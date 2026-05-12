/**
 * Cloudflare Worker — Anthropic API Proxy
 *
 * Holds the Anthropic API key as a Cloudflare secret so it never leaks
 * into the backend codebase or the deployed environment.
 *
 * The Nistula FastAPI backend posts to this Worker's URL. The Worker
 * attaches the real key and forwards the request to api.anthropic.com,
 * then passes the response straight back.
 *
 * Same pattern I used for Thine (the Memory Debt Audit tool).
 *
 * Setup:
 *   1. Install wrangler: npm install -g wrangler
 *   2. wrangler login
 *   3. wrangler secret put ANTHROPIC_API_KEY   (paste the key when prompted)
 *   4. wrangler deploy
 *
 *   Wrangler prints a URL like https://nistula-claude-proxy.your-name.workers.dev
 *   Put that URL in your backend .env as WORKER_URL.
 */

export default {
  async fetch(request, env) {
    // CORS preflight, in case anything browser-side ever calls this
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    // The API key lives only here, as a Cloudflare secret.
    const API_KEY = env.ANTHROPIC_API_KEY;
    if (!API_KEY) {
      return jsonError("API key not configured on Worker", 500);
    }

    try {
      const body = await request.json();

      const upstream = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": API_KEY,
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
