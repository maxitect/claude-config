"""Posts payload.json as a PENDING review. Never submits, approves or requests changes.

Usage: post.py <run-dir> <owner/repo> <pr>

Creates the review with its body over REST (no `event`, so it stays PENDING), then adds every comment as a
review thread over GraphQL. A thread GitHub rejects is demoted into the review body as `path:line` prose.
Writes <run-dir>/posted.json and <run-dir>/pr-<n>-review.md.
"""

import json
import os
import subprocess
import sys

run, slug, pr = sys.argv[1], sys.argv[2], sys.argv[3]
payload = json.load(open(os.path.join(run, "payload.json")))
posted_file = os.path.join(run, "posted.json")


def gh(*args, body=None):
    res = subprocess.run(["gh", "api", *args], input=json.dumps(body) if body is not None else None,
                         capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError((res.stdout + res.stderr).strip()[-400:])
    return json.loads(res.stdout or "null")


def graphql(query, **variables):
    out = gh("graphql", "--input", "-", body={"query": query, "variables": variables})
    if out.get("errors"):
        raise RuntimeError("; ".join(e["message"] for e in out["errors"]))
    return out["data"]


def fail(msg):
    print(f"POST FAIL: #{pr} {msg}")
    sys.exit(1)


me = gh("user")["login"]
pending = [r for page in gh(f"repos/{slug}/pulls/{pr}/reviews", "--paginate", "--slurp") for r in page
           if r["state"] == "PENDING" and r["user"]["login"] == me]
if os.path.isfile(posted_file) and json.load(open(posted_file))["sha"] == payload["commit_id"]:
    print(f"POST PASS #{pr} (already posted at this head)")
    sys.exit(0)
if pending:
    fail(f"you already hold pending review {pending[0]['id']} on this PR; submit or delete it first")

head = gh(f"repos/{slug}/pulls/{pr}")["head"]["sha"]
if head != payload["commit_id"]:
    fail(f"head moved to {head[:7]} since the review of {payload['commit_id'][:7]}: re-run the sweep for it")

review = gh(f"repos/{slug}/pulls/{pr}/reviews", "--method", "POST", "--input", "-",
            body={"commit_id": payload["commit_id"], "body": payload["body"]})
if review["state"] != "PENDING":
    fail(f"review {review['id']} came back {review['state']}, expected PENDING")

ADD = """mutation($input: AddPullRequestReviewThreadInput!) {
  addPullRequestReviewThread(input: $input) { thread { id } } }"""
added, demoted = [], []
for t in payload["threads"]:
    thread = {"pullRequestReviewId": review["node_id"], "path": t["path"], "body": t["body"], "subjectType": t["subject"]}
    if t["subject"] == "LINE":
        thread |= {"line": t["line"], "side": t["side"]}
        if t["start_line"]:
            thread |= {"startLine": t["start_line"], "startSide": t["side"]}
    try:
        graphql(ADD, input=thread)
        added.append(t)
    except RuntimeError as e:
        loc = f"{t['path']}:{t['line']}" if t["line"] else t["path"]
        demoted.append((t, f"`{loc}` {t['body'].split('```')[-1].strip()}", str(e)))

body = payload["body"]
if demoted:
    body += "\n\n" + "\n\n".join(prose for _, prose, _ in demoted)
    graphql("""mutation($id: ID!, $body: String!) {
      updatePullRequestReview(input: {pullRequestReviewId: $id, body: $body}) { pullRequestReview { id } } }""",
            id=review["node_id"], body=body)

url = f"https://github.com/{slug}/pull/{pr}/files"
json.dump({"sha": payload["commit_id"], "review_id": review["id"], "node_id": review["node_id"], "url": url,
           "threads": len(added), "demoted": [{"path": t["path"], "line": t["line"], "error": err} for t, _, err in demoted]},
          open(posted_file, "w"), indent=2)

lines = [f"Pending review posted - submit at {url}", "", body, ""]
for t in added:
    loc = f"{t['path']}:{t['start_line']}-{t['line']}" if t["start_line"] else f"{t['path']}:{t['line']}" if t["line"] else f"{t['path']} (file-level)"
    lines += [f"### {loc}", "", t["body"], ""]
open(os.path.join(run, f"pr-{pr}-review.md"), "w").write("\n".join(lines))

print(f"POST PASS #{pr} ({len(added)} comments, {len(demoted)} demoted to body) {url}")
