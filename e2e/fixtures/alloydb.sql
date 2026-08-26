BEGIN;

DROP TABLE IF EXISTS public.type_matrix;
CREATE TABLE public.type_matrix (
  id bigint PRIMARY KEY,
  -- EXTERNAL_QUERY-native PostgreSQL types (package type_map natives)
  col_smallint smallint NOT NULL,
  col_integer integer NOT NULL,
  col_real real NOT NULL,
  col_double double precision NOT NULL,
  col_boolean boolean NOT NULL,
  col_text text NOT NULL,
  col_varchar character varying(32) NOT NULL,
  col_char character(1) NOT NULL,
  col_bytea bytea NOT NULL,
  col_date date NOT NULL,
  col_timestamp timestamp without time zone NOT NULL,
  col_timestamptz timestamp with time zone NOT NULL,
  col_time time without time zone NOT NULL,
  col_json json NOT NULL,
  col_xml xml NOT NULL,
  col_bit bit(8) NOT NULL,
  col_varbit bit varying NOT NULL,
  col_numeric numeric(12, 2) NOT NULL,
  -- Unsupported under EXTERNAL_QUERY; federated_relation(safe) remote-casts to text
  col_uuid uuid NOT NULL,
  col_jsonb jsonb NOT NULL,
  col_inet inet NOT NULL,
  col_interval interval NOT NULL
);

INSERT INTO public.type_matrix (
  id,
  col_smallint, col_integer, col_real, col_double, col_boolean,
  col_text, col_varchar, col_char, col_bytea,
  col_date, col_timestamp, col_timestamptz, col_time,
  col_json, col_xml, col_bit, col_varbit, col_numeric,
  col_uuid, col_jsonb, col_inet, col_interval
) VALUES (
  1,
  1, 2, 1.25::real, 2.5::double precision, TRUE,
  'hello', 'world', 'A', E'\\x0102'::bytea,
  DATE '2026-01-02',
  TIMESTAMP '2026-01-02 03:04:05',
  TIMESTAMPTZ '2026-01-02 03:04:05+00',
  TIME '03:04:05',
  '{"source":"alloydb"}'::json,
  '<root>ok</root>'::xml,
  B'10101010',
  B'1100',
  12.34,
  '11111111-1111-1111-1111-111111111111'::uuid,
  '{"active":true}'::jsonb,
  '127.0.0.1'::inet,
  INTERVAL '1 day 02:03:04'
);

DROP TABLE IF EXISTS public.orders;
CREATE TABLE public.orders (
  id bigint PRIMARY KEY,
  user_uuid uuid NOT NULL,
  payload jsonb NOT NULL,
  amount numeric(12, 2) NOT NULL,
  created_at timestamp without time zone NOT NULL
);

INSERT INTO public.orders (id, user_uuid, payload, amount, created_at) VALUES
  (1, '11111111-1111-1111-1111-111111111111', '{"source":"alloydb","active":true}', 12.34, '2026-01-02 03:04:05'),
  (2, '22222222-2222-2222-2222-222222222222', '{"source":"alloydb","active":false}', 56.78, '2026-02-03 04:05:06');

COMMIT;
