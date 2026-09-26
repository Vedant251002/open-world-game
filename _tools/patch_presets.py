"""Set exclude_filter on the two web export presets.

Godot's export filter is a comma-separated glob list applied to resource paths.
`assets/tex/*` is the 1024px desktop set. Excluding it from the web presets
keeps the 36MB 512px set (assets/tex_web) as the only texture payload that
ships to a browser, which is the whole point: the deployed pack went from
20.6 MB to 88.6 MB when both were included, and the tab wedged on the parse.

Desktop, Linux, macOS and Android are left alone — they load from disk, where
100 MB costs nothing and the extra resolution is worth having.
"""
import re
import shutil

P = "export_presets.cfg"
shutil.copyfile(P, P + ".bak")

src = open(P, encoding="utf8").read()

# preset index -> display name, confirmed by reading the file above
WEB = {"2": "Web", "4": "Web Lite"}
EXCLUDE = "assets/tex/*"


def patch_block(m):
    head, idx, body = m.group(0), m.group(1), m.group(2)
    if idx not in WEB:
        return head
    if 'exclude_filter=""' in body:
        body = body.replace('exclude_filter=""', f'exclude_filter="{EXCLUDE}"', 1)
    else:
        body = re.sub(r'exclude_filter="[^"]*"',
                      f'exclude_filter="{EXCLUDE}"', body, count=1)
    return head.replace(m.group(2), body)


out = re.sub(r"\[preset\.(\d+)\]\n(.*?)(?=\n\[preset\.|\n\[|\Z)",
             patch_block, src, flags=re.S)
open(P, "w", encoding="utf8").write(out)

# verify
chk = open(P, encoding="utf8").read()
for m in re.finditer(r"\[preset\.(\d+)\]\n(.*?)(?=\n\[preset\.|\n\[|\Z)", chk, re.S):
    b = m.group(2)
    nm = re.search(r'name="([^"]+)"', b).group(1)
    ex = re.search(r'exclude_filter="([^"]*)"', b).group(1)
    tag = "WEB " if m.group(1) in WEB else "     "
    print(f"  {tag}preset {m.group(1)} {nm:18s} exclude_filter={ex!r}")
