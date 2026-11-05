---
name: tandem-gdoc-style
description: Create or restyle a Google Doc in the Tandem Creative Dev house style (proposals, fee proposals, scopes of work, reports) using the Google Docs and Drive connectors. Copies the Tandem master template, then builds the document from a JSON content spec with a script that handles numbering, styles and tables. Use whenever the user wants a Tandem-branded Google Doc. For a downloadable .docx, use tandem-docx-style instead.
---

# Tandem house style for Google Docs

This skill builds on Anthropic's `google-workspace` skill. **Read its `SKILL.md` and `references/docs.md` first.** Those cover the connector rules this skill relies on: revision guards, index arithmetic, batching, reading saved results and verifying with a PDF render. This file adds only what is specific to Tandem documents.

The house style was set by the Amagi Phase 1c scope and refined on the DWP UK Skills Explorer fee proposal (October 2026). The master template captures it.

## Files

- **Master template:** Google Doc `1qSx8tTAgHXgkV2xYkobN5DODxRVoaYwqlpyJz31t5z8` ("Tandem Google Doc Master Template", in the Tandem `Templates` folder `10PdmBu88JHfAf2K7LvswGZZvb4Lzu7Ry`, shared with Max and Jack only). It has the cover with the Tandem logo, the footer with the logo mark and page number, the named styles, and a placeholder body.
- `scripts/tandem_gdoc.py`: turns a content spec plus a fresh `read_doc` result into `update_doc` arguments, one phase at a time.
- `references/master-spec.json`: the spec that produced the master's placeholder body. Copy it as the starting point for a new spec.

## Workflow

1. **Choose the destination folder and check who can see it.** Run Drive `get_file_permissions` on the folder. Never write a client's document into a folder another client can open. A template's own folder says nothing about where its copies belong.
2. **Copy the master with an explicit destination:** Drive `copy_file` with `fileId` set to the master, `parentId` set to the folder from step 1, and a `title`. Without `parentId` the copy lands in the Templates folder.
3. **Write the spec** (format below) to a JSON file in the scratchpad.
4. **Run the four phases in order.** For each phase:
   - `read_doc` the new doc. Large results are saved to a file; the script reads that file as saved.
   - Run `python3 <skill>/scripts/tandem_gdoc.py PHASE <saved read_doc file> <spec.json>`.
   - Pass the printed `writeControl` and `requests` to `update_doc` unchanged.
   - Read again before the next phase. Never reuse indexes or revisions across phases.

   | Phase | What it does |
   |---|---|
   | `cover` | Fills the title, subtitle and metadata lines, renames the first section heading, and clears the body after it. Each metadata line it adds replaces one blank spacer, so the cover stays on one page |
   | `content` | Inserts every block. H1s get the numbered list (number at the margin, title at 30pt), H2s and body text get their named styles, list items get bullets, and a blank line goes before each H1 |
   | `tables` | Replaces each `TABLE::name` marker with a filled table, leaving one blank line above it |
   | `style` | Applies table widths, borders and font weights, removes the bottom line from the last row, and pins the header row. `--only NAME ...` restyles selected tables |

5. **Verify the result.** Export a PDF with Drive `download_file_content`, render it with the google-workspace `render_export.py`, and look at every page against the checklist below.

If a read comes back inline instead of as a saved file, the script still needs a file. Either read again (a doc with content usually saves), or write a minimal JSON holding only the elements the phase uses: the first H1 and the paragraph after it for `content`, the marker paragraphs for `tables`.

## Spec format

```json
{
  "cover": {
    "title": "UK Skills Explorer",
    "subtitle": "Digital Service Contract Proposal",
    "lines": {"Client": "...", "Date": "October 2026", "Status": "DRAFT", "Author": "Tandem Creative Dev"}
  },
  "blocks": [
    ["h1", "Purpose"],
    ["p", "Body paragraph."],
    ["h2", "Sub-heading"],
    ["li", "Bullet item"],
    ["table", "scope"]
  ],
  "tables": {
    "scope": {"widths": [225.65, 225.65], "rows": [["In scope", "Out of scope"], ["✓ ...", "✗ ..."]]},
    "costs": {"widths": [271.3, 90, 90], "total": true, "rows": [["Item", "Days", "Cost"], ["...", "1", "£500"], ["Total", "1", "£500"]]}
  }
}
```

- The first block must be an `h1`. It replaces the master's first heading.
- Cover `lines` keys: `Client`, `Date`, `Status`, `Author`, `Project number`, `Document number`, `Contract reference`. Keys already on the cover are rewritten. Missing keys are added after the last line.
- Table `widths` are in points and must sum to 451.3, the content width. Omit them for equal columns.
- `"total": true` sets the last row in the header weight.
- Never type numbers into H1 text. H2 text may carry a reference number from a source document, such as a specification's deliverable numbers.

## House style the script applies

| Element | Style |
|---|---|
| Body | Normal text: Helvetica Neue Light (weight 300), 11pt, 8pt after |
| H1 | Heading 1, numbered `1.` to `n.` in one list, number at the margin, title at 30pt, one blank line above (except the first) |
| H2 | Heading 2: Helvetica Neue 400, 12pt, no number |
| Bullets | Disc bullets, 4pt after |
| Table header row | Helvetica Neue Normal (400), not bold, black 0.75pt bottom line, pinned |
| Table body rows | Helvetica Neue Light, grey (#CCCCCC) 0.5pt lines above and below, no side lines |
| Table last row | No bottom line. A total row uses the header weight |
| Table placement | One blank line above, full content width, fixed column widths |

Cover, footer, page size (A4, 72pt margins) and the named styles come from the master. Do not change them.

## Writing and structure

- **Proposal sections**, in order, as needed: Purpose, Scope, Timeline, Deliverables (one H2 per deliverable), Live service or delivery approach, Proposed improvements, Capacity and capability, Decisions made, Decisions needed, Commercial terms.
- **Purpose** opens with what the reader should conclude, including the price.
- **Each deliverable** says what we do, the assumptions, the estimate in days, and any contingency with the risk behind it.
- **Scope table:** pair each in-scope item with the out-of-scope item it reads against (design principles next to the excluded design system, hosting from a date next to hosting before it). Balance the columns where it is natural, by merging closely related items. Do not invent items to fill a cell; leave it empty.
- **Decisions made** go in a two-column table (`#`, `Decision`), each saying where it was agreed. **Decisions needed** go under H2 topics.
- **Commercial terms:** an estimate table by deliverable, a table per purchase order, a total table with VAT, then contingency and payment terms. Totals must reconcile with the Purpose figures.
- Put a short sentence before a table that directly follows a heading.
- British English. Plain, specific sentences. No em dashes in headings, no filler intensifiers, no typed list markers. Follow the writing rules in google-workspace `references/docs.md`.

## Editing an existing Tandem doc

Use the google-workspace recipes for text edits. For tables, `style --only NAME` reapplies the house table style after changing a table's rows. To replace a table, delete the table range, delete the blank paragraph above it, and insert the new table into the remaining empty paragraph: the insert recreates the blank line above.

## Checklist

- [ ] Copy is in a folder whose sharing you checked
- [ ] Cover fits on page 1 and every placeholder is filled
- [ ] H1s numbered 1 to n with no gaps, titles aligned
- [ ] No body paragraph shows a number or bullet it should not have
- [ ] Every table has a blank line above, a pinned 400-weight header, light body rows and no bottom line on its last row
- [ ] Scope rows pair related items
- [ ] Figures in the Purpose, deliverables and commercial tables agree
- [ ] PDF render checked page by page
