"""Checks a reviewer's findings.json against the PR diff and resolves where each finding can be posted.

Usage: validate.py <run-dir> <base-ref>     (cwd: the PR worktree)

Writes <run-dir>/anchors.json: {id: {kind: inline|file|body, path, line, start_line, side, suggestion}}.
  inline  every line of the span sits in one diff hunk on that side
  file    path is in the diff, finding is about the whole file (line null)
  body    anything else: an unchanged line, or a file the PR doesn't touch
Structural problems are printed one per line and exit 1, so review.sh --fix can hand them back.
"""

import json
import os
import re
import subprocess
import sys

run, base = sys.argv[1], sys.argv[2]
data = json.load(open(os.path.join(run, "findings.json")))
diff = subprocess.run(["git", "diff", "--no-color", "-U3", f"{base}...HEAD"], capture_output=True, text=True).stdout

HUNK = re.compile(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@")
hunks = {}  # path -> list of {"RIGHT": set, "LEFT": set}
path = old_path = None
for raw in diff.splitlines():
    if raw.startswith("diff --git"):
        path = None
    elif raw.startswith("--- "):
        old_path = raw[6:] if raw.startswith("--- a/") else None
    elif raw.startswith("+++ "):
        path = raw[6:] if raw.startswith("+++ b/") else old_path
        hunks.setdefault(path, [])
    elif path and (m := HUNK.match(raw)):
        old, new = int(m.group(1)), int(m.group(2))
        hunks[path].append({"RIGHT": set(), "LEFT": set()})
    elif path and hunks.get(path) and raw[:1] in ("+", "-", " "):
        h = hunks[path][-1]
        if raw[0] == "+":
            h["RIGHT"].add(new); new += 1
        elif raw[0] == "-":
            h["LEFT"].add(old); old += 1
        else:
            h["RIGHT"].add(new); h["LEFT"].add(old); new += 1; old += 1

errors, anchors, seen = [], {}, set()
for f in data["findings"]:
    fid, p, line, end, side = f["id"], f["path"].removeprefix("./"), f["line"], f["end_line"], f["side"]
    where = f"{fid} ({p}:{line})"
    if fid in seen:
        errors.append(f"{where}: duplicate id")
    seen.add(fid)
    if f["severity"] in ("critical", "warning") and not f["evidence"].strip():
        errors.append(f"{where}: {f['severity']} finding has no evidence line")
    if f["status"] == "UNVERIFIED" and "UNVERIFIED" not in f["evidence"]:
        errors.append(f"{where}: status UNVERIFIED but evidence doesn't say 'UNVERIFIED - <reason>'")
    exists = os.path.isfile(p)
    if not exists and p not in hunks:
        errors.append(f"{where}: path exists neither in the worktree nor in the diff")
        continue
    if line is not None and side == "RIGHT" and exists:
        length = sum(1 for _ in open(p, errors="replace"))
        if line < 1 or (end or line) > length:
            errors.append(f"{where}: line out of range, file has {length} lines")
            continue
    if end is not None and line is not None and end < line:
        errors.append(f"{where}: end_line before line")
        continue

    span = set(range(line, (end or line) + 1)) if line is not None else set()
    if line is None:
        kind = "file" if p in hunks else "body"
    elif any(span <= h[side] for h in hunks.get(p, [])):
        kind = "inline"
    else:
        kind = "body"
    anchors[fid] = {
        "kind": kind, "path": p, "line": end or line, "start_line": line if end and end != line else None,
        "side": side, "suggestion": f["suggestion"] if kind == "inline" and side == "RIGHT" else None,
    }

if errors:
    print("\n".join(errors))
    sys.exit(1)
json.dump(anchors, open(os.path.join(run, "anchors.json"), "w"), indent=2)
kinds = [a["kind"] for a in anchors.values()]
print(f"VALIDATE PASS ({kinds.count('inline')} inline, {kinds.count('file')} file-level, {kinds.count('body')} in body)")
