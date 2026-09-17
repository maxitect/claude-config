### Python

- [ ] Are public functions annotated — params and return? Is `Any` used where a real type exists?
- [ ] Are mutable default arguments (`def f(x=[])`) present?
- [ ] Are bare `except:` / `except Exception:` blocks swallowing errors without re-raise or log?
- [ ] Is input validated at the boundary (Pydantic model / dataclass + validation) rather than
      trusting raw `dict` payloads through the call stack?
- [ ] Are `Optional` values unwrapped without a None check?
- [ ] Is blocking I/O called inside `async def` without `run_in_executor` / an async driver?
- [ ] Are f-strings used to build SQL or shell commands? (parameterise / `shlex`)
- [ ] Are module-level side effects (network, DB, file reads at import time) introduced?
- [ ] Do new dependencies land in the project manifest, not just the environment?

**Probes**

| Claim                     | Probe                                                             |
| ------------------------- | -------------------------------------------------------------------- |
| Type error                | `mypy <path>` or `pyright <path>` — whichever the repo configures     |
| Lint / style violation    | `ruff check <file>` (or `flake8` / `pylint` per repo config)          |
| Logic bug in pure function | `python -c` or a one-off `pytest -k <test>` with the breaking input   |
| Test coverage claim       | run the suite; quote the decisive line                                |
