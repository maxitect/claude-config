### Poetry (+ poe)

- [ ] Is `poetry.lock` regenerated and committed with any `pyproject.toml` dependency change?
- [ ] Are deps in the right group — dev tooling under `[tool.poetry.group.dev.dependencies]`, not runtime?
- [ ] Are version constraints pinned sanely (no unbounded `*`)?

**Probes** — read `[tool.poe.tasks]` in `pyproject.toml` for the real task names before running these:

```bash
grep -A30 '\[tool.poe.tasks\]' pyproject.toml    # the authoritative task list
poetry run poe lint 2>&1 | head -40
poetry run poe typecheck 2>&1 | head -40
poetry run poe test 2>&1 | tail -20
poetry run pytest <path>::<test> 2>&1 | tail -20  # single-test probe
poetry run ruff check <file>                       # single-file lint probe
```
