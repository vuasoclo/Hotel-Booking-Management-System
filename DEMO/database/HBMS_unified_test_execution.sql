-- =============================================================
-- HBMS Test Execution Script (Phase 5)
-- Prerequisite: Run src/HBMS_full_deployment.sql first
-- Scope:
--   - Seed data
--   - Execute test scenarios TC-01..TC-14, TC-20..TC-25, TC-30..TC-35
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
VALUES ('Dana Marina', '47 Vo Van Kiet', '0909000000');

INSERT INTO customers (full_name, phone_number, email, identity_card, date_of_birth)
VALUES ('Nguyen Van A', '0868250301', 'guest.a@hbms.local', 'ID-0001', DATE '1995-01-01');

INSERT INTO staff (hotel_id, name, role)
SELECT id, 'Tran Thi Le', 'Receptionist'
FROM hotels
WHERE name = 'Dana Marina';

INSERT INTO surcharge_policies (policy_type, description, multiplier, start_time, end_time, is_active)
VALUES
('EarlyCheckIn', 'Early check-in from 06:00 to 14:00', 0.50, TIME '06:00', TIME '14:00', TRUE),
('LateCheckOut', 'Late check-out from 12:00 to 18:00', 0.30, TIME '12:00', TIME '18:00', TRUE);

INSERT INTO room_types (hotel_id, type_name, base_price, max_capacity)
SELECT id, 'Deluxe', 100.00, 2
FROM hotels
WHERE name = 'Dana Marina';

INSERT INTO rooms (hotel_id, room_number, room_type_id)
SELECT h.id, x.room_number, rt.id
FROM hotels h
JOIN room_types rt ON rt.hotel_id = h.id AND rt.type_name = 'Deluxe'
JOIN (VALUES ('D101'), ('D102'), ('D103')) AS x(room_number) ON TRUE
WHERE h.name = 'Dana Marina';

INSERT INTO room_type_inventory (room_type_id, date, total_inventory, total_reserved)
SELECT rt.id, d::date, 3, 0
FROM room_types rt
CROSS JOIN generate_series(DATE '2026-05-01', DATE '2026-05-05', INTERVAL '1 day') AS d
WHERE rt.type_name = 'Deluxe';

INSERT INTO services (hotel_id, name, unit_price, category)
SELECT h.id, 'Minibar', 20.00, 'F&B'
FROM hotels h
WHERE h.name = 'Dana Marina';

-- =============================================================
-- =============================================================
-- Seed Data (From Additions)
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

-- Test Execution
-- =============================================================

DO $$
DECLARE
    v_hotel_id INT;
    v_customer_id INT;
    v_staff_id INT;
    v_room_type_id INT;
    v_room_d101_id INT;
    v_room_d102_id INT;
    v_room_d103_id INT;
    v_minibar_id INT;

    v_booking_tc01 INT;
    v_booking_tc05 INT;
    v_booking_tc07_a INT;
    v_booking_tc07_b INT;
    v_booking_tc10 INT;
    v_booking_tc13 INT;
    v_booking_tc20 INT;
    v_booking_tc21 INT;
    v_booking_tc22 INT;
    v_booking_tc33 INT;
    v_booking_tc35 INT;
    v_temp_booking INT;

    v_reserved INT;
    v_price_old DECIMAL(10, 2);
    v_price_new DECIMAL(10, 2);
    v_old_updated_at TIMESTAMP;
    v_new_updated_at TIMESTAMP;
    v_nights INT;

    v_room_cost DECIMAL(10, 2);
    v_surcharge_cost DECIMAL(10, 2);
    v_service_cost DECIMAL(10, 2);
    v_expected_total DECIMAL(10, 2);
    v_actual_total DECIMAL(10, 2);

    v_before_total DECIMAL(10, 2);
    v_after_total DECIMAL(10, 2);
    v_balance DECIMAL(10, 2);
    v_rate NUMERIC;
    v_rev_room DECIMAL(10, 2);
    v_rev_surcharge DECIMAL(10, 2);
    v_rev_service DECIMAL(10, 2);
    v_guest_name VARCHAR(100);
    v_cnt INT;

    -- Additions specific variables
    v_rt_deluxe INT;
    v_rt_suite INT;
    v_room_d101 INT;
    v_room_d102 INT;
    v_room_s201 INT;
    v_booking_main INT;
    v_booking_second INT;
    v_total DECIMAL(10, 2);
    v_remaining DECIMAL(10, 2);

BEGIN
    SELECT id INTO v_hotel_id FROM hotels WHERE name = 'Dana Marina';
    SELECT id INTO v_customer_id FROM customers WHERE phone_number = '0868250301';
    SELECT id INTO v_staff_id FROM staff WHERE name = 'Tran Thi Le';
    SELECT id INTO v_room_type_id FROM room_types WHERE type_name = 'Deluxe' AND hotel_id = v_hotel_id;
    SELECT id INTO v_room_d101_id FROM rooms WHERE room_number = 'D101' AND hotel_id = v_hotel_id;
    SELECT id INTO v_room_d102_id FROM rooms WHERE room_number = 'D102' AND hotel_id = v_hotel_id;
    SELECT id INTO v_room_d103_id FROM rooms WHERE room_number = 'D103' AND hotel_id = v_hotel_id;
    SELECT id INTO v_minibar_id FROM services WHERE name = 'Minibar' AND hotel_id = v_hotel_id;

    -- TC-01: Tạo Reservation hợp lệ
    BEGIN
        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-01 14:00', TIMESTAMP '2026-05-02 12:00', '11111111-1111-1111-1111-111111111001');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        SELECT id INTO v_booking_tc01
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111111001';

        SELECT total_reserved INTO v_reserved
        FROM room_type_inventory
        WHERE room_type_id = v_room_type_id
          AND date = DATE '2026-05-01';

        IF v_booking_tc01 IS NULL OR v_reserved <> 1 THEN
            RAISE EXCEPTION 'TC-01 assertion failed';
        END IF;

        RAISE NOTICE 'TC-01 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-01 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-02: Chống overbooking
    BEGIN
        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-03 14:00', TIMESTAMP '2026-05-04 12:00', '11111111-1111-1111-1111-111111111201');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);
        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-03 14:00', TIMESTAMP '2026-05-04 12:00', '11111111-1111-1111-1111-111111111202');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);
        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-03 14:00', TIMESTAMP '2026-05-04 12:00', '11111111-1111-1111-1111-111111111203');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        -- Lệnh thứ 4 phải lỗi overbooking
        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-03 14:00', TIMESTAMP '2026-05-04 12:00', '11111111-1111-1111-1111-111111111204');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        RAISE NOTICE 'TC-02 failed: expected OVERBOOKING but not raised';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = 'P0001' THEN
            RAISE NOTICE 'TC-02 passed: %', SQLERRM;
        ELSE
            RAISE NOTICE 'TC-02 failed with unexpected error: % (state=%)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- TC-03: Snapshot giá
    BEGIN
        UPDATE room_types SET base_price = 120.00 WHERE id = v_room_type_id;

        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-02 14:00', TIMESTAMP '2026-05-03 12:00', '11111111-1111-1111-1111-111111111301');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        SELECT bd.agreed_price INTO v_price_old
        FROM booking_details bd
        JOIN bookings b ON b.id = bd.booking_id
        WHERE b.idempotency_key = '11111111-1111-1111-1111-111111111001';

        SELECT bd.agreed_price INTO v_price_new
        FROM booking_details bd
        JOIN bookings b ON b.id = bd.booking_id
        WHERE b.idempotency_key = '11111111-1111-1111-1111-111111111301';

        IF v_price_old <> 100.00 OR v_price_new <> 120.00 THEN
            RAISE EXCEPTION 'TC-03 assertion failed: old=%, new=%', v_price_old, v_price_new;
        END IF;

        RAISE NOTICE 'TC-03 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-03 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-04: Check-in gán phòng
    BEGIN
        SELECT id INTO v_booking_tc01
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111111001';

        CALL check_in_booking(v_booking_tc01, v_room_d101_id, v_staff_id);

        IF (SELECT status FROM bookings WHERE id = v_booking_tc01) <> 'Checked-in' THEN
            RAISE EXCEPTION 'TC-04 assertion failed: booking not Checked-in';
        END IF;

        IF (SELECT status FROM rooms WHERE id = v_room_d101_id) <> 'Occupied' THEN
            RAISE EXCEPTION 'TC-04 assertion failed: room not Occupied';
        END IF;

        RAISE NOTICE 'TC-04 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-04 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-05: Chặn duplicate assignment bằng EXCLUDE
    v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-01 14:00', TIMESTAMP '2026-05-02 12:00', '11111111-1111-1111-1111-111111111501');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

    SELECT id INTO v_booking_tc05
    FROM bookings
    WHERE idempotency_key = '11111111-1111-1111-1111-111111111501';

    BEGIN
        INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
        SELECT v_booking_tc05, v_room_d101_id, b.check_in, b.check_out, FALSE
        FROM bookings b
        WHERE b.id = v_booking_tc05;

        RAISE NOTICE 'TC-05 failed: expected exclusion violation but not raised';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23P01' THEN
            RAISE NOTICE 'TC-05 passed: %', SQLERRM;
        ELSE
            RAISE NOTICE 'TC-05 failed with unexpected error: % (state=%)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- TC-06: Soft cancel set cancelled_at
    BEGIN
        UPDATE bookings
        SET status = 'Cancelled'
        WHERE id = v_booking_tc05;

        IF (SELECT cancelled_at FROM bookings WHERE id = v_booking_tc05) IS NULL THEN
            RAISE EXCEPTION 'TC-06 assertion failed: cancelled_at is NULL';
        END IF;

        RAISE NOTICE 'TC-06 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-06 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-07: EXCLUDE cho phép khi assignment cũ đã cancel
    BEGIN
        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-04 14:00', TIMESTAMP '2026-05-05 12:00', '11111111-1111-1111-1111-111111111701');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);
        SELECT id INTO v_booking_tc07_a
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111111701';

        CALL check_in_booking(v_booking_tc07_a, v_room_d103_id, v_staff_id);

        UPDATE bookings SET status = 'Cancelled' WHERE id = v_booking_tc07_a;

        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-04 14:00', TIMESTAMP '2026-05-05 12:00', '11111111-1111-1111-1111-111111111702');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);
        SELECT id INTO v_booking_tc07_b
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111111702';

        INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
        SELECT v_booking_tc07_b, v_room_d103_id, b.check_in, b.check_out, FALSE
        FROM bookings b
        WHERE b.id = v_booking_tc07_b;

        RAISE NOTICE 'TC-07 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-07 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-08: Duplicate idempotency
    BEGIN
        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-02 14:00', TIMESTAMP '2026-05-03 12:00', '11111111-1111-1111-1111-111111111801');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-02 14:00', TIMESTAMP '2026-05-03 12:00', '11111111-1111-1111-1111-111111111801');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        RAISE NOTICE 'TC-08 failed: expected DUPLICATE idempotency error';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = 'P0002' THEN
            RAISE NOTICE 'TC-08 passed: %', SQLERRM;
        ELSE
            RAISE NOTICE 'TC-08 failed with unexpected error: % (state=%)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- TC-09: FK RESTRICT room_types
    BEGIN
        DELETE FROM room_types WHERE id = v_room_type_id;
        RAISE NOTICE 'TC-09 failed: expected FK RESTRICT error';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23503' THEN
            RAISE NOTICE 'TC-09 passed: %', SQLERRM;
        ELSE
            RAISE NOTICE 'TC-09 failed with unexpected error: % (state=%)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- TC-10: Delete booking parent => cascade children
    BEGIN
        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-05 14:00', TIMESTAMP '2026-05-06 12:00', '11111111-1111-1111-1111-111111112001');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);
        SELECT id INTO v_booking_tc10
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111112001';

        INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
        SELECT v_booking_tc10, v_room_d102_id, b.check_in, b.check_out, FALSE
        FROM bookings b
        WHERE b.id = v_booking_tc10;

        DELETE FROM bookings WHERE id = v_booking_tc10;

        IF EXISTS (SELECT 1 FROM booking_details WHERE booking_id = v_booking_tc10)
           OR EXISTS (SELECT 1 FROM room_assignments WHERE booking_id = v_booking_tc10) THEN
            RAISE EXCEPTION 'TC-10 assertion failed: cascade did not clean child rows';
        END IF;

        RAISE NOTICE 'TC-10 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-10 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-11: Audit trigger updated_at
    BEGIN
        SELECT updated_at INTO v_old_updated_at FROM rooms WHERE id = v_room_d102_id;
        UPDATE rooms SET status = 'Maintenance' WHERE id = v_room_d102_id;
        SELECT updated_at INTO v_new_updated_at FROM rooms WHERE id = v_room_d102_id;

        IF v_new_updated_at <= v_old_updated_at THEN
            RAISE EXCEPTION 'TC-11 assertion failed: updated_at did not change';
        END IF;

        UPDATE rooms SET status = 'Available' WHERE id = v_room_d102_id;

        RAISE NOTICE 'TC-11 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-11 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-12: Cancel TC-01 releases inventory and set cancelled_at
    BEGIN
        SELECT id INTO v_booking_tc01
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111111001';

        UPDATE bookings
        SET status = 'Cancelled'
        WHERE id = v_booking_tc01;

        SELECT total_reserved INTO v_reserved
        FROM room_type_inventory
        WHERE room_type_id = v_room_type_id
          AND date = DATE '2026-05-01';

        IF v_reserved <> 0 THEN
            RAISE EXCEPTION 'TC-12 assertion failed: total_reserved expected 0, got %', v_reserved;
        END IF;

        IF (SELECT cancelled_at FROM bookings WHERE id = v_booking_tc01) IS NULL THEN
            RAISE EXCEPTION 'TC-12 assertion failed: cancelled_at is NULL';
        END IF;

        RAISE NOTICE 'TC-12 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-12 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-13: apply_time_surcharges tạo EarlyCheckIn
    BEGIN
        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-02 07:00', TIMESTAMP '2026-05-03 12:00', '11111111-1111-1111-1111-111111111313');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        SELECT id INTO v_booking_tc13
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111111313';

        SELECT COUNT(*) INTO v_cnt
        FROM booking_surcharges
        WHERE booking_id = v_booking_tc13
          AND surcharge_type = 'EarlyCheckIn';

        IF v_cnt <= 0 THEN
            RAISE EXCEPTION 'TC-13 assertion failed: no EarlyCheckIn surcharge inserted';
        END IF;

        RAISE NOTICE 'TC-13 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-13 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-14: CHECK tuổi khách hàng
    BEGIN
        INSERT INTO customers (full_name, phone_number, email, identity_card, date_of_birth)
        VALUES ('Under Age Guest', '0900000014', 'under14@hbms.local', 'ID-0014', DATE '2015-01-01');

        RAISE NOTICE 'TC-14 failed: expected age CHECK violation';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '23514' THEN
            RAISE NOTICE 'TC-14 passed: %', SQLERRM;
        ELSE
            RAISE NOTICE 'TC-14 failed with unexpected error: % (state=%)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- TC-20: check-in thành công
    BEGIN
        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-04 14:00', TIMESTAMP '2026-05-05 12:00', '11111111-1111-1111-1111-111111112020');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        SELECT id INTO v_booking_tc20
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111112020';

        UPDATE rooms SET status = 'Available' WHERE id = v_room_d102_id;

        CALL check_in_booking(v_booking_tc20, v_room_d102_id, v_staff_id);

        IF (SELECT status FROM bookings WHERE id = v_booking_tc20) <> 'Checked-in'
           OR (SELECT status FROM rooms WHERE id = v_room_d102_id) <> 'Occupied' THEN
            RAISE EXCEPTION 'TC-20 assertion failed';
        END IF;

        RAISE NOTICE 'TC-20 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-20 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-21: check-in phòng Dirty bị chặn
    BEGIN
        UPDATE rooms SET status = 'Dirty' WHERE id = v_room_d103_id;

        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-05-04 14:00', TIMESTAMP '2026-05-05 12:00', '11111111-1111-1111-1111-111111112021');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        SELECT id INTO v_booking_tc21
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111112021';

        CALL check_in_booking(v_booking_tc21, v_room_d103_id, v_staff_id);

        RAISE NOTICE 'TC-21 failed: expected P0010 room not available';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = 'P0010' THEN
            RAISE NOTICE 'TC-21 passed: %', SQLERRM;
        ELSE
            RAISE NOTICE 'TC-21 failed with unexpected error: % (state=%)', SQLERRM, SQLSTATE;
        END IF;
    END;
    UPDATE rooms SET status = 'Available' WHERE id = v_room_d103_id;

    -- TC-22: check-in booking Pending bị chặn
    BEGIN
        INSERT INTO bookings (hotel_id, customer_id, status, idempotency_key, check_in, check_out)
        VALUES (
            v_hotel_id, v_customer_id, 'Pending',
            '11111111-1111-1111-1111-111111112022',
            TIMESTAMP '2026-05-04 14:00', TIMESTAMP '2026-05-05 12:00'
        )
        RETURNING id INTO v_booking_tc22;

        INSERT INTO booking_details (booking_id, room_type_id, agreed_price, quantity)
        VALUES (v_booking_tc22, v_room_type_id, 0, 1);

        CALL check_in_booking(v_booking_tc22, v_room_d103_id, v_staff_id);

        RAISE NOTICE 'TC-22 failed: expected P0011 booking state error';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = 'P0011' THEN
            RAISE NOTICE 'TC-22 passed: %', SQLERRM;
        ELSE
            RAISE NOTICE 'TC-22 failed with unexpected error: % (state=%)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- TC-23: check-out tính tiền đúng
    BEGIN
        INSERT INTO booking_surcharges (booking_id, surcharge_type, amount, description)
        VALUES (v_booking_tc20, 'Holiday', 25.00, 'Holiday surcharge test');

        INSERT INTO service_usage (booking_id, service_id, quantity, staff_id)
        VALUES (v_booking_tc20, v_minibar_id, 2, v_staff_id);

        SELECT GREATEST((check_out::DATE - check_in::DATE), 1)
        INTO v_nights
        FROM bookings
        WHERE id = v_booking_tc20;

        SELECT COALESCE(SUM(agreed_price * quantity * v_nights), 0)
        INTO v_room_cost
        FROM booking_details
        WHERE booking_id = v_booking_tc20;

        SELECT COALESCE(SUM(amount), 0)
        INTO v_surcharge_cost
        FROM booking_surcharges
        WHERE booking_id = v_booking_tc20;

        SELECT COALESCE(SUM(su.quantity * s.unit_price), 0)
        INTO v_service_cost
        FROM service_usage su
        JOIN services s ON s.id = su.service_id
        WHERE su.booking_id = v_booking_tc20;

        v_expected_total := v_room_cost + v_surcharge_cost + v_service_cost;

        CALL check_out_booking(v_booking_tc20, v_staff_id);

        SELECT total_amount INTO v_actual_total
        FROM bookings
        WHERE id = v_booking_tc20;

        IF v_actual_total <> v_expected_total THEN
            RAISE EXCEPTION 'TC-23 assertion failed: expected total %, got %', v_expected_total, v_actual_total;
        END IF;

        IF (SELECT status FROM bookings WHERE id = v_booking_tc20) <> 'Completed'
           OR (SELECT status FROM rooms WHERE id = v_room_d102_id) <> 'Dirty' THEN
            RAISE EXCEPTION 'TC-23 assertion failed: status transition incorrect';
        END IF;

        RAISE NOTICE 'TC-23 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-23 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-24: housekeeping đổi Dirty -> Available
    BEGIN
        CALL housekeeping_complete(v_room_d102_id, v_staff_id);

        IF (SELECT status FROM rooms WHERE id = v_room_d102_id) <> 'Available' THEN
            RAISE EXCEPTION 'TC-24 assertion failed: room not Available';
        END IF;

        RAISE NOTICE 'TC-24 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-24 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-25: chặn housekeeping trên phòng không Dirty
    BEGIN
        CALL housekeeping_complete(v_room_d102_id, v_staff_id);
        RAISE NOTICE 'TC-25 failed: expected P0013';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = 'P0013' THEN
            RAISE NOTICE 'TC-25 passed: %', SQLERRM;
        ELSE
            RAISE NOTICE 'TC-25 failed with unexpected error: % (state=%)', SQLERRM, SQLSTATE;
        END IF;
    END;

    -- TC-30: v_daily_occupancy đúng tỷ lệ
    BEGIN
        INSERT INTO room_type_inventory (room_type_id, date, total_inventory, total_reserved)
        VALUES (v_room_type_id, DATE '2026-06-01', 4, 0)
        ON CONFLICT (room_type_id, date)
        DO UPDATE SET total_inventory = EXCLUDED.total_inventory, total_reserved = EXCLUDED.total_reserved;

        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-06-01 14:00', TIMESTAMP '2026-06-02 12:00', '11111111-1111-1111-1111-111111113030');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        SELECT occupancy_rate INTO v_rate
        FROM v_daily_occupancy
        WHERE room_type_id = v_room_type_id
          AND date = DATE '2026-06-01';

        IF v_rate IS NULL OR ABS(v_rate - 25.00) > 0.01 THEN
            RAISE EXCEPTION 'TC-30 assertion failed: expected 25, got %', v_rate;
        END IF;

        RAISE NOTICE 'TC-30 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-30 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-31: occupancy_rate = 0 khi inventory = 0
    BEGIN
        INSERT INTO room_type_inventory (room_type_id, date, total_inventory, total_reserved)
        VALUES (v_room_type_id, DATE '2026-06-02', 0, 0)
        ON CONFLICT (room_type_id, date)
        DO UPDATE SET total_inventory = EXCLUDED.total_inventory, total_reserved = EXCLUDED.total_reserved;

        SELECT occupancy_rate INTO v_rate
        FROM v_daily_occupancy
        WHERE room_type_id = v_room_type_id
          AND date = DATE '2026-06-02';

        IF COALESCE(v_rate, -1) <> 0 THEN
            RAISE EXCEPTION 'TC-31 assertion failed: expected 0, got %', v_rate;
        END IF;

        RAISE NOTICE 'TC-31 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-31 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-32: v_monthly_revenue đủ 3 thành phần
    BEGIN
        SELECT total_room_cost, total_surcharges, total_services
        INTO v_rev_room, v_rev_surcharge, v_rev_service
        FROM v_monthly_revenue
        WHERE hotel_id = v_hotel_id
          AND report_month = DATE_TRUNC('month', TIMESTAMP '2026-05-01')
        LIMIT 1;

        IF COALESCE(v_rev_room, 0) <= 0
           OR COALESCE(v_rev_surcharge, 0) <= 0
           OR COALESCE(v_rev_service, 0) <= 0 THEN
            RAISE EXCEPTION 'TC-32 assertion failed: breakdown not complete (room=%, surcharge=%, service=%)',
                v_rev_room, v_rev_surcharge, v_rev_service;
        END IF;

        RAISE NOTICE 'TC-32 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-32 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-33: trigger sync_total_amount
    BEGIN
        INSERT INTO room_type_inventory (room_type_id, date, total_inventory, total_reserved)
        VALUES (v_room_type_id, DATE '2026-06-03', 3, 0)
        ON CONFLICT (room_type_id, date)
        DO UPDATE SET total_inventory = EXCLUDED.total_inventory, total_reserved = EXCLUDED.total_reserved;

        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-06-03 14:00', TIMESTAMP '2026-06-04 12:00', '11111111-1111-1111-1111-111111113033');
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        SELECT id INTO v_booking_tc33
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111113033';

        SELECT total_amount INTO v_before_total
        FROM bookings
        WHERE id = v_booking_tc33;

        INSERT INTO service_usage (booking_id, service_id, quantity, staff_id)
        VALUES (v_booking_tc33, v_minibar_id, 1, v_staff_id);

        SELECT total_amount INTO v_after_total
        FROM bookings
        WHERE id = v_booking_tc33;

        IF v_after_total <= v_before_total THEN
            RAISE EXCEPTION 'TC-33 assertion failed: total_amount did not increase (% -> %)', v_before_total, v_after_total;
        END IF;

        RAISE NOTICE 'TC-33 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-33 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-34: balance = total_amount - amount_paid
    BEGIN
        UPDATE bookings
        SET amount_paid = GREATEST(total_amount - 50, 0)
        WHERE id = v_booking_tc33;

        SELECT balance INTO v_balance
        FROM v_booking_summary
        WHERE booking_id = v_booking_tc33;

        IF v_balance <> (
            SELECT total_amount - amount_paid
            FROM bookings
            WHERE id = v_booking_tc33
        ) THEN
            RAISE EXCEPTION 'TC-34 assertion failed: balance mismatch';
        END IF;

        RAISE NOTICE 'TC-34 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-34 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;

    -- TC-35: v_room_status_now hiển thị khách đang ở
    BEGIN
        UPDATE rooms SET status = 'Available' WHERE id = v_room_d103_id;

        INSERT INTO room_type_inventory (room_type_id, date, total_inventory, total_reserved)
        VALUES (v_room_type_id, CURRENT_DATE, 3, 0)
        ON CONFLICT (room_type_id, date)
        DO UPDATE SET total_inventory = EXCLUDED.total_inventory,
                      total_reserved = LEAST(room_type_inventory.total_reserved, EXCLUDED.total_inventory);

        v_temp_booking := begin_booking(v_hotel_id, v_customer_id, (NOW() - INTERVAL '1 hour')::TIMESTAMP, (NOW() + INTERVAL '1 day')::TIMESTAMP, '11111111-1111-1111-1111-111111113035'::UUID);
        CALL add_room_detail_to_booking(v_temp_booking, v_room_type_id, 1, FALSE);
        CALL finalize_booking(v_temp_booking);

        SELECT id INTO v_booking_tc35
        FROM bookings
        WHERE idempotency_key = '11111111-1111-1111-1111-111111113035';

        CALL check_in_booking(v_booking_tc35, v_room_d103_id, v_staff_id);

        SELECT current_guest INTO v_guest_name
        FROM v_room_status_now
        WHERE room_id = v_room_d103_id;

        IF v_guest_name IS NULL THEN
            RAISE EXCEPTION 'TC-35 assertion failed: current_guest is NULL';
        END IF;

        RAISE NOTICE 'TC-35 passed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'TC-35 failed: % (state=%)', SQLERRM, SQLSTATE;
    END;


    -- =============================================================
    -- Additions E2E Verification
    -- =============================================================
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
    CALL pre_assign_room(v_booking_main, NULL, v_room_d101, v_staff_id);
    CALL pre_assign_room(v_booking_main, NULL, v_room_s201, v_staff_id);

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
    CALL pre_assign_room(v_booking_second, NULL, v_room_d102, v_staff_id);

    -- 8) tetrisroom_defrag()
    CALL tetrisroom_defrag(v_hotel_id, v_staff_id);

    SELECT COUNT(*) INTO v_cnt
    FROM room_assignments ra
    JOIN bookings b ON b.id = ra.booking_id
    WHERE b.status = 'Active'
      AND ra.is_cancelled = FALSE
      AND b.hotel_id = v_hotel_id;

    IF v_cnt <> 3 THEN
        RAISE EXCEPTION 'E2E-08 failed: expected 3 active assignments after defrag, got %', v_cnt;
    END IF;

    SELECT COUNT(*) INTO v_cnt
    FROM room_assignments ra
    JOIN bookings b ON b.id = ra.booking_id
    WHERE ra.is_cancelled = TRUE
      AND b.hotel_id = v_hotel_id;

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
    RAISE NOTICE 'All test blocks executed.';
END
$$;
