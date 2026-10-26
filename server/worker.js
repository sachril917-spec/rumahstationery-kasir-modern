export default {
  async fetch(request, env) {
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Content-Type": "application/json; charset=utf-8"
    };
    const json = (data, status = 200) => Response.json(data, { status, headers: cors });
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    const url = new URL(request.url);

    if (url.pathname === "/health" && request.method === "GET") {
      return json({success:true, app:"Rumah Stationery Kasir", server:"aktif",
        database:env.DB_RUMAH_STATIONERY ? "terhubung" : "belum dikonfigurasi"});
    }
    if (url.pathname !== "/sync/transactions" || request.method !== "POST")
      return json({success:false,message:"Endpoint tidak ditemukan."},404);
    if (!env.DB_RUMAH_STATIONERY || !env.API_KEY)
      return json({success:false,message:"Database atau API_KEY belum dikonfigurasi."},503);
    if (request.headers.get("Authorization") !== `Bearer ${env.API_KEY}`)
      return json({success:false,message:"API key tidak valid."},401);

    let body;
    try { body = await request.json(); }
    catch { return json({success:false,message:"JSON tidak valid."},400); }
    const {device_id,branch_id,transactions} = body ?? {};
    if (typeof device_id !== "string" || !device_id.trim() ||
        typeof branch_id !== "string" || !branch_id.trim() ||
        !Array.isArray(transactions) || transactions.length < 1 || transactions.length > 100)
      return json({success:false,message:"Data kiriman tidak valid."},400);

    try {
      const db = env.DB_RUMAH_STATIONERY, receivedAt = new Date().toISOString();
      let inserted = 0;
      for (const tx of transactions) {
        if (typeof tx.id !== "string" || !tx.id.trim() ||
            typeof tx.payment !== "string" || !["Tunai","Transfer","QRIS"].includes(tx.payment) ||
            typeof tx.amount_paid !== "number" || !Number.isFinite(tx.amount_paid) || tx.amount_paid < 0 ||
            typeof tx.change_amount !== "number" || !Number.isFinite(tx.change_amount) || tx.change_amount < 0 ||
            typeof tx.created_at !== "string" ||
            typeof tx.total !== "number" || !Number.isFinite(tx.total) || tx.total < 0 ||
            tx.payload === undefined)
          return json({success:false,message:"Data transaksi tidak valid."},400);
        if (tx.payment === "Tunai" && tx.amount_paid < tx.total)
          return json({success:false,message:"Uang tunai kurang dari total transaksi."},400);
        if (tx.payment !== "Tunai" && tx.change_amount !== 0)
          return json({success:false,message:"Pembayaran non-tunai tidak boleh memiliki kembalian."},400);
        const payload = typeof tx.payload === "string" ? tx.payload : JSON.stringify(tx.payload);
        const result = await db.prepare(`INSERT OR IGNORE INTO transactions
          (id,total,payment,amount_paid,change_amount,created_at,branch_id,device_id,payload,received_at)
          VALUES(?,?,?,?,?,?,?,?,?,?)`)
          .bind(tx.id,tx.total,tx.payment,tx.amount_paid,tx.change_amount,tx.created_at,
            branch_id,device_id,payload,receivedAt).run();
        inserted += result.meta.changes || 0;
      }
      return json({success:true,received:transactions.length,inserted,
        duplicates:transactions.length-inserted,message:"Transaksi diterima server"});
    } catch (e) {
      return json({success:false,message:"Gagal menyimpan transaksi. Pastikan kolom D1 amount_paid sudah ditambahkan."},500);
    }
  }
};
