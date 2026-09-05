// The same Worker, on localhost, so the game can be pointed at it before
// anything is deployed anywhere.
//
//   OPENCODE_API_KEY=... node proxy/dev-server.mjs
//   godot --path . -- --aitest --proxy=http://127.0.0.1:8787
//
// It imports worker.js rather than reimplementing it, so what is tested here
// is what gets deployed. ALLOW_NATIVE is on, because a desktop build sends no
// Origin header and this is exactly the case that setting is for.

import { createServer } from "node:http";
import worker from "./worker.js";

const PORT = Number(process.env.PORT || 8787);
const env = {
  OPENCODE_API_KEY: process.env.OPENCODE_API_KEY || "",
  OPENCODE_MODEL: process.env.OPENCODE_MODEL || "nemotron-3-ultra-free",
  ALLOW_NATIVE: "1",
};

if (!env.OPENCODE_API_KEY) {
  console.error("[dev-proxy] no OPENCODE_API_KEY in the environment — every call will 500");
}

createServer(async (req, res) => {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;

  const request = new Request(`http://127.0.0.1:${PORT}${req.url}`, {
    method: req.method,
    headers: req.headers,
    body: req.method === "GET" || req.method === "HEAD" ? undefined : body,
  });

  const out = await worker.fetch(request, env);
  const text = await out.text();
  res.writeHead(out.status, Object.fromEntries(out.headers));
  res.end(text);
  console.log(`[dev-proxy] ${req.method} -> ${out.status}`);
}).listen(PORT, "127.0.0.1", () => {
  console.log(`[dev-proxy] listening on http://127.0.0.1:${PORT} (model ${env.OPENCODE_MODEL})`);
});
