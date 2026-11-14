-- =====================================================================
-- Portfolio 1 - Constraint tests
-- Inserts a small amount of valid data, then deliberately attempts
-- inserts that break business rules. Each "SHOULD FAIL" test must be
-- rejected by the database.
-- Run: psql -d laguna_care -f schema.sql && psql -d laguna_care -f constraint_tests.sql
-- =====================================================================
SET search_path TO hospital;
\echo '=== Valid setup data ==='

INSERT INTO branch (branch_code, name, address, phone, opened_on) VALUES
 ('IKJ','Laguna Care Ikeja','12 Allen Avenue, Ikeja','01-2000001','2015-03-01'),
 ('LKI','Laguna Care Lekki','5 Admiralty Way, Lekki Phase 1','01-2000002','2019-07-15');

INSERT INTO department (branch_id, name) VALUES (1,'General Medicine'), (1,'Cardiology'), (2,'General Medicine');

INSERT INTO staff (staff_no, home_branch_id, department_id, first_name, last_name, role, email, hire_date) VALUES
 ('LC-S-00001',1,1,'Adaeze','Okafor','doctor','a.okafor@lagunacare.ng','2016-01-10'),
 ('LC-S-00002',1,NULL,'Tunde','Bakare','receptionist','t.bakare@lagunacare.ng','2018-05-02'),
 ('LC-S-00003',1,NULL,'Halima','Musa','lab_scientist','h.musa@lagunacare.ng','2020-09-14');

INSERT INTO doctor (staff_id, specialty, mdcn_licence_no) VALUES (1,'Internal Medicine','MDCN/R/45123');

INSERT INTO insurance_provider (name, provider_type) VALUES ('Hygeia HMO','HMO');

INSERT INTO patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, blood_group, phone, provider_id, policy_no)
VALUES ('LCH-0000001',1,'Chinedu','Eze','1988-04-12','M','O+','08030000001',1,'HYG-778812');

INSERT INTO appointment (patient_id, doctor_id, branch_id, slot, booked_by)
VALUES (1,1,1,'[2026-11-20 09:00+01, 2026-11-20 09:30+01)',2);

INSERT INTO ward (branch_id, name, ward_type, daily_rate) VALUES (1,'Ward A','general',15000);
INSERT INTO bed (ward_id, bed_label) VALUES (1,'A-01');

INSERT INTO drug (generic_name, brand_name, dosage_form, strength, unit_price)
VALUES ('Artemether/Lumefantrine','Coartem','tablet','20/120 mg',350);
INSERT INTO branch_drug_stock (branch_id, drug_id, quantity) VALUES (1,1,5);

\echo ''
\echo '=== TEST 1 (SHOULD FAIL): doctor double-booked for an overlapping slot ==='
INSERT INTO appointment (patient_id, doctor_id, branch_id, slot)
VALUES (1,1,1,'[2026-11-20 09:15+01, 2026-11-20 09:45+01)');

\echo '=== TEST 1b (SHOULD SUCCEED): adjacent slot 09:30-10:00 does not overlap ==='
INSERT INTO appointment (patient_id, doctor_id, branch_id, slot)
VALUES (1,1,1,'[2026-11-20 09:30+01, 2026-11-20 10:00+01)');

\echo '=== TEST 2 (SHOULD FAIL): drug stock going negative ==='
UPDATE branch_drug_stock SET quantity = quantity - 10 WHERE branch_id = 1 AND drug_id = 1;

\echo '=== TEST 3 (SHOULD FAIL): two patients in the same bed at the same time ==='
INSERT INTO patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, phone)
VALUES ('LCH-0000002',1,'Ngozi','Adeyemi','1995-09-30','F','08030000002');
INSERT INTO admission (patient_id, bed_id, admitting_doctor_id, admitted_at)
VALUES (1,1,1,'2026-11-21 10:00+01');
INSERT INTO admission (patient_id, bed_id, admitting_doctor_id, admitted_at)
VALUES (2,1,1,'2026-11-22 08:00+01');

\echo '=== TEST 4 (SHOULD FAIL): invalid sex value (CHECK) ==='
INSERT INTO patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, phone)
VALUES ('LCH-0000003',1,'Test','Patient','2000-01-01','X','08030000003');

\echo '=== TEST 5 (SHOULD FAIL): duplicate hospital number (UNIQUE) ==='
INSERT INTO patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, phone)
VALUES ('LCH-0000001',2,'Duplicate','Number','1990-01-01','F','08030000004');

\echo '=== TEST 6 (SHOULD FAIL): appointment with a non-doctor (FOREIGN KEY) ==='
INSERT INTO appointment (patient_id, doctor_id, branch_id, slot)
VALUES (1,2,1,'[2026-11-20 11:00+01, 2026-11-20 11:30+01)');

\echo '=== TEST 7 (SHOULD FAIL): policy number with no insurance provider ==='
INSERT INTO patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, phone, policy_no)
VALUES ('LCH-0000005',1,'No','Provider','1990-01-01','M','08030000005','ABC-1');

\echo '=== TEST 8 (SHOULD FAIL): two primary diagnoses for one encounter ==='
INSERT INTO encounter (patient_id, doctor_id, branch_id, appointment_id, chief_complaint)
VALUES (1,1,1,1,'Fever and headache for 3 days');
INSERT INTO diagnosis (encounter_id, icd10_code, description, is_primary) VALUES (1,'B54','Malaria, unspecified',TRUE);
INSERT INTO diagnosis (encounter_id, icd10_code, description, is_primary) VALUES (1,'R51','Headache',TRUE);

\echo '=== TEST 9 (SHOULD FAIL): discharge before admission ==='
UPDATE admission SET discharged_at = '2026-11-20 08:00+01' WHERE patient_id = 1;

\echo '=== TEST 10 (SHOULD FAIL): insurance payment without a provider ==='
INSERT INTO invoice (invoice_no, patient_id, branch_id, encounter_id) VALUES ('INV-IKJ-000001',1,1,1);
INSERT INTO invoice_item VALUES (1,1,'consultation','GP consultation',1,10000), (1,2,'drug','Coartem x 24',24,350);
INSERT INTO payment (invoice_id, amount, method) VALUES (1,5000,'insurance');

\echo '=== Derived balance from view (total 18,400; 5,000 cash paid -> 13,400 due) ==='
INSERT INTO payment (invoice_id, amount, method, reference) VALUES (1,5000,'cash','RCPT-0001');
SELECT invoice_no, total_amount, amount_paid, balance_due FROM invoice_balance;
