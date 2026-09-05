// What the proxy has to get right, checked against the real handler.
//
// Two of these matter more than the rest. The preflight has to be answered,
// because that is the thing OpenCode Zen does not do and the only reason this
// file's subject exists. And the key has to go out on the upstream request and
// never come back on the response — a proxy that leaks its own key is worse
// than no proxy, because it looks like it is working.
//
//   node test.mjs            the handler on its own, no network
//   OPENCODE_API_KEY=... node test.mjs --live    plus one real call
//
// Run with --live before trusting a deployment: everything else here would
// pass just as happily against a model that had been switched off.

import worker from "./worker.js";

const GOOD = "https://vedant251002.github.io";
const KEY = "test-key-not-a-real-one";

let failed = 0;
function ok(cond, what) {
  console.log(`  ${cond ? "PASS" : "FAIL"} ${what}`);
  if (!cond) failed++;
}

function post(origin, body, headers = {}) {
  const h = { "Content-Type": "application/json", ...headers };
  if (origin) h["Origin"] = origin;
  return new Request("https://proxy.example/", {
    method: "POST",
    headers: h,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const PLAN = { model: "x", messages: [{ role: "user", content: "hello" }] };

// Stands in for OpenCode Zen so the handler can be checked without spending a
// call, and so the outgoing request can be read.
function stubUpstream() {
  const seen = {};
  const real = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    seen.url = String(url);
    seen.auth = init.headers["Authorization"];
    seen.body = JSON.parse(init.body);
    return new Response(JSON.stringify({ choices: [{ message: { content: "{}" } }] }), {
      status: 200,
      headers: { "Content-Type": "application/json", "x-account-id": "leak-me" },
    });
  };
  return { seen, restore: () => { globalThis.fetch = real; } };
}

async function main() {
  const env = { OPENCODE_API_KEY: KEY, OPENCODE_MODEL: "chosen-model" };

  console.log("[proxy] the preflight, which is the whole reason for this file");
  {
    const res = await worker.fetch(
      new Request("https://proxy.example/", {
        method: "OPTIONS",
        headers: {
          Origin: GOOD,
          "Access-Control-Request-Method": "POST",
          "Access-Control-Request-Headers": "content-type",
        },
      }), env);
    ok(res.status === 204, `answered 204 (got ${res.status})`);
    ok(res.headers.get("Access-Control-Allow-Origin") === GOOD,
      "allows the game's origin by name, not '*'");
    ok((res.headers.get("Access-Control-Allow-Headers") || "").includes("content-type"),
      "allows the content-type header the game sends");
  }

  console.log("[proxy] who is allowed to ask");
  {
    const bad = await worker.fetch(
      new Request("https://proxy.example/", {
        method: "OPTIONS", headers: { Origin: "https://somebody-else.example" },
      }), env);
    ok(bad.status === 403, `a stranger's preflight is refused (got ${bad.status})`);

    const noOrigin = await worker.fetch(post(null, PLAN), env);
    ok(noOrigin.status === 403, "a request with no origin at all is refused");

    const stranger = await worker.fetch(post("https://somebody-else.example", PLAN), env);
    ok(stranger.status === 403, "a stranger's POST is refused");
  }

  console.log("[proxy] the key");
  {
    const { seen, restore } = stubUpstream();
    const res = await worker.fetch(post(GOOD, PLAN), env);
    const text = await res.text();
    restore();
    ok(seen.auth === `Bearer ${KEY}`, "goes out on the upstream request");
    ok(!text.includes(KEY), "never comes back in the response body");
    ok(![...res.headers.values()].some((v) => v.includes(KEY)),
      "never comes back in a response header");
    ok(res.headers.get("x-account-id") === null,
      "upstream's own headers are dropped rather than forwarded");
    ok(res.headers.get("Access-Control-Allow-Origin") === GOOD,
      "the answer carries the CORS header too, not just the preflight");
  }
  {
    const res = await worker.fetch(post(GOOD, PLAN), { OPENCODE_MODEL: "m" });
    ok(res.status === 500, "an unconfigured proxy says so instead of calling out");
  }
  {
    // The game sends none, and a caller who sends one must not get to use it.
    const { seen, restore } = stubUpstream();
    await worker.fetch(post(GOOD, PLAN, { Authorization: "Bearer somebody-elses-key" }), env);
    restore();
    ok(seen.auth === `Bearer ${KEY}`, "a client-supplied one is ignored, not passed on");
  }

  console.log("[proxy] what it forwards");
  {
    const { seen, restore } = stubUpstream();
    await worker.fetch(post(GOOD, { ...PLAN, max_tokens: 999999 }), env);
    restore();
    ok(seen.body.max_tokens === 4096, `max_tokens clamped (got ${seen.body.max_tokens})`);
    ok(seen.body.model === "chosen-model", "the key's owner picks the model, not the caller");
    ok(seen.url.startsWith("https://opencode.ai/"), "sent to OpenCode Zen");
  }
  {
    const junk = await worker.fetch(post(GOOD, "not json at all"), env);
    ok(junk.status === 400, "junk is refused before it reaches the model");
    const empty = await worker.fetch(post(GOOD, { messages: [] }), env);
    ok(empty.status === 400, "an empty conversation is refused too");
    const huge = await worker.fetch(post(GOOD, "x".repeat(70 * 1024)), env);
    ok(huge.status === 413, "an oversized body is refused");
    const put = await worker.fetch(
      new Request("https://proxy.example/", { method: "PUT", headers: { Origin: GOOD } }), env);
    ok(put.status === 405, "a method that is neither GET nor POST is refused");
  }

  console.log("[proxy] opening the address in a browser");
  {
    // A browser navigating to the URL sends no Origin at all, so this has to
    // answer without one — and it has to answer with something worth reading.
    // "POST only." and a 405 was correct and told nobody anything.
    const res = await worker.fetch(new Request("https://proxy.example/"), env);
    ok(res.status === 200, `answers a plain visit (got ${res.status})`);
    const body = await res.json();
    ok(body.key_configured === true, "says whether the key is in yet");
    ok(body.key_length === KEY.length, "says how long the stored key is");
    ok(typeof body.key_fingerprint === "string" && body.key_fingerprint.length === 8,
      "fingerprints the key rather than showing it");
    ok(!JSON.stringify(body).includes(KEY), "and does not leak the key itself");

    const none = await worker.fetch(new Request("https://proxy.example/"),
      { OPENCODE_MODEL: "m" });
    const nobody = await none.json();
    ok(nobody.key_configured === false, "and says so when there is no key");
  }

  console.log("[proxy] a key that got half-pasted");
  {
    // The failure this actually hit: a secret stored with a newline on the end
    // makes the Authorization header malformed, and the gateway answers a bare
    // 400 with no body — which looks exactly like a broken proxy.
    const { seen, restore } = stubUpstream();
    await worker.fetch(post(GOOD, PLAN), { ...env, OPENCODE_API_KEY: `${KEY}
` });
    restore();
    ok(seen.auth === `Bearer ${KEY}`, "a trailing newline is trimmed off before use");

    const res = await worker.fetch(new Request("https://proxy.example/"),
      { ...env, OPENCODE_API_KEY: `  ${KEY}  ` });
    const body = await res.json();
    ok(body.key_had_stray_whitespace === true, "and the visit page says it happened");
    ok(body.key_length === KEY.length, "reporting the length as used, not as stored");
  }

  console.log("[proxy] when the gateway refuses");
  {
    // An empty 400 passed straight through tells the game nothing. The status
    // has to survive into something readable.
    const real = globalThis.fetch;
    globalThis.fetch = async () => new Response("", { status: 400 });
    const res = await worker.fetch(post(GOOD, PLAN), env);
    globalThis.fetch = real;
    const body = await res.json();
    ok(res.status === 400, "the status is passed through");
    ok(body.error.upstream_status === 400, "and named in the body");
    ok(String(body.error.message).length > 20, "with something a person can read");
  }

  if (process.argv.includes("--live")) {
    console.log("[proxy] one real call, end to end");
    const key = process.env.OPENCODE_API_KEY;
    if (!key) {
      console.log("  SKIP no OPENCODE_API_KEY in the environment");
    } else {
      const res = await worker.fetch(post(GOOD, {
        model: "ignored",
        max_tokens: 32,
        messages: [{ role: "user", content: "Reply with the single word: ready" }],
      }), { OPENCODE_API_KEY: key, OPENCODE_MODEL: process.env.OPENCODE_MODEL || "nemotron-3-ultra-free" });
      const text = await res.text();
      ok(res.status === 200, `the model answered (got ${res.status})`);
      ok(!text.includes(key), "and the key is not in what came back");
      let content = "";
      try { content = JSON.parse(text).choices?.[0]?.message?.content ?? ""; } catch {}
      ok(content.length > 0, `there is an answer in it: ${JSON.stringify(content.slice(0, 60))}`);
    }
  }

  console.log(failed === 0 ? "[proxy] === PASS ===" : `[proxy] === FAIL (${failed}) ===`);
  process.exit(failed === 0 ? 0 : 1);
}

main();
