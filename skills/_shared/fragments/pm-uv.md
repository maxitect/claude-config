### uv

- [ ] Is `uv.lock` committed alongside any dependency change in `pyproject.toml`?
- [ ] Are dev-only tools under `[dependency-groups] dev` rather than runtime dependencies?

**Probes**

```bash
uv run mypy <path> 2>&1 | head -40
uv run ruff check <file>
uv run pytest <path>::<test> 2>&1 | tail -20
```
