# Google Cloud federation E2E

Authenticated real-Google-Cloud federation conformance tests are intentionally developer-triggered rather than run from GitHub Actions. The local BigQuery emulator cannot validate BigQuery Connection API federation or execute `EXTERNAL_QUERY` against Cloud SQL, AlloyDB, or Spanner.

Use the repository's `e2e/` Terraform harness for disposable real-cloud infrastructure and deterministic fixtures. Cloud SQL PostgreSQL coverage should follow the same local-only lifecycle: provision ephemeral resources, seed deterministic fixtures, run federation checks with local ADC, and unconditionally destroy the resources afterward.
