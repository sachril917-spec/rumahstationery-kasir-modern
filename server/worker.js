
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
    

    // LAPORAN PENJUALAN UNTUK APK ADMIN
    if (url.pathname === "/admin/sales" && request.method === "GET") {
      if (!env.ADMIN_API_KEY || !env.DB_RUMAH_STATIONERY) {
        return json({
          success: false,
          message: "API_KEY atau database belum tersedia."
        }, 503);
      }

      if (request.headers.get("Authorization") !== `Bearer ${env.ADMIN_API_KEY}`) {
        return json({
          success: false,
          message: "Akses Admin ditolak."
        }, 401);
      }

      const date = url.searchParams.get("date") || "";

      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
        return json({
          success: false,
          message: "Format tanggal harus YYYY-MM-DD."
        }, 400);
      }

      try {
        const db = env.DB_RUMAH_STATIONERY;

        const [summary, branches, transactions] = await Promise.all([
          db.prepare(`
            SELECT
              COUNT(*) AS jumlah_transaksi,
              COALESCE(SUM(total), 0) AS total_penjualan
            FROM transactions
            WHERE substr(created_at, 1, 10) = ?
          `).bind(date).first(),

          db.prepare(`
            SELECT
              branch_id,
              COUNT(*) AS jumlah_transaksi,
              COALESCE(SUM(total), 0) AS total_penjualan
            FROM transactions
            WHERE substr(created_at, 1, 10) = ?
            GROUP BY branch_id
            ORDER BY total_penjualan DESC
          `).bind(date).all(),

          db.prepare(`
            SELECT
              id, branch_id, created_at,
              payment, total, payload
            FROM transactions
            WHERE substr(created_at, 1, 10) = ?
            ORDER BY created_at DESC
            LIMIT 500
          `).bind(date).all()
        ]);

        return json({
          success: true,
          tanggal: date,
          jumlah_transaksi: Number(summary?.jumlah_transaksi || 0),
          total_penjualan: Number(summary?.total_penjualan || 0),
          cabang: branches.results || [],
          transaksi: transactions.results || []
        });

      } catch (error) {
        return json({
          success: false,
          message: "Gagal mengambil laporan penjualan.",
          details: String(error?.message || error)
        }, 500);
      }
    }


// ENDPOINT ADMIN PUSAT ADL
if (url.pathname.startsWith("/admin/") && request.method === "GET") {
  const adminDb = env.DB_RUMAH_STATIONERY;

  if (!env.ADMIN_API_KEY || !adminDb) {
    return json({
      success: false,
      message: "ADMIN_API_KEY atau database belum tersedia."
    }, 503);
  }

  if (
    request.headers.get("Authorization") !==
    `Bearer ${env.ADMIN_API_KEY}`
  ) {
    return json({
      success: false,
      message: "Akses Admin ditolak."
    }, 401);
  }

  try {
    const date = url.searchParams.get("date") ||
      new Date().toISOString().slice(0, 10);

    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return json({
        success: false,
        message: "Format tanggal harus YYYY-MM-DD."
      }, 400);
    }

    if (url.pathname === "/admin/overview") {
      const [products, sales, expenses, branches] =
        await Promise.all([
          adminDb.prepare(`
            SELECT COUNT(*) AS count,
                   COALESCE(SUM(stock), 0) AS stock
            FROM products
          `).first(),

          adminDb.prepare(`
            SELECT COUNT(*) AS count,
                   COALESCE(SUM(total), 0) AS total
            FROM transactions
            WHERE substr(created_at, 1, 10) = ?
          `).bind(date).first(),

          adminDb.prepare(`
            SELECT COUNT(*) AS count,
                   COALESCE(SUM(amount), 0) AS total
            FROM expenses
            WHERE expense_date = ?
              AND deleted_at IS NULL
          `).bind(date).first(),

          adminDb.prepare(`
            SELECT branch_id,
                   COUNT(*) AS count,
                   COALESCE(SUM(total), 0) AS total
            FROM transactions
            WHERE substr(created_at, 1, 10) = ?
            GROUP BY branch_id
            ORDER BY total DESC
          `).bind(date).all()
        ]);

      return json({
        success: true,
        date,
        products: Number(products?.count || 0),
        total_stock: Number(products?.stock || 0),
        sales_count: Number(sales?.count || 0),
        sales_total: Number(sales?.total || 0),
        expenses_count: Number(expenses?.count || 0),
        expenses_total: Number(expenses?.total || 0),
        branch_sales: branches.results || []
      });
    }

    if (url.pathname === "/admin/products") {
      const result = await adminDb.prepare(`
        SELECT id, barcode, name, price, stock, updated_at
        FROM products
        ORDER BY name
        LIMIT 1000
      `).all();

      return json({
        success: true,
        products: result.results || []
      });
    }

    return json({
      success: false,
      message: "Endpoint admin tidak ditemukan."
    }, 404);

  } catch (error) {
    return json({
      success: false,
      message: "Gagal membaca data Admin.",
      details: String(error?.message || error)
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

    if (request.headers.get("Authorization") !== `Bearer ${env.API_KEY}`) {
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
