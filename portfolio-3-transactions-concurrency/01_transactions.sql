-- =====================================================================
-- MIT 8103 - Portfolio 3, Part A: single-session transactions
-- COMMIT, automatic ROLLBACK on error (atomicity), explicit ROLLBACK,
-- and SAVEPOINT for partial rollback.
-- Run: psql -d lagoon_p3 -f seed.sql && psql -d lagoon_p3 -f 01_transactions.sql
-- =====================================================================
SET search_path TO hospital;
\pset footer off

\echo
\echo '############ A1. COMMIT: dispense a whole prescription as one unit ############'
\echo '-- Before: Ikeja stock and Chinedu''s prescription'
SELECT d.generic_name, s.quantity AS ikeja_stock
FROM branch_drug_stock s JOIN drug d USING (drug_id) WHERE s.branch_id = 1 ORDER BY drug_id;
SELECT drug_id, quantity, quantity_dispensed FROM prescription_item WHERE prescription_id = 1 ORDER BY drug_id;

BEGIN;
SELECT dispense_item(1, 1, 1::smallint);   -- 6 Coartem
SELECT dispense_item(1, 2, 1::smallint);   -- 10 Paracetamol
COMMIT;

\echo '-- After COMMIT: stock reduced, lines dispensed, prescription closed, drugs billed'
SELECT d.generic_name, s.quantity AS ikeja_stock
FROM branch_drug_stock s JOIN drug d USING (drug_id) WHERE s.branch_id = 1 ORDER BY drug_id;
SELECT p.status, pi.drug_id, pi.quantity, pi.quantity_dispensed
FROM prescription p JOIN prescription_item pi USING (prescription_id) WHERE p.prescription_id = 1 ORDER BY drug_id;
SELECT line_no, item_type, description, quantity, unit_price FROM invoice_item WHERE invoice_id = 1 ORDER BY line_no;


\echo
\echo '############ A2. ATOMICITY: an error half-way rolls back the whole transaction ############'
\echo '-- A second prescription needs 6 more Coartem, but only 4 are left at Ikeja.'
INSERT INTO prescription (encounter_id) VALUES (1);                       -- prescription 2
INSERT INTO prescription_item (prescription_id, drug_id, dose, frequency, duration_days, quantity)
VALUES (2,2,'2 tablets','8-hourly',3,10), (2,1,'1 strip','once daily',6,6);

BEGIN;
SELECT dispense_item(2, 2, 1::smallint);    -- Paracetamol: succeeds (stock 90 -> 80 inside the transaction)
\echo '-- Inside the transaction, Paracetamol stock is now:'
SELECT quantity AS paracetamol_inside_txn FROM branch_drug_stock WHERE branch_id = 1 AND drug_id = 2;
SELECT dispense_item(2, 1, 1::smallint);    -- Coartem: fails, insufficient stock -> transaction aborted
SELECT 1;                                   -- any further statement is refused until ROLLBACK
ROLLBACK;

\echo '-- After ROLLBACK: Paracetamol is back at 90 and nothing on prescription 2 was dispensed'
SELECT d.generic_name, s.quantity AS ikeja_stock
FROM branch_drug_stock s JOIN drug d USING (drug_id) WHERE s.branch_id = 1 ORDER BY drug_id;
SELECT drug_id, quantity, quantity_dispensed FROM prescription_item WHERE prescription_id = 2 ORDER BY drug_id;
SELECT count(*) AS invoice_lines_still FROM invoice_item WHERE invoice_id = 1;


\echo
\echo '############ A3. Explicit ROLLBACK: cashier cancels a mistaken payment ############'
BEGIN;
INSERT INTO payment (invoice_id, amount, method, reference, received_by)
VALUES (1, 99999, 'pos', 'POS-TYPO-1', 7);
SELECT invoice_no, amount_paid AS paid_seen_inside_txn FROM invoice_balance WHERE invoice_id = 1;
ROLLBACK;
SELECT invoice_no, amount_paid AS paid_after_rollback FROM invoice_balance WHERE invoice_id = 1;


\echo
\echo '############ A4. SAVEPOINT: admit a patient, recover from one failed step ############'
\echo '-- Amina is already in ICU-01 (bed 1).'
INSERT INTO admission (patient_id, bed_id, admitting_doctor_id, admitted_at)
VALUES (3, 1, 1, now() - INTERVAL '6 hours');

BEGIN;
INSERT INTO encounter (patient_id, doctor_id, branch_id, encounter_type, chief_complaint)
VALUES (2, 2, 1, 'emergency', 'Severe difficulty breathing');          -- step 1: emergency visit
SAVEPOINT before_bed;
INSERT INTO admission (patient_id, bed_id, admitting_doctor_id, encounter_id)
VALUES (2, 1, 2, currval('encounter_encounter_id_seq'));               -- step 2: ICU-01 is occupied -> error
ROLLBACK TO SAVEPOINT before_bed;                                       -- undo step 2 only
INSERT INTO admission (patient_id, bed_id, admitting_doctor_id, encounter_id)
VALUES (2, 2, 2, currval('encounter_encounter_id_seq'));               -- step 2 again: ICU-02 is free
COMMIT;

\echo '-- Result: the emergency encounter (step 1) survived, Ngozi is in ICU-02'
SELECT a.admission_id, p.first_name, b.bed_label, a.encounter_id, a.discharged_at IS NULL AS still_admitted
FROM admission a JOIN patient p USING (patient_id) JOIN bed b USING (bed_id) ORDER BY admission_id;
SELECT encounter_id, encounter_type, chief_complaint FROM encounter ORDER BY encounter_id;


\echo
\echo '############ A5. Default isolation level ############'
SHOW default_transaction_isolation;
