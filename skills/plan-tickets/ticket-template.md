# Ticket body

Sections in this order. Leave out any that would be empty, except Acceptance criteria.

```markdown
# <PROJECT>-<CODE>-<Txx-yy> <Title>

<!-- BUG tickets only: -->
> [!CAUTION]
> **Security.** Outside the <CODE> budget lines. Pick up before any other <CODE> work.

<What exists today and why it falls short, with file:line evidence. Two short paragraphs at most.>

## Deliverables

- <Concrete outputs: migrations, endpoints, pages, docs. Name the pattern to follow with file:line.>
- **Existing bug fixed while here:** <only if small and adjacent>

## Open questions

- <Questions for the client or the team, each with a proposed answer where there is one>

## Files (indicative)

- `<path>` (new)
- `<path>`

## Acceptance criteria

- <Checkable outcome, provable by a test or a stated manual check>
- <A negative criterion also proves the valid path still works>

## Depends on

<PROJECT>-<CODE>-<Txx-yy> (#n), <PROJECT>-<CODE>-<Txx-yy> (#n) (<why, if not obvious>)

## Blocked on

<Who supplies what, in which format.>

+<N> day(s).

### Notes for dev

<Gotchas, prior art in sibling repos with exact paths, things to check in production first.>
```

## Style

- Plain, direct English; say what the code does, not what it is called. No hedging, no marketing words.
- Evidence over assertion: `file:line`, migration names, measured numbers.
- The `## Depends on` first sentence holds only the `#n` refs; notes such as "Coordinate with #378" go in a later sentence.
- Spike tickets: deliverable is a written recommendation with measurements against real queries or data, not code to keep. Their acceptance criteria name the decision to be made and the evidence it needs.
- Holding tickets (maintenance, support budgets): deliverables are how time is logged and reported, criteria are the budget not being passed without client agreement.
