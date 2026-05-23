

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
