# Claude / AI assistant notes

In **Claude Code**, macro-package work can be delegated to the project subagent [`dbt-macro-package-specialist`](.claude/agents/dbt-macro-package-specialist.md) (preloads `implement-dbt-macro`, `implement-dbt-macro-unit-test`, and `implement-dbt-package-feature`). For **lint plus tests** (`make lint`, then unit/integration tests), use [`verifier`](.claude/agents/verifier.md) (preloads `lint-and-fix`, `test-and-fix`). Restart the session or use `/agents` after changing agent files ([subagents](https://code.claude.com/docs/en/sub-agents)).

## Macros and packages

- Package macros live under [`macros/`](macros/); follow [`macros/CLAUDE.md`](macros/CLAUDE.md) for structure and `adapter.dispatch` usage.
- This project is a **dbt package** (`name: dbt_bigquery_federation` in [`dbt_project.yml`](dbt_project.yml)). Consumers override dispatched macros via root `dispatch` + `search_order` (see [dbt dispatch](https://docs.getdbt.com/reference/dbt-jinja-functions/dispatch?version=1.12)).
- Cross-project **Mesh** dependencies are a different mechanism; see [project dependencies](https://docs.getdbt.com/docs/mesh/govern/project-dependencies?version=1.12#when-to-use-package-dependencies) if you outgrow vendoring macros as a package.

## Integration tests

- The harness project is [`integration_tests/`](integration_tests/); see [`integration_tests/CLAUDE.md`](integration_tests/CLAUDE.md) for mirroring macro tests under `macros/tests/`.
- Planner tests assert SQL strings. Do not `run_query` `EXTERNAL_QUERY`. Postgres is the Jinja execution engine, not the federation warehouse.

## Verification

From the repo root: `make run-unit-tests` for most changes; add `make run-integration-tests` when SQL compilation or model behavior is affected.
