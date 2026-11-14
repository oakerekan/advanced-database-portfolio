-- =====================================================================
-- MIT 8103 - Portfolio 2: optimisations
-- Each index is justified by the query it serves (see README).
-- Note: PostgreSQL creates indexes automatically for PRIMARY KEY,
-- UNIQUE and EXCLUDE constraints, but NOT for foreign keys.
-- =====================================================================
SET search_path TO hospital;

-- Q1: find a patient's encounters, newest first (FK patient_id was unindexed)
CREATE INDEX idx_encounter_patient_started ON encounter (patient_id, started_at DESC);

-- Q1: find the prescription(s) written in an encounter (FK encounter_id was unindexed)
CREATE INDEX idx_prescription_encounter ON prescription (encounter_id);

-- Q3: a branch's appointments for a date range. Expression index on the
-- range's start time, because the query filters on lower(slot).
CREATE INDEX idx_appointment_branch_start ON appointment (branch_id, lower(slot));

-- Q4: case-insensitive surname match + first-name prefix search.
-- text_pattern_ops lets LIKE 'chi%' use the index whatever the collation.
CREATE INDEX idx_patient_name_search
    ON patient (lower(last_name), lower(first_name) text_pattern_ops);

-- Q5: payments in a time window (only usable once the query is rewritten
-- to compare paid_at directly instead of paid_at::date)
CREATE INDEX idx_payment_paid_at ON payment (paid_at);

-- Q7: a patient's invoices, and the payments against each invoice
CREATE INDEX idx_invoice_patient ON invoice (patient_id);
CREATE INDEX idx_payment_invoice ON payment (invoice_id);

-- Q8: partial index - only the small set of tests still waiting are indexed,
-- so the index stays tiny while the lab_request table keeps growing.
CREATE INDEX idx_lab_request_pending
    ON lab_request (requested_at)
    WHERE status = 'requested';

-- Q6: a reporting query that must read a whole year of invoices cannot be
-- fixed with an index. Pre-aggregate it in a materialized view, refreshed
-- nightly (REFRESH MATERIALIZED VIEW CONCURRENTLY needs the unique index).
CREATE MATERIALIZED VIEW monthly_branch_revenue AS
SELECT i.branch_id,
       date_trunc('month', i.issued_at)::date AS month,
       sum(ii.quantity * ii.unit_price)       AS revenue
FROM invoice i
JOIN invoice_item ii USING (invoice_id)
WHERE i.status <> 'void'
GROUP BY i.branch_id, month;
CREATE UNIQUE INDEX ux_monthly_branch_revenue ON monthly_branch_revenue (branch_id, month);

ANALYZE;
