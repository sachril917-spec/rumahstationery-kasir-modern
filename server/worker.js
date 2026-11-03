export default {
  async fetch(request, env) {
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Content-Type": "application/json; charset=utf-8"
    };
    const json = (data, status = 200) =>
      new Response(JSON.stringify(data), { status, headers: cors });

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    const url = new URL(request.url);
    const db = env.DB_RUMAH_STATIONERY;
    const authorized = () => Boolean(env.API_KEY) &&
      request.headers.get("Authorization") === `Bearer ${env.API_KEY}`;

    function readItems(raw) {
      const payload = typeof raw === "string" ? JSON.parse(raw) : raw;
      const items = Array.isArray(payload) ? payload : payload?.items;
      if (!Array.isArray(items) || items.length === 0) {
        throw new Error("Payload harus berisi items berupa array yang tidak kosong.");
      }
      return items;
    }

    function itemStatement(transactionId, item, index) {
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        throw new Error(`Barang ke-${index + 1} bukan objek yang valid.`);
      }
      const productId = item.id == null ? null : String(item.id);
      const productName = typeof item.name === "string" ? item.name.trim() : "";
      const quantity = Number(item.qty);
      const price = Number(item.price);
      const discount = Number(item.discount ?? 0);

      if (!productName) throw new Error(`Nama barang ke-${index + 1} kosong.`);
      if (!Number.isInteger(quantity) || quantity < 1) {
        throw new Error(`Jumlah barang ke-${index + 1} tidak valid.`);
      }
      if (!Number.isFinite(price) || price < 0) {
        throw new Error(`Harga barang ke-${index + 1} tidak valid.`);
      }
      if (!Number.isFinite(discount) || discount < 0) {
        throw new Error(`Diskon barang ke-${index + 1} tidak valid.`);
      }

      const subtotal = Math.max(0, price * quantity - discount);
      // ID yang stabil membuat pengiriman ulang tidak menggandakan rincian.
      const itemId = `${transactionId}:${index}`;
      return db.prepare(`
        INSERT OR IGNORE INTO transaction_items
          (id, transaction_id, product_id, product_name, quantity, price, subtotal)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).bind(itemId, transactionId, productId, productName, quantity, price, subtotal);
    }

    if (url.pathname === "/health" && request.method === "GET") {
      try {
        if (!db) return json({ success: false, server: "aktif", database: "belum dikonfigurasi" }, 503);
        await db.prepare("SELECT 1").first();
        return json({ success: true, app: "Rumah Stationery Kasir", server: "aktif", database: "terhubung" });
      } catch (error) {
        return json({ success: false, server: "aktif", database: "bermasalah", message: String(error?.message || error) }, 500);
      }
    }

    if (url.pathname === "/updates" && request.method === "GET") {
      return json({
        success: true,
        app: "Rumah Stationery Kasir",
        android: {
          version: env.UPDATE_ANDROID_VERSION || "",
          url: env.UPDATE_ANDROID_URL || "",
          sha256: env.UPDATE_ANDROID_SHA256 || "",
          notes: env.UPDATE_ANDROID_NOTES || ""
        },
        windows: {
          version: env.UPDATE_WINDOWS_VERSION || "",
          url: env.UPDATE_WINDOWS_URL || "",
          sha256: env.UPDATE_WINDOWS_SHA256 || "",
          notes: env.UPDATE_WINDOWS_NOTES || ""
        }
      });
    }

    if (!db || !env.API_KEY) {
      return json({ success: false, message: "API_KEY atau binding D1 belum dikonfigurasi." }, 503);
    }

    // Jalankan berulang untuk mengisi rincian transaksi lama yang masih kosong.
    if (url.pathname === "/admin/backfill-items" && request.method === "POST") {
      if (!authorized()) return json({ success: false, message: "API key tidak valid." }, 401);
      try {
        const oldRows = await db.prepare(`
          SELECT t.id, t.payload
          FROM transactions t
          WHERE NOT EXISTS (
            SELECT 1 FROM transaction_items i WHERE i.transaction_id = t.id
          )
          ORDER BY t.created_at ASC
          LIMIT 100
        `).all();

        const statements = [];
        let scanned = 0;
        let skipped = 0;
        for (const tx of (oldRows.results || [])) {
          let items;
          try {
            items = readItems(tx.payload);
            const pending = items.map((item, i) => itemStatement(tx.id, item, i));
            if (statements.length + pending.length > 500) break;
            statements.push(...pending);
            scanned++;
          } catch (error) {
            skipped++;
          }
        }

        const results = statements.length ? await db.batch(statements) : [];
        const insertedItems = results.reduce((sum, r) => sum + (r.meta?.changes ?? 0), 0);
        return json({
          success: true,
          scanned,
          inserted_items: insertedItems,
          skipped,
          message: "Kelompok backfill selesai. Periksa remaining dengan memanggil endpoint ini lagi."
        });
      } catch (error) {
        return json({ success: false, message: "Backfill gagal.", details: String(error?.message || error) }, 500);
      }
    }

    if (url.pathname !== "/sync/transactions" || request.method !== "POST") {
      return json({ success: false, message: "Endpoint tidak ditemukan." }, 404);
    }
    if (!authorized()) return json({ success: false, message: "API key tidak valid." }, 401);

    let body;
    try { body = await request.json(); }
    catch { return json({ success: false, message: "JSON tidak valid." }, 400); }

    const { device_id, branch_id, transactions } = body ?? {};
    if (typeof device_id !== "string" || !device_id.trim() ||
        typeof branch_id !== "string" || !branch_id.trim() ||
        !Array.isArray(transactions) || transactions.length < 1 || transactions.length > 100) {
      return json({ success: false, message: "Data cabang, perangkat, atau daftar transaksi tidak valid." }, 400);
    }

    const statements = [];
    const transactionIndexes = [];
    let totalItems = 0;
    const receivedAt = new Date().toISOString();

    for (let index = 0; index < transactions.length; index++) {
      const tx = transactions[index];
      if (!tx || typeof tx !== "object" || Array.isArray(tx)) {
        return json({ success: false, message: "Data transaksi bukan objek yang valid.", transaction_index: index }, 400);
      }
      if (typeof tx.id !== "string" || !tx.id.trim()) {
        return json({ success: false, message: "ID transaksi tidak valid.", transaction_index: index }, 400);
      }
      if (! ["Tunai", "Transfer", "QRIS"].includes(tx.payment)) {
        return json({ success: false, message: "Metode pembayaran harus Tunai, Transfer, atau QRIS.", transaction_id: tx.id }, 400);
      }
      for (const field of ["total", "amount_paid", "change_amount"]) {
        if (typeof tx[field] !== "number" || !Number.isFinite(tx[field]) || tx[field] < 0) {
          return json({ success: false, message: `Kolom ${field} tidak valid.`, transaction_id: tx.id }, 400);
        }
      }
      if (typeof tx.created_at !== "string" || !tx.created_at.trim()) {
        return json({ success: false, message: "Tanggal transaksi tidak valid.", transaction_id: tx.id }, 400);
      }
      if (tx.payment === "Tunai" && tx.amount_paid < tx.total) {
        return json({ success: false, message: "Uang tunai kurang dari total transaksi.", transaction_id: tx.id }, 400);
      }
      if (tx.payment === "Tunai" && tx.change_amount !== tx.amount_paid - tx.total) {
        return json({ success: false, message: "Nominal kembalian tidak sesuai.", transaction_id: tx.id }, 400);
      }
      if (tx.payment !== "Tunai" && tx.change_amount !== 0) {
        return json({ success: false, message: "Pembayaran non-tunai tidak boleh memiliki kembalian.", transaction_id: tx.id }, 400);
      }

      let items;
      let payload;
      try {
        items = readItems(tx.payload);
        payload = typeof tx.payload === "string" ? tx.payload : JSON.stringify(tx.payload);
      } catch (error) {
        return json({ success: false, message: "Payload transaksi tidak valid.", transaction_id: tx.id, details: String(error?.message || error) }, 400);
      }
      totalItems += items.length;
      if (totalItems > 500) return json({ success: false, message: "Maksimal 500 rincian barang per permintaan." }, 413);

      transactionIndexes.push(statements.length);
      statements.push(db.prepare(`
        INSERT OR IGNORE INTO transactions
          (id, total, payment, amount_paid, change_amount, created_at,
           branch_id, device_id, payload, received_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).bind(tx.id, tx.total, tx.payment, tx.amount_paid, tx.change_amount,
        tx.created_at, branch_id, device_id, payload, receivedAt));

      try {
        items.forEach((item, itemIndex) => {
          statements.push(itemStatement(tx.id, item, itemIndex));
        });
      } catch (error) {
        return json({ success: false, message: "Rincian barang tidak valid.", transaction_id: tx.id, details: String(error?.message || error) }, 400);
      }
    }

    try {
      const results = await db.batch(statements);
      const insertedTransactions = transactionIndexes.reduce(
        (sum, i) => sum + (results[i]?.meta?.changes ?? 0), 0
      );
      const transactionIndexSet = new Set(transactionIndexes);
      const insertedItems = results.reduce(
        (sum, result, i) => transactionIndexSet.has(i) ? sum : sum + (result.meta?.changes ?? 0), 0
      );
      return json({
        success: true,
        received: transactions.length,
        inserted: insertedTransactions,
        duplicates: transactions.length - insertedTransactions,
        received_items: totalItems,
        inserted_items: insertedItems,
        duplicate_items: totalItems - insertedItems,
        message: "Transaksi dan rincian barang diterima server."
      });
    } catch (error) {
      return json({ success: false, message: "Gagal menyimpan transaksi atau rincian barang ke D1.", details: String(error?.message || error) }, 500);
    }
  }
};
