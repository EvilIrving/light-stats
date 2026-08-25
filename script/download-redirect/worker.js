const FILE_RE = /^Light-Stats-\d[\w.+-]*\.dmg$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const isBeta = url.pathname === "/Light-Stats-beta.dmg";
    if (url.pathname !== "/Light-Stats.dmg" && !isBeta) {
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
