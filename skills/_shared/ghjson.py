"""Fallback for the small jq filter set render.sh uses, for machines without jq.

Reads gh JSON on stdin, takes the filter as argv[1], prints the same raw text jq -r would.
"""

import json
import sys

f = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)

if f == 'if .isDraft then " (draft)" else "" end':
    out = " (draft)" if d.get("isDraft") else ""
elif f == '[.labels[].name] | join(", ")':
    out = ", ".join(l["name"] for l in d.get("labels") or [])
elif f.startswith(".closingIssuesReferences[]"):
    refs = d.get("closingIssuesReferences") or []
    if "repository" in f:
        out = "\n".join(
            "%s/%s#%s" % (r["repository"]["owner"]["login"], r["repository"]["name"], r["number"])
            for r in refs
        )
    else:
        out = "\n".join("#%s %s" % (r["number"], r.get("url", "")) for r in refs)
else:
    out = d.get(f.lstrip("."), "") or ""

sys.stdout.write(str(out))
