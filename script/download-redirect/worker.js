const LIGHT_STATS_FILE_RE = /^Light-Stats-\d[\w.+-]*\.dmg$/;
const CHARGE_LIMITER_FILE_RE = /^Charge-Limiter-\d[\w.+-]*\.dmg$/;

const ROUTES = new Map([
  ["/stable", { marker: "latest-stable.json", filePattern: LIGHT_STATS_FILE_RE }],
  ["/Light-Stats.dmg", { marker: "latest-stable.json", filePattern: LIGHT_STATS_FILE_RE }],
  ["/beta", { marker: "latest-beta.json", filePattern: LIGHT_STATS_FILE_RE }],
  ["/Light-Stats-beta.dmg", { marker: "latest-beta.json", filePattern: LIGHT_STATS_FILE_RE }],
  ["/charge-limiter", { marker: "charge-limiter-latest.json", filePattern: CHARGE_LIMITER_FILE_RE }],
]);

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname.replace(/\/$/, "") || "/";
    const route = ROUTES.get(path);
    if (!route) {
      return new Response("Not found", { status: 404 });
    }

    const marker = await env.RELEASES.get(route.marker);
    if (marker === null) {
      return new Response("Latest build marker missing", { status: 404 });
    }

    let parsed;
    try {
      parsed = await marker.json();
    } catch {
      return new Response("Latest build marker is invalid", { status: 500 });
    }

    const file = typeof parsed.file === "string" ? parsed.file : "";
    if (!route.filePattern.test(file)) {
      return new Response("Latest build marker is invalid", { status: 500 });
    }

    return Response.redirect(`https://download.onecat.dev/${file}`, 302);
  },
};
