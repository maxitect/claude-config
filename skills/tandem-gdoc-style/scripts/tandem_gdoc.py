#!/usr/bin/env python3
"""Build Tandem house-style Google Docs through the Docs connector.

Each phase reads a fresh read_doc result and a content spec, and prints the
update_doc arguments ({"writeControl": ..., "requests": [...]}) for one call.
Run the phases in order, re-reading the doc between each:

  cover    rewrite the cover fields, rename the first section, clear the body
  content  insert every block with Tandem paragraph styles and numbering
  tables   replace each table marker with a filled table
  style    apply Tandem table styling (widths, borders, weights, pinned header)

Usage: tandem_gdoc.py PHASE DOC.json SPEC.json [--tab t.0] [--only TABLE ...]
"""

import argparse
import json
import sys

COMPANY = "Tandem Creative Dev Limited"
MARKER = "TABLE::"
COVER_KEYS = ("Client", "Date", "Status", "Author", "Project number", "Document number", "Contract reference")
H1_INDENT_START = 30
BODY_SPACE_BELOW = 8
LIST_SPACE_BELOW = 4
CONTENT_WIDTH = 451.3
CLEARED_TEXT = "bold,italic,underline,fontSize,weightedFontFamily,foregroundColor"


def pt(v):
    return {"magnitude": v, "unit": "PT"}


def u16(s):
    return len(s.encode("utf-16-le")) // 2


def load_doc(path):
    raw = json.load(open(path))
    if isinstance(raw, list):
        raw = json.loads(raw[0]["text"])
    if isinstance(raw, dict) and "content" in raw and "tabs" not in raw:
        raw = raw["content"]
        if isinstance(raw, str):
            raw = json.loads(raw)
    return raw


def body_of(doc, tab):
    for t in doc["tabs"]:
        if t["tabProperties"]["tabId"] == tab:
            return t["documentTab"]["body"]["content"]
    sys.exit(f"tab {tab} not found")


def text(el):
    if "paragraph" not in el:
        return None
    return "".join(e.get("textRun", {}).get("content", "") for e in el["paragraph"]["elements"])


def style(el):
    return el["paragraph"]["paragraphStyle"].get("namedStyleType") if "paragraph" in el else None


def first_h1(body):
    for i, el in enumerate(body):
        if style(el) == "HEADING_1":
            return i, el
    sys.exit("no HEADING_1 found: copy the Tandem master template first")


class Batch:
    def __init__(self, tab):
        self.tab, self.reqs = tab, []

    def rng(self, a, b):
        return {"startIndex": a, "endIndex": b, "tabId": self.tab}

    def loc(self, i):
        return {"index": i, "tabId": self.tab}

    def add(self, kind, body):
        self.reqs.append({kind: body})

    def replace_text(self, el, new):
        s, e = el["startIndex"], el["endIndex"]
        if e - 1 > s:
            self.add("deleteContentRange", {"range": self.rng(s, e - 1)})
        if new:
            self.add("insertText", {"location": self.loc(s), "text": new})

    def para_style(self, a, b, **ps):
        fields = ",".join(ps)
        values = {k: (pt(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else v) for k, v in ps.items()}
        self.add("updateParagraphStyle", {"range": self.rng(a, b), "paragraphStyle": values, "fields": fields})


def emit(doc, batch):
    json.dump({"writeControl": {"requiredRevisionId": doc["revisionId"]}, "requests": batch.reqs},
              sys.stdout, ensure_ascii=False, separators=(",", ":"))
    print()


def phase_cover(doc, spec, tab):
    body = body_of(doc, tab)
    h1_i, h1 = first_h1(body)
    blocks = spec["blocks"]
    if blocks[0][0] != "h1":
        sys.exit("the first block must be an h1")
    cover = spec.get("cover", {})
    lines = dict(cover.get("lines", {}))
    b = Batch(tab)
    b.add("deleteContentRange", {"range": b.rng(h1["endIndex"], body[-1]["endIndex"] - 1)})
    b.replace_text(h1, blocks[0][1])

    edits, seen_company, last_line = [], False, None
    for el in body[:h1_i]:
        t = (text(el) or "").rstrip("\n")
        st = style(el)
        if st == "TITLE" and t == COMPANY:
            seen_company = True
        elif st == "TITLE" and t and seen_company and "title" in cover:
            edits.append((el, cover["title"]))
        elif st == "SUBTITLE" and t and "subtitle" in cover:
            edits.append((el, cover["subtitle"]))
        else:
            key = next((k for k in COVER_KEYS if t.startswith(k + ":")), None)
            if key:
                last_line = el
                if key in lines:
                    edits.append((el, f"{key}: {lines.pop(key)}"))
    extra = "".join(f"\n{k}: {v}" for k, v in lines.items())
    if extra:
        if last_line is None:
            sys.exit(f"cover has no metadata lines to add {list(lines)} after")
        edits.append((last_line, None))
        # each added line costs one blank spacer above the metadata, or the cover spills onto page 2
        first_line = next(el for el in body[:h1_i] if any((text(el) or "").startswith(k + ":") for k in COVER_KEYS))
        idx = body.index(first_line)
        spacers = []
        while idx > 0 and len(spacers) < len(lines) and style(body[idx - 1]) == "NORMAL_TEXT" and text(body[idx - 1]) == "\n":
            idx -= 1
            spacers.append(body[idx])
        if spacers:
            edits.append((spacers[-1], ("drop", spacers[0]["endIndex"])))
    for el, new in sorted(edits, key=lambda x: -(x[0]["startIndex"] + (0.5 if x[1] is None else 0))):
        if new is None:
            b.add("insertText", {"location": b.loc(el["endIndex"] - 1), "text": extra})
        elif isinstance(new, tuple):
            b.add("deleteContentRange", {"range": b.rng(el["startIndex"], new[1])})
        else:
            b.replace_text(el, new)
    return b


def paragraphs_from(blocks):
    out = []
    for kind, value in blocks[1:]:
        if kind == "h1" and out and out[-1][0] != "table":
            out.append(("blank", ""))
        if kind == "table":
            out.append(("table", MARKER + value))
        else:
            out.append((kind, value))
    return out


def phase_content(doc, spec, tab):
    body = body_of(doc, tab)
    h1_i, h1 = first_h1(body)
    trailing = body[h1_i + 1] if h1_i + 1 < len(body) else None
    if trailing is None or (text(trailing) or "").strip():
        sys.exit("expected an empty paragraph after the first H1: run the cover phase first")
    paras = paragraphs_from(spec["blocks"])
    texts = [t for _, t in paras]
    start = h1["endIndex"]
    b = Batch(tab)
    b.add("insertText", {"location": b.loc(start), "text": "\n".join(texts)})

    spans, pos = [], start
    for (kind, t) in paras:
        spans.append((kind, pos, pos + u16(t) + 1))
        pos += u16(t) + 1
    end = pos

    def runs(pred):
        out = []
        for kind, a, z in spans:
            if pred(kind):
                if out and out[-1][1] == a:
                    out[-1][1] = z
                else:
                    out.append([a, z])
        return out

    b.add("createParagraphBullets", {"range": b.rng(h1["startIndex"], end), "bulletPreset": "NUMBERED_DECIMAL_ALPHA_ROMAN"})
    for a, z in runs(lambda k: k != "h1"):
        b.add("deleteParagraphBullets", {"range": b.rng(a, z)})
    b.add("updateTextStyle", {"range": b.rng(start, end - 1), "textStyle": {}, "fields": CLEARED_TEXT})
    b.para_style(h1["startIndex"], h1["endIndex"], namedStyleType="HEADING_1", indentFirstLine=0, indentStart=H1_INDENT_START)
    for a, z in runs(lambda k: k == "h1"):
        b.para_style(a, z, namedStyleType="HEADING_1", indentFirstLine=0, indentStart=H1_INDENT_START)
    for a, z in runs(lambda k: k == "h2"):
        b.para_style(a, z, namedStyleType="HEADING_2", indentFirstLine=0, indentStart=0)
    for a, z in runs(lambda k: k in ("p", "blank")):
        b.para_style(a, z, namedStyleType="NORMAL_TEXT", spaceBelow=BODY_SPACE_BELOW, indentFirstLine=0, indentStart=0)
    for a, z in runs(lambda k: k == "table"):
        b.para_style(a, z, namedStyleType="NORMAL_TEXT", spaceBelow=0, indentFirstLine=0, indentStart=0)
    for a, z in runs(lambda k: k == "li"):
        b.para_style(a, z, namedStyleType="NORMAL_TEXT", spaceBelow=LIST_SPACE_BELOW)
        b.add("createParagraphBullets", {"range": b.rng(a, z), "bulletPreset": "BULLET_DISC_CIRCLE_SQUARE"})
    return b


def phase_tables(doc, spec, tab):
    body = body_of(doc, tab)
    markers = [(el, text(el).strip()[len(MARKER):]) for el in body if (text(el) or "").startswith(MARKER)]
    if not markers:
        sys.exit("no table markers found: run the content phase first")
    b = Batch(tab)
    for el, name in sorted(markers, key=lambda m: -m[0]["startIndex"]):
        t = spec["tables"][name]
        rows = t["rows"]
        R, C = len(rows), len(rows[0])
        if any(len(r) != C for r in rows):
            sys.exit(f"table {name}: rows have different lengths")
        s, e = el["startIndex"], el["endIndex"]
        b.add("deleteContentRange", {"range": b.rng(s, e - 1)})
        i = s
        b.add("insertTable", {"rows": R, "columns": C, "location": b.loc(i)})
        after = i + 3 + R * (2 * C + 1)
        b.para_style(after, after + 1, namedStyleType="NORMAL_TEXT", spaceBelow=BODY_SPACE_BELOW, indentFirstLine=0, indentStart=0)
        for r in range(R - 1, -1, -1):
            for c in range(C - 1, -1, -1):
                value = str(rows[r][c])
                if value:
                    b.add("insertText", {"location": b.loc(i + 4 + r * (2 * C + 1) + 2 * c), "text": value})
    return b


def phase_style(doc, spec, tab, only=None):
    body = body_of(doc, tab)
    order = [v for k, v in spec["blocks"] if k == "table"]
    tables = [(i, el) for i, el in enumerate(body) if "table" in el]
    if len(tables) != len(order):
        sys.exit(f"doc has {len(tables)} tables, spec has {len(order)}")
    black, grey = {}, {"red": 0.8, "green": 0.8, "blue": 0.8}

    def border(width, colour):
        return {"color": {"color": {"rgbColor": colour}}, "dashStyle": "SOLID", "width": pt(width)}

    sides = {"borderLeft": border(0, black), "borderRight": border(0, black)}
    header = {"borderTop": border(0, black), "borderBottom": border(0.75, black), **sides}
    rows_style = {"borderTop": border(0.5, grey), "borderBottom": border(0.5, grey), **sides}
    last = {"borderBottom": border(0, black)}
    light = {"weightedFontFamily": {"fontFamily": "Helvetica Neue", "weight": 300}, "bold": False}
    normal = {"weightedFontFamily": {"fontFamily": "Helvetica Neue", "weight": 400}, "bold": False}

    b = Batch(tab)
    for (i, el), name in zip(tables, order):
        if only and name not in only:
            continue
        t = spec["tables"][name]
        tb = el["table"]
        R, C = tb["rows"], tb["columns"]
        s, e = el["startIndex"], el["endIndex"]
        loc = b.loc(s)
        widths = t.get("widths") or [round(CONTENT_WIDTH / C, 2)] * C
        if abs(sum(widths) - CONTENT_WIDTH) > 0.5:
            sys.exit(f"table {name}: widths sum to {sum(widths)}, need {CONTENT_WIDTH}")

        def cells(r, n):
            return {"tableCellLocation": {"tableStartLocation": loc, "rowIndex": r, "columnIndex": 0}, "rowSpan": n, "columnSpan": C}

        b.add("deleteParagraphBullets", {"range": b.rng(s, body[i + 1]["endIndex"])})
        b.para_style(s + 1, e - 1, namedStyleType="NORMAL_TEXT", spaceBelow=0, indentFirstLine=0, indentStart=0)
        by_width = {}
        for c, w in enumerate(widths):
            by_width.setdefault(w, []).append(c)
        for w, cols in by_width.items():
            b.add("updateTableColumnProperties", {"tableStartLocation": loc, "columnIndices": cols,
                                                  "tableColumnProperties": {"widthType": "FIXED_WIDTH", "width": pt(w)},
                                                  "fields": "widthType,width"})
        b.add("updateTableCellStyle", {"tableRange": cells(0, 1), "tableCellStyle": header, "fields": ",".join(header)})
        if R > 1:
            b.add("updateTableCellStyle", {"tableRange": cells(1, R - 1), "tableCellStyle": rows_style, "fields": ",".join(rows_style)})
        b.add("updateTableCellStyle", {"tableRange": cells(R - 1, 1), "tableCellStyle": last, "fields": "borderBottom"})
        b.add("updateTextStyle", {"range": b.rng(s, e), "textStyle": light, "fields": "weightedFontFamily,bold"})
        hdr = tb["tableRows"][0]
        b.add("updateTextStyle", {"range": b.rng(hdr["startIndex"], hdr["endIndex"]), "textStyle": normal, "fields": "weightedFontFamily,bold"})
        if t.get("total"):
            tot = tb["tableRows"][-1]
            b.add("updateTextStyle", {"range": b.rng(tot["startIndex"], tot["endIndex"]), "textStyle": normal, "fields": "weightedFontFamily,bold"})
        b.add("pinTableHeaderRows", {"tableStartLocation": loc, "pinnedHeaderRowsCount": 1})
    return b


PHASES = {"cover": phase_cover, "content": phase_content, "tables": phase_tables, "style": phase_style}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("phase", choices=PHASES)
    ap.add_argument("doc")
    ap.add_argument("spec")
    ap.add_argument("--tab", default="t.0")
    ap.add_argument("--only", nargs="+", help="style phase: restyle only these named tables")
    a = ap.parse_args()
    doc, spec = load_doc(a.doc), json.load(open(a.spec))
    kwargs = {"only": a.only} if a.phase == "style" and a.only else {}
    emit(doc, PHASES[a.phase](doc, spec, a.tab, **kwargs))


if __name__ == "__main__":
    main()
