-- Spanner GoogleSQL DDL for Layer 3 dialect tests (TypeMatrix only).
-- Keep column shapes aligned with e2e/terraform/modules/spanner/main.tf TypeMatrix.

CREATE TABLE TypeMatrix (
  Id INT64 NOT NULL,
  ColBool BOOL NOT NULL,
  ColBytes BYTES(16) NOT NULL,
  ColDate DATE NOT NULL,
  ColFloat FLOAT64 NOT NULL,
  ColJson JSON NOT NULL,
  ColNumeric NUMERIC NOT NULL,
  ColString STRING(64) NOT NULL,
  ColTimestamp TIMESTAMP NOT NULL,
  ColArray ARRAY<STRING(16)>
) PRIMARY KEY (Id);
