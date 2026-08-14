# Google Cloud federation E2E

This directory is reserved for authenticated, real-Google-Cloud federation conformance tests. The local BigQuery emulator cannot validate BigQuery Connection API federation or execute `EXTERNAL_QUERY` against Cloud SQL, AlloyDB, or Spanner.

The provider milestones are developed on the RFC implementation branch. Real-GCP execution should use short-lived credentials (prefer Workload Identity Federation), ephemeral Terraform resources, and unconditional teardown.
