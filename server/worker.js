
export default {
  async fetch(request, env) {
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Content-Type": "application/json; charset=utf-8"
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: cors });
    }

    const url = new URL(request.url);

    // Tes apakah server aktif
    if (url.pathname === "/health" && request.method === "GET") {
      return Response.json({
        success: true,
        app: "Rumah Stationery Kasir",
        server: "aktif",
        database: env.DB_RUMAH_STATIONERY ? "terhubung" : "belum dikonfigurasi",
        sync: "belum diaktifkan"
      }, { headers: cors });
    }

    // Endpoint lain belum diaktifkan
    return Response.json({
      success: false,
      message: "API kasir belum dikonfigurasi."
    }, {
      status: 404,
      headers: cors
    });
  }
};
