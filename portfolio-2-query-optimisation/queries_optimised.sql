-- =====================================================================
-- MIT 8103 - Portfolio 2: workload queries (OPTIMISED versions)
-- Identical to queries.sql except Q2, Q5, Q6 and Q7, which are rewritten.
-- =====================================================================

-- @Q1 Patient history for a doctor (all visits, diagnoses, drugs)
SELECT e.started_at::date                          AS visit_date,
       b.branch_code,
       s.first_name || ' ' || s.last_name           AS doctor,
       e.chief_complaint,
       d.icd10_code || ' ' || d.description         AS primary_diagnosis,
       (SELECT string_agg(dr.generic_name || ' ' || dr.strength, ', ')
          FROM prescription p
          JOIN prescription_item pi USING (prescription_id)
          JOIN drug dr USING (drug_id)
         WHERE p.encounter_id = e.encounter_id)     AS drugs
FROM patient pt
JOIN encounter e  ON e.patient_id = pt.patient_id
JOIN branch b     ON b.branch_id = e.branch_id
JOIN staff s      ON s.staff_id = e.doctor_id
LEFT JOIN diagnosis d ON d.encounter_id = e.encounter_id AND d.is_primary
WHERE pt.hospital_no = 'LCH-0000013'
ORDER BY e.started_at DESC;

-- @Q2 One doctor's schedule for a day
-- REWRITE: the no_doctor_double_booking EXCLUDE constraint already builds a
-- GiST index on (doctor_id, slot), but it is PARTIAL (WHERE status <> 'cancelled').
-- The planner only uses a partial index when the query implies its predicate,
-- so we add the same condition. No new index is needed.
SELECT lower(a.slot) AS starts, a.status, p.hospital_no, p.first_name || ' ' || p.last_name AS patient, a.reason
FROM appointment a JOIN patient p USING (patient_id)
WHERE a.doctor_id = 17
  AND a.slot && tstzrange('2026-03-10 00:00+01', '2026-03-11 00:00+01')
  AND a.status <> 'cancelled'
ORDER BY lower(a.slot);

-- @Q3 Front-desk clinic list: all appointments at the Lekki branch for a day
SELECT lower(a.slot) AS starts, s.last_name AS doctor, p.hospital_no, p.last_name AS patient, a.status
FROM appointment a
JOIN patient p USING (patient_id)
JOIN staff s ON s.staff_id = a.doctor_id
WHERE a.branch_id = 2
  AND lower(a.slot) >= '2026-03-10 00:00+01'
  AND lower(a.slot) <  '2026-03-11 00:00+01'
ORDER BY lower(a.slot), s.last_name, a.appointment_id;

-- @Q4 Front-desk patient search by name (case-insensitive, prefix on first name)
SELECT hospital_no, first_name, last_name, date_of_birth, phone
FROM patient
WHERE lower(last_name) = lower('Okafor')
  AND lower(first_name) LIKE 'chi%'
ORDER BY first_name, date_of_birth;

-- @Q5 Cashier end-of-day: takings by payment method for one day
-- REWRITE: "paid_at::date = X" applies a function to every row, so no index
-- on paid_at can be used. A half-open range on the raw column is "sargable".
SELECT method, count(*) AS payments, sum(amount) AS total
FROM payment
WHERE paid_at >= TIMESTAMPTZ '2026-06-01 00:00+01'
  AND paid_at <  TIMESTAMPTZ '2026-06-02 00:00+01'
GROUP BY method
ORDER BY total DESC;

-- @Q6 Management report: monthly revenue billed per branch in 2025
-- REWRITE: read the pre-aggregated materialized view instead of 780k invoice lines.
SELECT b.branch_code, m.month, m.revenue
FROM monthly_branch_revenue m
JOIN branch b USING (branch_id)
WHERE m.month >= '2025-01-01' AND m.month < '2026-01-01'
ORDER BY b.branch_code, m.month;

-- @Q7 Billing desk: a patient's outstanding invoices
-- REWRITE: the invoice_balance view aggregates ALL invoices before the
-- patient filter is applied. LATERAL subqueries total only this patient's invoices.
SELECT i.invoice_no, t.total AS total_amount, COALESCE(p.paid, 0) AS amount_paid,
       t.total - COALESCE(p.paid, 0) AS balance_due
FROM invoice i
CROSS JOIN LATERAL (SELECT COALESCE(sum(quantity * unit_price), 0) AS total
                      FROM invoice_item WHERE invoice_id = i.invoice_id) t
CROSS JOIN LATERAL (SELECT sum(amount) AS paid
                      FROM payment WHERE invoice_id = i.invoice_id) p
WHERE i.patient_id = (SELECT patient_id FROM patient WHERE hospital_no = 'LCH-0000013')
  AND t.total - COALESCE(p.paid, 0) > 0
ORDER BY i.invoice_no;

-- @Q8 Lab dashboard: urgent tests still waiting, oldest first
SELECT lr.request_id, lr.requested_at, lr.priority, t.test_code, e.branch_id
FROM lab_request lr
JOIN lab_test t USING (test_id)
JOIN encounter e USING (encounter_id)
WHERE lr.status = 'requested'
  AND lr.priority IN ('urgent','stat')
ORDER BY lr.requested_at, lr.request_id
LIMIT 50;
