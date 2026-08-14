# Google Cloud federation E2E

Authenticated real-Google-Cloud tests validate the boundary that the local BigQuery emulator cannot cover: BigQuery Connection API, IAM, networking, `EXTERNAL_QUERY`, live metadata discovery, and runtime type conversion for Cloud SQL, AlloyDB, and Spanner.

Provider implementation and GCP conformance tests should share the same logical scenarios while keeping provider-specific infrastructure separate. Prefer Workload Identity Federation, ephemeral resources, and unconditional teardown.
