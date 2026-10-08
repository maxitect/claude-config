"""Gives a worktree's supabase/config.toml its own project_id and port block so its stack runs beside the base one.

Usage: patch_supabase.py <config.toml> <slot> <pr> <dev-port>

Slot k gets ports 55000 + 100k + (old port % 100), so 54321 becomes 55121 in slot 1. Every ':<old port>'
elsewhere in the file (redirect URIs) and ':3000' (site_url) follow. Prints 'old new' per remapped port so the
caller can rewrite env files the same way. Idempotent: run on the committed file, never on a patched one.
"""

import re
import sys

path, slot, pr, dev_port = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
text = open(path).read()
base = 55000 + 100 * slot

PORT_LINE = re.compile(r"^(\s*(?:port|shadow_port|inspector_port|smtp_port|pop3_port|vector_port)\s*=\s*)(\d+)", re.M)

mapping, used = {}, set()
for old in dict.fromkeys(int(m.group(2)) for m in PORT_LINE.finditer(text)):
    offset = old % 100
    while base + offset in used:
        offset = (offset + 1) % 100
    mapping[old] = base + offset
    used.add(base + offset)

text = PORT_LINE.sub(lambda m: m.group(1) + str(mapping[int(m.group(2))]), text)
for old, new in mapping.items():
    text = re.sub(rf":{old}\b", f":{new}", text)
text = re.sub(r"(localhost|127\.0\.0\.1):3000\b", rf"\g<1>:{dev_port}", text)

text, n = re.subn(r'^(\s*project_id\s*=\s*")([^"]*)"', rf'\g<1>\g<2>-pr{pr}"', text, count=1, flags=re.M)
if n == 0:
    text = f'project_id = "pr{pr}"\n' + text

open(path, "w").write(text)
for old, new in mapping.items():
    print(old, new)
print(3000, dev_port)
