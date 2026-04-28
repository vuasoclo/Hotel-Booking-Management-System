-- =============================================================
-- HBMS Additions Quick E2E Verification
-- Prerequisite: Run DEMO/HBMS_full_deployment.sql first
-- Scope:
--   - Seed minimal data
--   - Call each new procedure and verify outcomes
-- =============================================================

SET client_min_messages TO NOTICE;

BEGIN;
TRUNCATE TABLE
    invoices,
    service_usage,
    services,
    room_assignments,
    booking_surcharges,
    booking_details,
    bookings,
    room_type_inventory,
    rooms,
    room_types,
    surcharge_policies,
    staff,
    customers,
    hotels
RESTART IDENTITY CASCADE;
COMMIT;

-- =============================================================
-- Seed Data
-- =============================================================

INSERT INTO hotels (name, address, hotline)
VALUES ('E2E Marina', '99 Test Street', '0909888777');

INSERT INTO customers (full_name, phone_number, email, identity_card, date_of_birth)
VALUES ('E2E Guest', '0909000100', 'guest.e2e@hbms.local', 'E2E-ID-0001', DATE '1990-01-01');

INSERT INTO staff (hotel_id, name, role)
SELECT id, 'E2E Reception', 'Receptionist'
FROM hotels
WHERE name = 'E2E Marina';

INSERT INTO surcharge_policies (policy_type, description, multiplier, start_time, end_time, is_active)
VALUES
('EarlyCheckIn', 'Early check-in policy', 0.50, TIME '06:00', TIME '14:00', TRUE),
('LateCheckOut', 'Late check-out policy', 0.30, TIME '12:00', TIME '18:00', TRUE);

INSERT INTO room_types (hotel_id, type_name, base_price, max_capacity)
SELECT id, x.type_name, x.base_price, x.max_capacity
FROM hotels h
JOIN (VALUES
    ('Deluxe', 120.00::DECIMAL(10, 2), 2),
    ('Suite', 220.00::DECIMAL(10, 2), 3)
) AS x(type_name, base_price, max_capacity) ON TRUE
WHERE h.name = 'E2E Marina';

INSERT INTO rooms (hotel_id, room_number, room_type_id)
SELECT h.id, x.room_number, rt.id
FROM hotels h
JOIN room_types rt ON rt.hotel_id = h.id
JOIN (VALUES
    ('D101', 'Deluxe'),
    ('D102', 'Deluxe'),
    ('S201', 'Suite')
) AS x(room_number, type_name)
    ON x.type_name = rt.type_name
WHERE h.name = 'E2E Marina';

INSERT INTO room_type_inventory (room_type_id, date, total_inventory, total_reserved)
SELECT
    rt.id,
    d::DATE,
    CASE WHEN rt.type_name = 'Deluxe' THEN 2 ELSE 1 END AS total_inventory,
    0 AS total_reserved
FROM room_types rt
CROSS JOIN generate_series(DATE '2026-07-10', DATE '2026-07-13', INTERVAL '1 day') d
WHERE rt.hotel_id = (SELECT id FROM hotels WHERE name = 'E2E Marina');

INSERT INTO services (hotel_id, name, unit_price, category)
SELECT id, 'Minibar', 25.00, 'F&B'
FROM hotels
WHERE name = 'E2E Marina';

-- =============================================================
-- Procedure E2E Verification
-- =============================================================

DO $$
DECLARE
    v_hotel_id INT;
    v_customer_id INT;
    v_staff_id INT;

    v_rt_deluxe INT;
    v_rt_suite INT;

    v_room_d101 INT;
    v_room_d102 INT;
    v_room_s201 INT;

    v_booking_main INT;
    v_booking_second INT;

    v_cnt INT;
    v_total DECIMAL(10, 2);
    v_balance DECIMAL(10, 2);
    v_remaining DECIMAL(10, 2);
BEGIN
    SELECT id INTO v_hotel_id FROM hotels WHERE name = 'E2E Marina';
    SELECT id INTO v_customer_id FROM customers WHERE phone_number = '0909000100';
    SELECT id INTO v_staff_id FROM staff WHERE name = 'E2E Reception';

    SELECT id INTO v_rt_deluxe FROM room_types WHERE hotel_id = v_hotel_id AND type_name = 'Deluxe';
    SELECT id INTO v_rt_suite FROM room_types WHERE hotel_id = v_hotel_id AND type_name = 'Suite';

    SELECT id INTO v_room_d101 FROM rooms WHERE hotel_id = v_hotel_id AND room_number = 'D101';
    SELECT id INTO v_room_d102 FROM rooms WHERE hotel_id = v_hotel_id AND room_number = 'D102';
    SELECT id INTO v_room_s201 FROM rooms WHERE hotel_id = v_hotel_id AND room_number = 'S201';

    -- 1) begin_booking()
    v_booking_main := begin_booking(
        v_hotel_id,
        v_customer_id,
        TIMESTAMP '2026-07-10 07:00',
        TIMESTAMP '2026-07-12 13:00',
        '22222222-2222-2222-2222-222222222201'
    );

    IF (SELECT status FROM bookings WHERE id = v_booking_main) <> 'Pending' THEN
        RAISE EXCEPTION 'E2E-01 failed: begin_booking did not create Pending booking';
    END IF;
    RAISE NOTICE 'E2E-01 passed: begin_booking()';

    -- 2) add_room_detail_to_booking() (2 room types)
    CALL add_room_detail_to_booking(v_booking_main, v_rt_deluxe, 1, FALSE);
    CALL add_room_detail_to_booking(v_booking_main, v_rt_suite, 1, TRUE);

    SELECT COUNT(*) INTO v_cnt
    FROM booking_details
    WHERE booking_id = v_booking_main;

    IF v_cnt <> 2 THEN
        RAISE EXCEPTION 'E2E-02 failed: expected 2 booking_details, got %', v_cnt;
    END IF;

    SELECT total_reserved INTO v_cnt
    FROM room_type_inventory
    WHERE room_type_id = v_rt_deluxe
      AND date = DATE '2026-07-10';

    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'E2E-02 failed: Deluxe inventory not reserved correctly';
    END IF;

    SELECT total_reserved INTO v_cnt
    FROM room_type_inventory
    WHERE room_type_id = v_rt_suite
      AND date = DATE '2026-07-10';

    IF v_cnt <> 1 THEN
        RAISE EXCEPTION 'E2E-02 failed: Suite inventory not reserved correctly';
    END IF;
    RAISE NOTICE 'E2E-02 passed: add_room_detail_to_booking()';

    -- 3) finalize_booking()
    CALL finalize_booking(v_booking_main);

    IF (SELECT status FROM bookings WHERE id = v_booking_main) <> 'Active' THEN
        RAISE EXCEPTION 'E2E-03 failed: finalize_booking did not set Active';
    END IF;

    SELECT COUNT(*) INTO v_cnt
    FROM booking_surcharges
    WHERE booking_id = v_booking_main
      AND surcharge_type IN ('EarlyCheckIn', 'LateCheckOut');

    IF v_cnt < 2 THEN
        RAISE EXCEPTION 'E2E-03 failed: expected time surcharges to be applied, got % rows', v_cnt;
    END IF;
    RAISE NOTICE 'E2E-03 passed: finalize_booking()';

    -- 4) pre_assign_room()
    CALL pre_assign_room(v_booking_main, v_room_d101, v_staff_id);
    CALL pre_assign_room(v_booking_main, v_room_s201, v_staff_id);

    SELECT COUNT(*) INTO v_cnt
    FROM room_assignments
    WHERE booking_id = v_booking_main
      AND is_cancelled = FALSE;

    IF v_cnt <> 2 THEN
        RAISE EXCEPTION 'E2E-04 failed: expected 2 active assignments, got %', v_cnt;
    END IF;

    SELECT COUNT(*) INTO v_cnt
    FROM v_calendar
    WHERE booking_id = v_booking_main;

    IF v_cnt <> 2 THEN
        RAISE EXCEPTION 'E2E-04 failed: v_calendar missing assignment rows';
    END IF;
    RAISE NOTICE 'E2E-04 passed: pre_assign_room() + v_calendar';

    -- 5) issue_invoice()
    CALL issue_invoice(v_booking_main, v_staff_id);

    IF NOT EXISTS (
        SELECT 1
        FROM invoices
        WHERE booking_id = v_booking_main
          AND status = 'Issued'
    ) THEN
        RAISE EXCEPTION 'E2E-05 failed: issue_invoice did not create/update invoice';
    END IF;
    RAISE NOTICE 'E2E-05 passed: issue_invoice()';

    -- 6) record_payment() partial + full
    CALL record_payment(v_booking_main, 50.00, v_staff_id);

    SELECT balance INTO v_remaining
    FROM invoices
    WHERE booking_id = v_booking_main;

    IF v_remaining <= 0 THEN
        RAISE EXCEPTION 'E2E-06 failed: expected positive remaining balance after partial payment';
    END IF;

    CALL record_payment(v_booking_main, v_remaining, v_staff_id);

    SELECT total_amount, balance
    INTO v_total, v_balance
    FROM invoices
    WHERE booking_id = v_booking_main;

    IF ABS(v_balance) > 0.01 THEN
        RAISE EXCEPTION 'E2E-06 failed: expected invoice balance ~ 0, got %', v_balance;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM invoices
        WHERE booking_id = v_booking_main
          AND status = 'Paid'
    ) THEN
        RAISE EXCEPTION 'E2E-06 failed: expected invoice status Paid';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM bookings
        WHERE id = v_booking_main
          AND ABS(total_amount - amount_paid) <= 0.01
    ) THEN
        RAISE EXCEPTION 'E2E-06 failed: booking amount_paid does not match total_amount';
    END IF;
    RAISE NOTICE 'E2E-06 passed: record_payment()';

    -- 7) Prepare another active booking for tetrisroom_defrag()
    v_booking_second := begin_booking(
        v_hotel_id,
        v_customer_id,
        TIMESTAMP '2026-07-11 08:00',
        TIMESTAMP '2026-07-13 11:00',
        '22222222-2222-2222-2222-222222222202'
    );

    CALL add_room_detail_to_booking(v_booking_second, v_rt_deluxe, 1, FALSE);
    CALL finalize_booking(v_booking_second);
    CALL pre_assign_room(v_booking_second, v_room_d102, v_staff_id);

    -- 8) tetrisroom_defrag()
    CALL tetrisroom_defrag(v_hotel_id, v_staff_id);

    SELECT COUNT(*) INTO v_cnt
    FROM room_assignments ra
    JOIN bookings b ON b.id = ra.booking_id
    WHERE b.status = 'Active'
      AND ra.is_cancelled = FALSE;

    IF v_cnt <> 3 THEN
        RAISE EXCEPTION 'E2E-08 failed: expected 3 active assignments after defrag, got %', v_cnt;
    END IF;

    SELECT COUNT(*) INTO v_cnt
    FROM room_assignments
    WHERE is_cancelled = TRUE;

    IF v_cnt = 0 THEN
        RAISE EXCEPTION 'E2E-08 failed: defrag did not cancel/repack old assignments';
    END IF;
    RAISE NOTICE 'E2E-08 passed: tetrisroom_defrag()';

    -- 9) Optional function check: search_services()
    SELECT COUNT(*) INTO v_cnt
    FROM search_services(v_hotel_id, 'Mini');

    IF v_cnt = 0 THEN
        RAISE EXCEPTION 'E2E-09 failed: search_services did not return expected rows';
    END IF;
    RAISE NOTICE 'E2E-09 passed: search_services()';

    RAISE NOTICE 'All additions E2E checks passed.';
END
$$;