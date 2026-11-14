-- =====================================================================
-- MIT 8103 - Portfolio 3: setup (run once, after Portfolio 1 schema.sql)
-- Creates two helper functions used by the transaction scripts.
-- =====================================================================
SET search_path TO hospital;

-- log(msg): prints a NOTICE immediately, even inside an open transaction.
-- The concurrency runner timestamps these lines to build a timeline.
CREATE OR REPLACE FUNCTION log(msg text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE '%', msg;
END $$;

-- dispense_item(): the pharmacy's "dispense one prescribed drug" operation.
-- It runs inside the CALLER's transaction, so several calls can be grouped
-- into one atomic unit, and any exception aborts the whole transaction.
CREATE OR REPLACE FUNCTION dispense_item(p_prescription_id bigint, p_drug_id int, p_branch_id smallint)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_need      int;
    v_invoice   bigint;
    v_price     numeric;
    v_name      text;
BEGIN
    -- lock the prescription line so two pharmacists cannot dispense it twice
    SELECT pi.quantity - pi.quantity_dispensed INTO v_need
    FROM prescription_item pi
    WHERE pi.prescription_id = p_prescription_id AND pi.drug_id = p_drug_id
    FOR UPDATE;

    IF v_need IS NULL THEN
        RAISE EXCEPTION 'Drug % is not on prescription %', p_drug_id, p_prescription_id;
    ELSIF v_need = 0 THEN
        RAISE EXCEPTION 'Drug % on prescription % is already dispensed', p_drug_id, p_prescription_id;
    END IF;

    -- atomic, conditional decrement: never reads-then-writes in the application
    UPDATE branch_drug_stock
       SET quantity = quantity - v_need
     WHERE branch_id = p_branch_id AND drug_id = p_drug_id AND quantity >= v_need;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient stock of drug % at branch % (need %)', p_drug_id, p_branch_id, v_need;
    END IF;

    UPDATE prescription_item
       SET quantity_dispensed = quantity
     WHERE prescription_id = p_prescription_id AND drug_id = p_drug_id;

    -- bill the drug on the encounter's invoice, at today's price
    SELECT i.invoice_id INTO v_invoice
    FROM prescription p JOIN invoice i ON i.encounter_id = p.encounter_id
    WHERE p.prescription_id = p_prescription_id
    ORDER BY i.invoice_id LIMIT 1;

    SELECT unit_price, generic_name || ' ' || strength INTO v_price, v_name FROM drug WHERE drug_id = p_drug_id;

    INSERT INTO invoice_item (invoice_id, line_no, item_type, description, quantity, unit_price)
    SELECT v_invoice, COALESCE(max(line_no), 0) + 1, 'drug', v_name, v_need, v_price
    FROM invoice_item WHERE invoice_id = v_invoice;

    -- mark the prescription fully dispensed once every line is done
    UPDATE prescription SET status = 'dispensed'
    WHERE prescription_id = p_prescription_id
      AND NOT EXISTS (SELECT 1 FROM prescription_item
                      WHERE prescription_id = p_prescription_id AND quantity_dispensed < quantity);
END $$;
