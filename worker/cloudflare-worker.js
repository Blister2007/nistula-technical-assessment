/**
 * Cloudflare Worker — Anthropic API Proxy (with auth)
 *
 * Two secrets live here as Cloudflare environment variables:
 *
 *   ANTHROPIC_API_KEY  - the real Anthropic key (used to call api.anthropic.com)
 *   PROXY_AUTH_TOKEN   - a shared secret between this Worker and our backend
 *
 * Every incoming request must include the header:
 *     x-proxy-auth: <PROXY_AUTH_TOKEN value>
 *
 * If the header is missing or wrong, the Worker returns 401. Without this,
 * anyone who knew the Worker URL could call it and burn the Anthropic key.
 *
 * Setup (one time):
 *   1. npm install -g wrangler
 *   2. wrangler login
 *   3. wrangler secret put ANTHROPIC_API_KEY   (paste the Anthropic key)
 *   4. wrangler secret put PROXY_AUTH_TOKEN    (paste any long random string)
 *   5. wrangler deploy
 *
 * Put the WORKER_URL and the same PROXY_AUTH_TOKEN value into the backend .env.
 */

export default {
  async fetch(request, env) {
    // CORS preflight, in case anything browser-side ever calls this
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST",
          "Access-Control-Allow-Headers": "Content-Type, x-proxy-auth",
        },
      });
    }

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    // ── AUTH CHECK ──────────────────────────────────────────────
    // Only requests with the right shared-secret header get through.
    const expectedToken = env.PROXY_AUTH_TOKEN;
    const providedToken = request.headers.get("x-proxy-auth");

    if (!expectedToken) {
      return jsonError("Proxy auth token not configured on Worker", 500);
    }
    if (providedToken !== expectedToken) {
      return jsonError("Unauthorized", 401);
    }

    // ── ANTHROPIC KEY CHECK ─────────────────────────────────────
    const apiKey = env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      return jsonError("API key not configured on Worker", 500);
    }

    // ── FORWARD TO ANTHROPIC ────────────────────────────────────
    try {
      const body = await request.json();

      const upstream = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: body.model || "claude-sonnet-4-20250514",
          max_tokens: body.max_tokens || 1000,
          system: body.system,
          messages: body.messages,
        }),
      });

      const data = await upstream.text();

      return new Response(data, {
        status: upstream.status,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    } catch (err) {
      return jsonError(err.message, 500);
    }
  },
};

function jsonError(message, status) {
  return new Response(JSON.stringify({ error: message }), {
    status: status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
