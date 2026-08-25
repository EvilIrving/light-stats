const FILE_RE = /^Light-Stats-\d[\w.+-]*\.dmg$/;
const STABLE_PATHS = new Set(["/stable", "/Light-Stats.dmg"]);
const BETA_PATHS = new Set(["/beta", "/Light-Stats-beta.dmg"]);

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname.replace(/\/$/, "") || "/";
    const isBeta = BETA_PATHS.has(path);
    if (!isBeta && !STABLE_PATHS.has(path)) {
      return new Response("Not found", { status: 404 });
    }

    const markerKey = isBeta ? "latest-beta.json" : "latest-stable.json";
    const marker = await env.RELEASES.get(markerKey);
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
    if (!FILE_RE.test(file)) {
      return new Response("Latest build marker is invalid", { status: 500 });
    }

    return Response.redirect(`https://download.onecat.dev/${file}`, 302);
  },
};
