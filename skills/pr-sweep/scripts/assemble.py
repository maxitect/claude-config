"""Merges the commenter's text with the resolved anchors into the review payload post.py sends.

Usage: assemble.py <run-dir> <pr-body-file> [--strict]

--strict: print problems with comments.json (uncovered critical/warning findings, unknown ids, em dashes)
and exit 1, so comment.sh can hand them back once. Without it, problems are repaired: an uncovered
finding gets a plain comment built from the reviewer's own text and em dashes become spaced hyphens.
Writes <run-dir>/payload.json: {commit_id, body, threads: [{path, body, line, start_line, side, subject}]}.
"""

import json
import os
import re
import sys

run, body_file, strict = sys.argv[1], sys.argv[2], "--strict" in sys.argv
load = lambda name: json.load(open(os.path.join(run, name)))
meta, findings, anchors, text = load("meta.json"), load("findings.json"), load("anchors.json"), load("comments.json")
by_id = {f["id"]: f for f in findings["findings"]}
DOT = {"critical": "🔴", "warning": "🟡", "suggestion": "🟢", "praise": "🟣"}

problems, covered = [], set()
for c in text["comments"]:
    for fid in c["finding_ids"]:
        if fid not in by_id:
            problems.append(f"comment references unknown finding id {fid}")
        elif fid in covered:
            problems.append(f"finding {fid} appears in more than one comment")
        covered.add(fid)
missing = [fid for fid, f in by_id.items() if f["severity"] in ("critical", "warning") and fid not in covered]
problems += [f"{by_id[fid]['severity']} finding {fid} ({by_id[fid]['title']}) is in no comment" for fid in missing]
dashed = [c["body"][:60] for c in text["comments"] if "—" in c["body"]] + (["summary"] if "—" in text["summary"] else [])
problems += [f"em dash in: {d}" for d in dashed]

if strict:
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    sys.exit(0)

undash = lambda s: re.sub(r"\s*—\s*", " - ", s)
comments = [c for c in text["comments"] if all(fid in by_id for fid in c["finding_ids"])]


def fallback(fid):
    f, a = by_id[fid], anchors[fid]
    loc = f" `{a['path']}:{a['line']}`" if a["kind"] == "body" and a["line"] else f" `{a['path']}`" if a["kind"] == "body" else ""
    return {"finding_ids": [fid], "body": f"{DOT[f['severity']]}{loc} {f['title']}: {f['fix']}"}


comments += [fallback(fid) for fid in missing]

threads, body_notes = [], []
for c in comments:
    lead = c["finding_ids"][0]
    a, body = anchors[lead], undash(c["body"])
    if a["kind"] == "body":
        body_notes.append(body)
        continue
    if a["suggestion"] is not None:
        body = f"```suggestion\n{a['suggestion']}\n```\n{body}"
    threads.append({
        "path": a["path"], "body": body, "line": a["line"] if a["kind"] == "inline" else None,
        "start_line": a["start_line"] if a["kind"] == "inline" else None, "side": a["side"],
        "subject": "LINE" if a["kind"] == "inline" else "FILE",
    })

summary = undash(text["summary"]).strip()
if body_notes:
    summary += "\n\n" + "\n\n".join(body_notes)
pr_body = open(body_file).read()
if findings["ui_changed"] and "![" not in pr_body and "<img" not in pr_body:
    summary += "\n\n> [!NOTE]\n> this PR should have screenshots"

json.dump({"commit_id": meta["sha"], "body": summary, "threads": threads},
          open(os.path.join(run, "payload.json"), "w"), indent=2, ensure_ascii=False)
repaired = f", repaired: {'; '.join(problems)}" if problems else ""
print(f"ASSEMBLE PASS ({len(threads)} threads, {len(body_notes)} body notes{repaired})")
