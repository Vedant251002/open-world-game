"""Insert _begin_call("<kind>") after each remaining `calls_made += 1`.

Done by line number rather than by string match because the file has mixed
line endings (CRLF from git checkout, LF from the patch tool), so an exact
string match either fails or silently rewrites the whole file's endings.

Idempotent: a site that already has a _begin_call on the next line is skipped.
"""
import io
import sys

F = r"C:\Users\vedan\Desktop\Projects\kingdom-city\scripts\ai\llm.gd"
# line number (1-based) -> kind. Taken from the context printed around each
# `calls_made += 1`; line 722 already has the plan timer and is skipped.
SITES = {450: "answer", 503: "talk", 628: "round"}

with open(F, "rb") as f:
    data = f.read()
nl = b"\r\n" if b"\r\n" in data else b"\n"
text = data.decode("utf-8")
lines = text.split(nl.decode())

added = []
for ln, kind in sorted(SITES.items()):
    i = ln - 1
    if i >= len(lines):
        print(f"SKIP {ln}: past end of file")
        continue
    if "calls_made += 1" not in lines[i]:
        print(f"SKIP {ln}: not a calls_made line -> {lines[i].strip()[:50]}")
        continue
    nxt = lines[i + 1] if i + 1 < len(lines) else ""
    if "_begin_call" in nxt:
        print(f"SKIP {ln}: already wired ({nxt.strip()})")
        continue
    lines.insert(i + 1, f'\t_begin_call("{kind}")')
    added.append((ln, kind))

if not added:
    print("nothing to do")
    sys.exit(0)

out = nl.decode().join(lines)
with open(F, "wb") as f:
    f.write(out.encode("utf-8"))
for ln, kind in added:
    print(f"OK   line {ln}: _begin_call(\"{kind}\")")
print(f"{len(added)} site(s) wired")
