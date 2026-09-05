# The AI proxy

The browser build of DELEGATE cannot call OpenCode Zen. That is not a phone
problem, a Godot problem or a missing setting — it is CORS:

```
POST https://opencode.ai/zen/v1/chat/completions
  -> 401   (the endpoint is fine; no key was sent)
  -> no access-control-allow-origin header
```

An `Authorization` header always forces a preflight, and the preflight on that
path answers 404 with no CORS headers at all. So a browser blocks the request
before it is sent, no matter whose key it is or where the key came from. There
is no version of "let the player paste their own key" that works.

This directory is the way round it: a Cloudflare Worker that holds the key,
adds the headers a browser insists on, and forwards the call. The key lives in
the Worker's environment. It is never in this repository, never in the exported
game, and never in a response.

## Deploy it

You need a Cloudflare account. The free tier covers this many times over.

```bash
cd proxy
npx wrangler deploy
```

Wrangler opens a browser for you to log in, then prints the deployed URL —
something like `https://delegate-ai.<your-subdomain>.workers.dev`.

Then give it the key. **This step has to be yours** — the key goes straight
from your machine to Cloudflare and never through anything else.

Pipe it from the `.env` file rather than pasting it at the prompt:

```bash
grep '^OPENCODE_API_KEY=' ../.env | cut -d= -f2- | npx wrangler secret put OPENCODE_API_KEY
```

Pasting at the interactive prompt is what the docs suggest and it is worth
avoiding: a paste that only half-lands stores a truncated key, and there is no
error — the gateway answers a malformed `Authorization` header with a bare 400
and an empty body, which looks exactly like a broken proxy. That happened here
once, with a stored key one character long. Piping from the file cannot do
that, and the Worker trims whitespace off whatever it is given.

Check it took:

```
https://<your-worker>.workers.dev/?check=1
```

`key_works: true` means the whole path is good. If `key_length` is not 67, the
secret did not land — run the pipe again.

Finally, put the deployed URL into `PROXY_URL` in
[`scripts/ai/llm.gd`](../scripts/ai/llm.gd) and push. The URL is not a secret —
it is useless without the key, and the Worker only answers the game's own
origin — so it belongs in the repository where every platform picks it up.

The next Pages deploy will report `AI: OpenCode Zen via the proxy` in the
browser console instead of `offline (no OPENCODE_API_KEY)`.

## Is it working?

Open the Worker's URL in a browser. It answers with its own status — whether a
key is configured, how long it is, a fingerprint of it, which model it will
use, and which origins it will answer. Nothing there is secret: the key is
reduced to four bytes of a SHA-256, and the origins are in this repository
already.

Add `?check=1` and it spends one token proving the key actually works, rather
than only that something is stored. Every other field can look perfect while
the stored secret is a string the gateway will not accept — which is exactly
the failure this hit — so that is the field to trust.

## Before you trust it

```bash
node test.mjs                                  # the handler, no network
OPENCODE_API_KEY=... node test.mjs --live      # plus one real call
```

The live run matters. Everything else passes just as happily against a model
that has been switched off.

## Testing the game against it without deploying

```bash
OPENCODE_API_KEY=... node dev-server.mjs
godot --path .. -- --aitest --proxy=http://127.0.0.1:8787
```

`dev-server.mjs` imports `worker.js` rather than reimplementing it, so what you
test locally is what deploys.

## What it does and does not protect

It stops the key being published, which is the thing that matters: nobody can
read it out of the build, and the Worker never puts it in a response.

The URL itself is guessable in the way any URL is. Against that there is an
origin allowlist in `worker.js` — a browser always sends `Origin`, so an
embedded page on someone else's site is refused. A request with no `Origin` at
all is not a browser and is refused too, unless you deliberately set
`ALLOW_NATIVE=1`, which the local dev server does and a deployment should not.
Body size and `max_tokens` are capped so a request that gets through cannot be
expensive, and the model is chosen by the Worker rather than the caller.

If you add another origin — a custom domain, a different Pages site — put it in
`ALLOWED_ORIGINS` in `worker.js` and redeploy.

Native builds do not need any of this. They read `OPENCODE_API_KEY` from the
environment and call the API directly, which is what the game does whenever no
proxy is configured.
