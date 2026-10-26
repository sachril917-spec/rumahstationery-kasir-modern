
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

    if (url.pathname === "/health" && request.method === "GET") {
      try {
        if (!env.DB_RUMAH_STATIONERY) {
          return json({
            success: false,
            server: "aktif",
            database: "belum dikonfigurasi"
          }, 503);
        }

        await env.DB_RUMAH_STATIONERY.prepare("SELECT 1").first();

        return json({
          success: true,
          app: "Rumah Stationery Kasir",
          server: "aktif",
          database: "terhubung"
        });
      } catch (error) {
        return json({
          success: false,
          server: "aktif",
          database: "bermasalah",
          message: String(error?.message || error)
        }, 500);
      }
    }

    if (
      url.pathname !== "/sync/transactions" ||
      request.method !== "POST"
    ) {
      return json({
        success: false,
        message: "Endpoint tidak ditemukan."
      }, 404);
    }

    if (!env.API_KEY || !env.DB_RUMAH_STATIONERY) {
      return json({
        success: false,
        message: "API_KEY atau binding D1 belum dikonfigurasi."
      }, 503);
    }

    if (
      request.headers.get("Authorization") !==
      `Bearer ${env.API_KEY}`
    ) {
      return json({
        success: false,
        message: "API key tidak valid."
      }, 401);
    }

    let body;

    try {
      body = await request.json();
    } catch {
      return json({
        success: false,
        message: "JSON tidak valid."
      }, 400);
    }

    const { device_id, branch_id, transactions } = body ?? {};

    if (
      typeof device_id !== "string" || !device_id.trim() ||
      typeof branch_id !== "string" || !branch_id.trim() ||
      !Array.isArray(transactions) ||
      transactions.length < 1 ||
      transactions.length > 100
    ) {
      return json({
        success: false,
        message: "Data cabang, perangkat, atau daftar transaksi tidak valid."
      }, 400);
    }

    const db = env.DB_RUMAH_STATIONERY;
    const receivedAt = new Date().toISOString();
    const statements = [];

    // Periksa data satu per satu agar error menyebutkan kolomnya.
    for (let index = 0; index < transactions.length; index++) {
      const tx = transactions[index];
      const errors = [];

      if (!tx || typeof tx !== "object" || Array.isArray(tx)) {
        return json({
          success: false,
          message: "Data transaksi bukan objek yang valid.",
          transaction_index: index
        }, 400);
      }

      if (typeof tx.id !== "string" || !tx.id.trim()) {
        errors.push({
          field: "id",
          reason: "Harus berupa teks yang tidak kosong."
        });
      }

      if (
        typeof tx.payment !== "string" ||
        !["Tunai", "Transfer", "QRIS"].includes(tx.payment)
      ) {
        errors.push({
          field: "payment",
          received: tx.payment,
          received_type: typeof tx.payment,
          reason: "Harus berupa Tunai, Transfer, atau QRIS."
        });
      }

      if (
        typeof tx.amount_paid !== "number" ||
        !Number.isFinite(tx.amount_paid) ||
        tx.amount_paid < 0
      ) {
        errors.push({
          field: "amount_paid",
          received: tx.amount_paid,
          received_type: typeof tx.amount_paid,
          reason: "Harus berupa angka nol atau lebih."
        });
      }

      if (
        typeof tx.change_amount !== "number" ||
        !Number.isFinite(tx.change_amount) ||
        tx.change_amount < 0
      ) {
        errors.push({
          field: "change_amount",
          received: tx.change_amount,
          received_type: typeof tx.change_amount,
          reason: "Harus berupa angka nol atau lebih."
        });
      }

      if (
        typeof tx.total !== "number" ||
        !Number.isFinite(tx.total) ||
        tx.total < 0
      ) {
        errors.push({
          field: "total",
          received: tx.total,
          received_type: typeof tx.total,
          reason: "Harus berupa angka nol atau lebih."
        });
      }

      if (
        typeof tx.created_at !== "string" ||
        !tx.created_at.trim()
      ) {
        errors.push({
          field: "created_at",
          received: tx.created_at,
          reason: "Harus berupa teks tanggal yang tidak kosong."
        });
      }

      if (
        tx.payload === undefined ||
        tx.payload === null
      ) {
        errors.push({
          field: "payload",
          reason: "Data payload tidak dikirim."
        });
      }

      if (errors.length > 0) {
        return json({
          success: false,
          message: "Data transaksi tidak valid.",
          transaction_index: index,
          transaction_id: tx.id ?? null,
          errors
        }, 400);
      }

      if (
        tx.payment === "Tunai" &&
        tx.amount_paid < tx.total
      ) {
        return json({
          success: false,
          message: "Uang tunai kurang dari total transaksi.",
          transaction_index: index,
          transaction_id: tx.id,
          errors: [{
            field: "amount_paid",
            received: tx.amount_paid,
            expected_minimum: tx.total
          }]
        }, 400);
      }

      if (
        tx.payment === "Tunai" &&
        tx.change_amount !== tx.amount_paid - tx.total
      ) {
        return json({
          success: false,
          message: "Nominal kembalian tidak sesuai.",
          transaction_index: index,
          transaction_id: tx.id,
          errors: [{
            field: "change_amount",
            received: tx.change_amount,
            expected: tx.amount_paid - tx.total
          }]
        }, 400);
      }

      if (
        tx.payment !== "Tunai" &&
        tx.change_amount !== 0
      ) {
        return json({
          success: false,
          message: "Pembayaran non-tunai tidak boleh memiliki kembalian.",
          transaction_index: index,
          transaction_id: tx.id,
          errors: [{
            field: "change_amount",
            received: tx.change_amount,
            expected: 0
          }]
        }, 400);
      }

      let payload;

      try {
        payload = typeof tx.payload === "string"
          ? tx.payload
          : JSON.stringify(tx.payload);
      } catch {
        return json({
          success: false,
          message: "Payload transaksi tidak dapat diproses.",
          transaction_index: index,
          transaction_id: tx.id,
          errors: [{
            field: "payload",
            reason: "Gagal mengubah payload menjadi JSON."
          }]
        }, 400);
      }

      statements.push(
        db.prepare(`
          INSERT OR IGNORE INTO transactions
            (id, total, payment, amount_paid, change_amount,
             created_at, branch_id, device_id, payload, received_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).bind(
          tx.id,
          tx.total,
          tx.payment,
          tx.amount_paid,
          tx.change_amount,
          tx.created_at,
          branch_id,
          device_id,
          payload,
          receivedAt
        )
      );
    }

    try {
      const results = await db.batch(statements);

      const inserted = results.reduce(
        (sum, result) => sum + (result.meta?.changes ?? 0),
        0
      );

      return json({
        success: true,
        received: transactions.length,
        inserted,
        duplicates: transactions.length - inserted,
        message: "Transaksi diterima server."
      });
    } catch (error) {
      return json({
        success: false,
        message: "Gagal menyimpan transaksi ke D1.",
        details: String(error?.message || error)
      }, 500);
    }
  }
};
