-- =====================================================================
-- MIT 8103 - Portfolio 2: workload queries (ORIGINAL versions)
-- Laguna Care Specialist Hospital
-- Each query is a real task a hospital user performs. Blocks are
-- separated by "-- @Qn" markers so run_benchmark.py can time them.
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
SELECT lower(a.slot) AS starts, a.status, p.hospital_no, p.first_name || ' ' || p.last_name AS patient, a.reason
FROM appointment a JOIN patient p USING (patient_id)
WHERE a.doctor_id = 17
  AND a.slot && tstzrange('2026-03-10 00:00+01', '2026-03-11 00:00+01')
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
SELECT method, count(*) AS payments, sum(amount) AS total
FROM payment
WHERE paid_at::date = DATE '2026-06-01'
GROUP BY method
ORDER BY total DESC;

-- @Q6 Management report: monthly revenue billed per branch in 2025
SELECT b.branch_code,
       date_trunc('month', i.issued_at)::date AS month,
       sum(ii.quantity * ii.unit_price)       AS revenue
FROM invoice i
JOIN invoice_item ii USING (invoice_id)
JOIN branch b USING (branch_id)
WHERE i.issued_at >= '2025-01-01' AND i.issued_at < '2026-01-01'
  AND i.status <> 'void'
GROUP BY b.branch_code, month
ORDER BY b.branch_code, month;

-- @Q7 Billing desk: a patient's outstanding invoices
SELECT invoice_no, total_amount, amount_paid, balance_due
FROM invoice_balance
WHERE patient_id = (SELECT patient_id FROM patient WHERE hospital_no = 'LCH-0000013')
  AND balance_due > 0
ORDER BY invoice_no;

-- @Q8 Lab dashboard: urgent tests still waiting, oldest first
SELECT lr.request_id, lr.requested_at, lr.priority, t.test_code, e.branch_id
FROM lab_request lr
JOIN lab_test t USING (test_id)
JOIN encounter e USING (encounter_id)
WHERE lr.status = 'requested'
  AND lr.priority IN ('urgent','stat')
ORDER BY lr.requested_at, lr.request_id
LIMIT 50;
