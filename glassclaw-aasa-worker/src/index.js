const AASA = JSON.stringify({
  applinks: {
    apps: [],
    details: [
      {
        appID: "G2HJ6YM2ZB.cl.zro.glassclaw",
        paths: ["*"],
      },
    ],
  },
});

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/.well-known/apple-app-site-association") {
      return new Response(AASA, {
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "public, max-age=86400",
        },
      });
    }

    return new Response("GlassClaw AASA server", { status: 200 });
  },
};
