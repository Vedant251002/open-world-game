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

// The gateways this Worker knows how to reach, and the secret each one wants.
//
// It began as one hardcoded URL, which was right while there was one gateway.
// A second one is worth having because it can be asked for constrained
// decoding — the reply then always parses, which removes the failure the game
// spends forty seconds discovering. Both speak the OpenAI chat-completions
// shape, so the only differences worth encoding are the address, the secret
// and what each calls its token budget.
const PROVIDERS = {
  groq: {
    upstream: "https://api.groq.com/openai/v1/chat/completions",
    secret: "GROQ_API_KEY",
    model: "GROQ_MODEL",
    defaultModel: "openai/gpt-oss-120b",
    tokenField: "max_completion_tokens",
  },
  opencode: {
    upstream: "https://opencode.ai/zen/v1/chat/completions",
    secret: "OPENCODE_API_KEY",
    model: "OPENCODE_MODEL",
    defaultModel: "nemotron-3-ultra-free",
    tokenField: "max_tokens",
  },
};

// Which one answers. The owner of the key decides, not the caller: a header
// naming a gateway is a hint about which build is asking, and the game sends
// it, but a proxy that lets a stranger choose its upstream is a proxy that can
// be pointed anywhere. So the env var wins, then whichever secret is actually
// set, and the header only breaks a tie.
function pickProvider(env, request) {
  const named = (env.AI_PROVIDER || "").trim();
  if (PROVIDERS[named]) return named;
  const hinted = (request?.headers.get("X-Provider") || "").trim();
  const order = ["groq", "opencode"];
  for (const name of order) {
    if ((env[PROVIDERS[name].secret] || "").trim()) return name;
  }
  return PROVIDERS[hinted] ? hinted : "opencode";
}

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

// Enough of the key to tell one from another, and not enough to be one. Eight
// hex characters of a SHA-256 cannot be walked back to a 67-character random
// string, but they answer the question that actually comes up — "is the key in
// the Worker the same one I meant to put there" — without anybody having to
// paste a secret anywhere to find out.
// The key, minus whatever the terminal attached to it.
//
// A secret pasted at a prompt very often arrives with a newline on the end,
// and an Authorization header with trailing whitespace is not a wrong key —
// it is a malformed header. The gateway's answer to that is a bare 400 with an
// empty body, which is indistinguishable from a broken proxy and sent me
// looking at User-Agents and network paths for half an hour. Cheaper to be
// forgiving here than to make anybody paste a secret twice.
function apiKey(env, provider) {
  return (env[PROVIDERS[provider].secret] || "").trim();
}

// The model the key's owner has chosen for that gateway.
function modelFor(env, provider) {
  const p = PROVIDERS[provider];
  return (env[p.model] || "").trim() || p.defaultModel;
}

async function fingerprint(secret) {
  if (!secret) return null;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(secret));
  return [...new Uint8Array(digest)].slice(0, 4)
    .map((b) => b.toString(16).padStart(2, "0")).join("");
}

// What you get for opening the URL in a browser.
//
// This used to be "POST only." and a 405, which is technically right and
// useless: opening the address is the first thing anyone does to see whether
// the thing is alive, and the answer they need is whether the key is in yet.
// So a GET says so. Nothing here is secret — the key is reduced to a
// fingerprint, and the allowed origins are in the repository already.
//
// `?check=1` goes further and actually spends one token proving the key works,
// because every field below can look perfect while the stored secret is a
// string that the gateway will not accept. Behind a flag rather than on by
// default: a health endpoint that calls out on every hit is a health endpoint
// somebody can point at a load generator.
async function health(env, request) {
  const provider = pickProvider(env, request);
  const raw = env[PROVIDERS[provider].secret] || "";
  const key = apiKey(env, provider);
  return {
    service: "DELEGATE AI proxy",
    ok: true,
    provider,
    secret_name: PROVIDERS[provider].secret,
    // Whether the reply is guaranteed to parse. The single most useful fact
    // about a deployment, and the one that is hardest to infer afterwards
    // from a log full of half-finished JSON.
    schema_locked: provider === "groq",
    key_configured: key.length > 0,
    // Of the key as used, so it can be compared against the one you meant to
    // store without anybody pasting a secret anywhere to check.
    key_fingerprint: await fingerprint(key),
    key_had_stray_whitespace: raw !== key,
    // Not the key, and not enough of it to be useful to anybody: a length and
    // four bytes of a hash. Enough to see at a glance that what got stored is
    // not what you meant to store, which is the failure this endpoint exists
    // to make visible.
    key_length: key.length,
    model: modelFor(env, provider),
    allow_native: env.ALLOW_NATIVE === "1",
    allowed_origins: ALLOWED_ORIGINS,
    usage: "POST the OpenAI chat-completions shape here. The game does this for you.",
    hint: "Add ?check=1 to make it prove the key works.",
  };
}


// Does the stored key actually buy anything? One token, so the answer costs
// almost nothing and means everything.
async function keyCheck(env, provider) {
  const key = apiKey(env, provider);
  if (!key) return { key_works: false, why: `no ${PROVIDERS[provider].secret} set` };
  try {
    const probe = { model: modelFor(env, provider), messages: [{ role: "user", content: "hi" }] };
    probe[PROVIDERS[provider].tokenField] = 1;
    const res = await fetch(PROVIDERS[provider].upstream, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${key}` },
      body: JSON.stringify(probe),
    });
    const text = await res.text();
    return {
      key_works: res.ok,
      upstream_status: res.status,
      why: res.ok ? "the gateway accepted it"
        : (text.slice(0, 200) || "the gateway refused it and said nothing"),
    };
  } catch (e) {
    return { key_works: false, why: "could not reach the gateway" };
  }
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

    // Open on purpose, and before the origin check: a browser navigating to
    // the address sends no Origin at all, and turning that away with a 403
    // would be the same unhelpfulness in a different colour.
    if (request.method === "GET" || request.method === "HEAD") {
      const body = await health(env, request);
      if (new URL(request.url).searchParams.get("check") === "1") {
        Object.assign(body, await keyCheck(env, pickProvider(env, request)));
      }
      return new Response(JSON.stringify(body, null, 2), {
        status: 200,
        headers: { "Content-Type": "application/json", ...corsHeaders(ok || "null") },
      });
    }

    if (!ok) {
      // No echo of what they sent, and no hint about what would be accepted.
      return fail(403, "Not an allowed origin.", null);
    }
    if (request.method !== "POST") {
      return fail(405, "POST only.", ok);
    }
    const provider = pickProvider(env, request);
    if (!apiKey(env, provider)) {
      return fail(500, "The proxy has no API key set. Run: wrangler secret put "
        + PROVIDERS[provider].secret, ok);
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
    // get an answer, just a bounded one. Both spellings are read and only the
    // one this gateway understands is sent, so a build that still says
    // max_tokens is not silently capped at the upstream default.
    const asked = Number(body.max_tokens ?? body.max_completion_tokens) || 1024;
    delete body.max_tokens;
    delete body.max_completion_tokens;
    body[PROVIDERS[provider].tokenField] = Math.min(asked, MAX_TOKENS_CAP);
    // Whatever the caller said, the key's owner picks the model.
    body.model = modelFor(env, provider);
    // response_format is forwarded untouched. It is the caller asking to be
    // held to a schema, it cannot cost anything, and stripping it would throw
    // away the one guarantee worth having.

    let upstream;
    try {
      upstream = await fetch(PROVIDERS[provider].upstream, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey(env, provider)}`,
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      return fail(502, "Could not reach the model.", ok);
    }

    // Read rather than stream it, so a refusal can be reported with whatever
    // the gateway actually said. It answers some bad requests with a bare 400
    // and no body at all, which tells the game nothing and tells whoever is
    // debugging it even less — so the status goes in the message where it can
    // be seen from the game's own log.
    const answer = await upstream.text();
    console.log(`upstream ${upstream.status} provider=${provider} model=${body.model} ` +
      `msgs=${body.messages.length} max_tokens=${body.max_tokens} ` +
      `bytes=${answer.length}`);

    if (!upstream.ok) {
      return new Response(JSON.stringify({
        error: {
          message: `The model gateway refused this (HTTP ${upstream.status}).`,
          upstream_status: upstream.status,
          upstream_body: answer.slice(0, 600),
        },
      }), {
        status: upstream.status,
        headers: { "Content-Type": "application/json", ...corsHeaders(ok) },
      });
    }

    // Upstream's own headers are dropped deliberately: nothing there is worth
    // forwarding and some of it names the account.
    return new Response(answer, {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders(ok) },
    });
  },
};
