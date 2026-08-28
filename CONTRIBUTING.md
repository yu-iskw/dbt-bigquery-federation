# Contributing to dbt_bigquery_federation

This guide is for **package maintainers** and **contributors** working in this repository. It also documents **downstream** topics—**dispatch overrides** and **dbt docs** metadata—for projects that depend on this package. For **installation** and macro usage, start with [README.md](README.md). Architecture: [docs/rfcs/0001-bigquery-federation-architecture.md](docs/rfcs/0001-bigquery-federation-architecture.md).

## Before you start

This repository is a dbt package of pinned BigQuery `EXTERNAL_QUERY` macros.
Keep changes focused. `federated_relation` must never call `run_query`.

**User-facing** install and macro documentation: [README.md](README.md).

## Downstream projects: overrides and dbt docs

These notes apply to **root dbt projects** that list this repository (or a fork) under `packages:` and run `dbt deps`.

### Overriding macro implementations

Public macros use dbt’s **`adapter.dispatch`** with namespace **`dbt_bigquery_federation`**. In your **root** project you can override implementations with `dispatch` and `search_order` in `dbt_project.yml` ([dispatch docs](https://docs.getdbt.com/reference/dbt-jinja-functions/dispatch?version=1.12)).

Remote Cloud SQL PostgreSQL quoting is **not** selected via `postgres__*` adapter macros. The dbt target is BigQuery (or Postgres in this repo’s tests); remote dialect routing is an explicit provider router.

### dbt docs

Macro descriptions and arguments are defined in [`macros/properties.yml`](macros/properties.yml). After `dbt deps`, generate your project’s docs as usual; macro pages reflect this metadata.

**Maintainers** run **lint** and **tests** from the repository root (Postgres Jinja engine, dbt-core 1.10, 1.11, and 1.12, optional non-blocking Fusion lane); see [How to develop](#how-to-develop) and [Test harness and Fusion](#test-harness-and-fusion). Workspace rules for agents: [`AGENTS.md`](AGENTS.md). **Claude Code** workflow: [`CLAUDE.md`](CLAUDE.md).

## Development layout and tooling

### Repository map

Paths you touch most often when developing the package:

- **`macros/`** — shipped package macros.
- **[`macros/properties.yml`](macros/properties.yml)** — dbt docs metadata for public macros (see [`macros/CLAUDE.md`](macros/CLAUDE.md)).
- **[`integration_tests/`](integration_tests/)** — nested dbt project for macro-runner unit tests and integration `dbt build` / `dbt compile` (`uv`, `nox`, Postgres). Details: [`integration_tests/README.md`](integration_tests/README.md).
- **[`docs/`](docs/)** — RFC and maintainer walkthroughs (for example [`docs/starter_walkthrough.md`](docs/starter_walkthrough.md)).
- **[`.claude/skills/`](.claude/skills/)**, **[`.claude/agents/`](.claude/agents/)** — Claude Code skills and subagents.
- **[`.codex/`](.codex/)** — Codex CLI configuration.
- **[`AGENTS.md`](AGENTS.md)** — workspace rules and agent documentation map.
- **[`CLAUDE.md`](CLAUDE.md)** — Claude Code–specific workflow and links into macro/test conventions.

**`.agents/skills`** is a symlink to **`../.claude/skills/`** for tools that expect that path—do not maintain duplicate skill trees.

### AI assistants and editor tooling

**Codex** — Shared configuration in [`.codex/config.toml`](.codex/config.toml); project instructions also align with [`AGENTS.md`](AGENTS.md).

Opt-in Codex CLI profiles:

- `fast`: smaller, iterative tasks
- `deep`: planning, review, and more complex changes
- `review`: bug-finding and regression review
- `verify`: lint/test orchestration and failure analysis

Read-only review subagents for Codex:

- `reviewer` — macros, SQL generation paths, workflows, and config regressions
- `test_gap_checker` — missing unit, integration, and workflow coverage

Implementation and verification subagents for Codex:

- `macro_package_specialist` — macro changes, public macro docs, mirrored macro-runner tests, and related package docs
- `verifier` — `make lint`, targeted dbt verification, and exact command/outcome reporting

```bash
codex --profile fast
codex --profile deep
```

**Claude Code** — See [`CLAUDE.md`](CLAUDE.md) for subagents (for example `dbt-macro-package-specialist`, `verifier`) and macro/integration pointers.

### Test harness and Fusion

From the **repository root**, typical flows:

```bash
make setup-integration-tests
make lint
make run-unit-tests
make run-integration-tests
make run-fusion-tests
```

- **dbt Core lane (required):** Postgres Jinja engine, `dbt-core-1-10`, `dbt-core-1-11`, and `dbt-core-1-12`.
- **Fusion lane (preview, non-blocking in CI):** same Postgres contract via [`integration_tests/noxfile_fusion.py`](integration_tests/noxfile_fusion.py). The harness sets **`DBT_ALLOW_EXPERIMENTAL_ADAPTERS=true`** because Fusion still treats postgres as experimental. Set **`DBT_FUSION_VERSION`** to pin a build.

`make run-fusion-tests` runs **both** Fusion unit and Fusion integration targets.

## How to develop

### Prerequisites

- **Docker Engine** and **Docker Compose v2** (Postgres-backed local tests start a Compose-managed container).
- **[uv](https://docs.astral.sh/uv/)** — the harness under `integration_tests/` uses `uv sync` and `uv run nox ...`.
- **Python** — `integration_tests/pyproject.toml` requires Python `>=3.10`. Local `make` targets for Core use nox sessions pinned to **3.12**.
- **pre-commit** — `make lint` uses the root `dev` dependency group (`uv run --group dev pre-commit run -a`).

### How to set up the development environment

```shell
make setup-integration-tests
```

That runs `uv sync` in `integration_tests/`.

### Linting

From the repository root:

```shell
make lint
```

### How to run unit testing

Unit tests execute dbt macros with `dbt run-operation` on Postgres for `dbt-core-1-10`, `dbt-core-1-11`, and `dbt-core-1-12`. They assert planner/SQL strings and do **not** run `EXTERNAL_QUERY`.

```shell
make run-unit-tests
```

### How to implement unit tests

- Add or update package macros under `macros/`.
- Add matching macro tests under `integration_tests/macros/tests/`, **mirroring** the directory layout under `macros/`.
- Use [dbt-unittest](https://github.com/yu-iskw/dbt-unittest) (`dbt_unittest.*`) for assertions.
- Call package macros as `{{ dbt_bigquery_federation.federated_relation(...) }}` and compare SQL strings.
- Register new test macros from `integration_tests/macros/tests/test_macros.sql`.

### How to run integration testing

```shell
make run-integration-tests
```

This runs `dbt build --exclude federation` (seed + example staging model) then `dbt compile --select federation` (federated `EXTERNAL_QUERY` SQL, not executed on Postgres).

### Local Postgres

The Postgres target uses a Docker Compose managed container during local test runs.

The dbt profile still connects with these defaults:

- host: `localhost`
- port: `5432`
- user: `postgres`
- password: `postgres`
- database: `dbt_package_template`
- schema: `dbt_package_template`

You can override any of them with `DBT_POSTGRES_*` environment variables.

### Starter conventions

- Implement public package macros with `adapter.dispatch` and `macro_namespace: 'dbt_bigquery_federation'`.
- When you add or change a **public** macro, update [`macros/properties.yml`](macros/properties.yml).
- Macro unit tests mirror the package tree under `integration_tests/macros/tests/`.
- Update [README.md](README.md) for **consumer-facing** behavior and **`docs/`** as needed.
