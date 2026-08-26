-- Spanner GoogleSQL DML for Layer 3 dialect remote-body tests.
-- Aligned with e2e/fixtures/spanner_type_matrix.sql.

INSERT OR UPDATE INTO TypeMatrix (
  Id,
  ColBool,
  ColBytes,
  ColDate,
  ColFloat,
  ColJson,
  ColNumeric,
  ColString,
  ColTimestamp,
  ColArray
) VALUES (
  1,
  TRUE,
  b'\x01\x02',
  DATE '2026-01-02',
  1.5,
  JSON '{"source":"dialect","active":true}',
  12.34,
  'alpha',
  TIMESTAMP '2026-01-02T03:04:05Z',
  ['a', 'b']
);
