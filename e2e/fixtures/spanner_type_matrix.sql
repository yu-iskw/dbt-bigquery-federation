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
  JSON '{"source":"spanner","active":true}',
  12.34,
  'alpha',
  TIMESTAMP '2026-01-02T03:04:05Z',
  ['a', 'b']
);
