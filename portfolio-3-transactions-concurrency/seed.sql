-- =====================================================================
-- MIT 8103 - Portfolio 3: small, known starting data.
-- Every script and scenario starts by resetting to exactly this state,
-- so results are repeatable. IDs are fixed by RESTART IDENTITY.
-- =====================================================================
SET search_path TO hospital;
SET client_min_messages = warning;   -- hide the list of cascaded tables

TRUNCATE branch, insurance_provider, drug, lab_test RESTART IDENTITY CASCADE;

INSERT INTO branch (branch_code, name, address, phone, opened_on) VALUES
 ('IKJ','Laguna Care Ikeja','12 Allen Avenue, Ikeja','01-2000001','2015-03-01'),   -- branch 1
 ('LKI','Laguna Care Lekki','5 Admiralty Way, Lekki Phase 1','01-2000002','2019-07-15'); -- branch 2

INSERT INTO department (branch_id, name) VALUES (1,'General Medicine'), (2,'General Medicine');

INSERT INTO staff (staff_no, home_branch_id, department_id, first_name, last_name, role, email, hire_date) VALUES
 ('LC-S-00001',1,1,'Adaeze','Okafor','doctor','okafor@lagunacare.ng','2016-01-10'),          -- 1
 ('LC-S-00002',1,1,'Ibrahim','Bello','doctor','bello@lagunacare.ng','2017-02-01'),           -- 2
 ('LC-S-00003',1,NULL,'Tunde','Bakare','receptionist','bakare@lagunacare.ng','2018-05-02'),  -- 3
 ('LC-S-00004',1,NULL,'Ngozi','Eze','receptionist','eze@lagunacare.ng','2019-03-11'),        -- 4
 ('LC-S-00005',1,NULL,'Halima','Musa','pharmacist','musa@lagunacare.ng','2020-09-14'),       -- 5
 ('LC-S-00006',2,NULL,'Chidi','Obi','pharmacist','obi@lagunacare.ng','2021-01-04'),          -- 6
 ('LC-S-00007',1,NULL,'Kemi','Lawal','billing_officer','lawal@lagunacare.ng','2019-06-20'),  -- 7
 ('LC-S-00008',1,1,'Aisha','Sani','nurse','sani@lagunacare.ng','2020-02-17');                -- 8

INSERT INTO doctor (staff_id, specialty, mdcn_licence_no) VALUES
 (1,'Internal Medicine','MDCN/R/45123'), (2,'Internal Medicine','MDCN/R/47788');

INSERT INTO patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, phone) VALUES
 ('LCH-0000001',1,'Chinedu','Eze','1988-04-12','M','08030000001'),      -- 1
 ('LCH-0000002',1,'Ngozi','Adeyemi','1995-09-30','F','08030000002'),    -- 2
 ('LCH-0000003',2,'Amina','Bello','1979-12-05','F','08030000003');      -- 3

INSERT INTO drug (generic_name, brand_name, dosage_form, strength, unit_price) VALUES
 ('Artemether/Lumefantrine','Coartem','tablet','20/120 mg',350),       -- drug 1
 ('Paracetamol','Emzor Paracetamol','tablet','500 mg',50);             -- drug 2

INSERT INTO branch_drug_stock (branch_id, drug_id, quantity, reorder_level) VALUES
 (1,1,10,5), (1,2,100,20),        -- Ikeja: 10 Coartem, 100 Paracetamol
 (2,1,10,5), (2,2,100,20);        -- Lekki: 10 Coartem, 100 Paracetamol

-- Wards and beds at Ikeja: ICU has 2 beds (ids 1, 2); general ward has 2 (ids 3, 4)
INSERT INTO ward (branch_id, name, ward_type, daily_rate) VALUES (1,'ICU','icu',120000), (1,'Ward A','general',15000);
INSERT INTO bed (ward_id, bed_label) VALUES (1,'ICU-01'), (1,'ICU-02'), (2,'A-01'), (2,'A-02');

-- One consultation for Chinedu with a 2-drug prescription and an invoice
INSERT INTO encounter (patient_id, doctor_id, branch_id, chief_complaint, started_at)
VALUES (1,1,1,'Fever and headache for 3 days','2026-11-14 09:05+01');
INSERT INTO diagnosis (encounter_id, icd10_code, description, is_primary) VALUES (1,'B54','Malaria, unspecified',TRUE);
INSERT INTO prescription (encounter_id) VALUES (1);
INSERT INTO prescription_item (prescription_id, drug_id, dose, frequency, duration_days, quantity) VALUES
 (1,1,'1 strip','once daily',6,6),        -- 6 strips of Coartem (stock is counted in strips)
 (1,2,'2 tablets','8-hourly',3,10);       -- 10 Paracetamol tablets
INSERT INTO invoice (invoice_no, patient_id, branch_id, encounter_id, issued_at)
VALUES ('INV-IKJ-000001',1,1,1,'2026-11-14 09:30+01');
INSERT INTO invoice_item VALUES (1,1,'consultation','Doctor consultation',1,10000);

-- Today's payments so far at Ikeja (used by the reporting scenarios)
INSERT INTO payment (invoice_id, amount, method, reference, received_by, paid_at) VALUES
 (1, 10000, 'cash', 'RCPT-0001', 7, '2026-11-14 09:40+01');
