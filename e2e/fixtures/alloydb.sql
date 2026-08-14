BEGIN;

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
