-- session: Cashier (posts a payment)
-- start_after: 0.5
SET search_path TO hospital;
BEGIN;
INSERT INTO payment (invoice_id, amount, method, reference, received_by, paid_at)
VALUES (1, 20000, 'transfer', 'TRF-0002', 7, '2026-11-14 10:00+01');
COMMIT;
SELECT log('posted and COMMITTED a 20,000 payment');
