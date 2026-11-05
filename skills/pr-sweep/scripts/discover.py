"""Filters gh PR JSON (stdin) into the sweep queue. Called by discover.sh."""

import json
import os
import sys

prs = json.load(sys.stdin)
sweep, me, explicit = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
my_reviews = json.load(open(sys.argv[4]))
supabase = os.path.isfile("supabase/config.toml")


def posted_sha(n):
    path = os.path.join(sweep, str(n), "posted.json")
    return json.load(open(path)).get("sha") if os.path.isfile(path) else None


def read(n, name):
    path = os.path.join(sweep, str(n), name)
    return open(path).read().strip() if os.path.isfile(path) else None


def has_session(n):
    return read(n, "reviewer.sid") is not None and os.path.isdir(os.path.join(sweep, str(n), "wt"))


def skip_reason(pr, posted, mine):
    if mine.get("pending"):
        return "pending review from this sweep, not yet submitted" if posted else "you already hold a pending review"
    if posted == pr["headRefOid"]:
        return "already reviewed at this head by a sweep"
    if mine.get("reviewed_sha") == pr["headRefOid"]:
        return "you already reviewed this head"
    if explicit:
        return None
    if pr["isDraft"]:
        return "draft"
    if pr["author"]["login"] == me:
        return "your own PR"
    if pr["isCrossRepository"]:
        return "from a fork"
    if "no-ai-review" in {label["name"] for label in pr["labels"]}:
        return "labelled no-ai-review"
    return None


def touches_schema(pr):
    return supabase and any(
        f["path"].startswith(("supabase/migrations/", "supabase/seed")) or f["path"] == "supabase/config.toml"
        for f in pr["files"]
    )


queue = []
for pr in sorted(prs, key=lambda p: p["number"]):
    n, title = pr["number"], pr["title"]
    posted, mine = posted_sha(n), my_reviews.get(str(n), {})
    reason = skip_reason(pr, posted, mine)
    if reason:
        print(f"skip #{n} {title} ({reason})")
        continue
    mig = touches_schema(pr)
    rereview = posted is not None or mine.get("reviewed_sha") is not None
    followup = mine.get("reviewed_sha") is not None and has_session(n) and read(n, "followup.sha") != pr["headRefOid"]
    queue.append({
        "number": n, "title": title, "url": pr["url"], "sha": pr["headRefOid"],
        "head": pr["headRefName"], "base": pr["baseRefName"], "mig": mig, "rereview": rereview,
        "mode": "followup" if followup else "review",
    })
    tags = (" MIG" if mig else "") + (
        " (followup: resumes its reviewer session, head moved since your review)" if followup
        else " (re-review, head moved since your last review)" if rereview else "")
    print(f"queue #{n}{tags} {title}")

with open(os.path.join(sweep, "queue.json"), "w") as f:
    json.dump(queue, f, indent=2)
print(f"DISCOVER PASS ({len(queue)} queued, {sum(q['mig'] for q in queue)} with migrations)")
