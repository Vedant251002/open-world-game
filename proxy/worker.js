// One job: let the browser build talk to OpenCode Zen without the key ever
// being in the browser.
//
// The reason this exists at all is CORS. OpenCode Zen sends no
// Access-Control-Allow-Origin header, so a browser refuses the request before
// it is even sent — it is not a phone limitation and not something a setting
// in the game can fix. Any browser build needs something on a server in the
// middle, and that something may as well be the thing that holds the key.
//
// The key lives in this Worker's environment (`wrangler secret put`), never in
// the repository, never in the exported build, and never in a response. The
// game sends no Authorization header at all and could not leak one if it tried.
//
// Deliberately small. It checks the origin, caps the size, forces the model
// and the token budget into a sane range, and forwards. It is not an API
// gateway and should not grow into one.

const UPSTREAM = "https://opencode.ai/zen/v1/chat/completions";

// Who is allowed to ask. An open proxy with somebody's key behind it is a
// donation to whoever finds the URL, so this is an allowlist and not a "*".
const ALLOWED_ORIGINS = [
  "https://vedant251002.github.io",
  "http://localhost:8060",
  "http://127.0.0.1:8060",
];

// The game asks for 3200 and the free models cap out well below a number that
// would cost anything, but a proxy that forwards whatever it is handed is a
// proxy that can be asked for a million tokens by someone else.
const MAX_TOKENS_CAP = 4096;
const MAX_BODY_BYTES = 64 * 1024;

function corsHeaders(origin) {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

// A browser always sends Origin on a cross-origin request, so an allowlist is
// a real check for the case this proxy exists to serve. Nothing else does, and
// anything that is not a browser can simply leave it off — so requests without
// one are refused unless the owner deliberately turns them on with
// ALLOW_NATIVE, which is what the local dev server does.
//
// Native builds do not need this anyway: they can hold a key and call the API
// directly, which is what the game does when no proxy is configured.
function allow(request, env) {
  const origin = request.headers.get("Origin");
  if (origin) return ALLOWED_ORIGINS.includes(origin) ? origin : null;
  return env.ALLOW_NATIVE === "1" ? "null" : null;
}

function fail(status, message, origin) {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders(origin || "null") },
  });
}

export default {
  async fetch(request, env) {
    const ok = allow(request, env);

    // The preflight. This is the request that fails against OpenCode Zen
    // directly, and answering it is most of the point of this file.
    if (request.method === "OPTIONS") {
      if (!ok) return new Response(null, { status: 403 });
      return new Response(null, { status: 204, headers: corsHeaders(ok) });
    }

    if (request.method !== "POST") {
      return fail(405, "POST only.", ok);
    }
    if (!ok) {
      // No echo of what they sent, and no hint about what would be accepted.
      return fail(403, "Not an allowed origin.", null);
    }
    if (!env.OPENCODE_API_KEY) {
      return fail(500, "The proxy has no API key set. Run: wrangler secret put OPENCODE_API_KEY", ok);
    }

    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) {
      return fail(413, "Request too large.", ok);
    }

    let body;
    try {
      body = JSON.parse(raw);
    } catch (e) {
      return fail(400, "Body is not JSON.", ok);
    }
    if (!Array.isArray(body.messages) || body.messages.length === 0) {
      return fail(400, "No messages.", ok);
    }

    // Clamp rather than reject: a request that is merely greedy should still
    // get an answer, just a bounded one.
    body.max_tokens = Math.min(Number(body.max_tokens) || 1024, MAX_TOKENS_CAP);
    // Whatever the caller said, the key's owner picks the model.
    body.model = env.OPENCODE_MODEL || body.model || "nemotron-3-ultra-free";

    let upstream;
    try {
      upstream = await fetch(UPSTREAM, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${env.OPENCODE_API_KEY}`,
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      return fail(502, "Could not reach the model.", ok);
    }

    // Pass the answer through as it came, with the headers a browser needs.
    // Upstream's own headers are dropped deliberately: nothing there is worth
    // forwarding and some of it names the account.
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { "Content-Type": "application/json", ...corsHeaders(ok) },
    });
  },
};
