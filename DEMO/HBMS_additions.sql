-- =============================================================
-- HBMS Additions — Gap-fill for Scenario 1 & 2
-- Depends on: HBMS_full_deployment.sql already applied
-- Database: PostgreSQL
-- =============================================================

BEGIN;

-- =============================================================
-- Gap 1: Multi-room-type reservation in a single booking
-- Rationale: create_reservation() creates one booking per call,
-- but a customer can book multiple room types simultaneously.
-- Solution: split into begin_booking → add_room_detail → finalize_booking
-- =============================================================

-- Step A: Open a Pending booking, return booking_id to caller
CREATE OR REPLACE FUNCTION begin_booking(
    p_hotel_id          INT,
    p_customer_id       INT,
    p_check_in          TIMESTAMP,
    p_check_out         TIMESTAMP,
    p_idempotency_key   UUID
)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_booking_id INT;
BEGIN
    IF p_check_out <= p_check_in THEN
        RAISE EXCEPTION 'INVALID_PERIOD: check_out phải lớn hơn check_in'
        USING ERRCODE = 'P0005';
    END IF;

    BEGIN
        INSERT INTO bookings (hotel_id, customer_id, idempotency_key, check_in, check_out, status)
        VALUES (p_hotel_id, p_customer_id, p_idempotency_key, p_check_in, p_check_out, 'Pending')
        RETURNING id INTO v_booking_id;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'DUPLICATE: idempotency_key % đã tồn tại', p_idempotency_key
            USING ERRCODE = 'P0002';
    END;

    RETURN v_booking_id;
END;
$$;

-- Step B: Attach one room-type line to an existing Pending booking (repeatable per room type)
CREATE OR REPLACE PROCEDURE add_room_detail_to_booking(
    p_booking_id            INT,
    p_room_type_id          INT,
    p_quantity              INT,
    p_is_breakfast_included BOOLEAN DEFAULT FALSE
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status    booking_status;
    v_check_in  DATE;
    v_check_out DATE;
    v_cur_date  DATE;
    v_available INT;
BEGIN
    SELECT status, check_in::DATE, check_out::DATE
    INTO v_status, v_check_in, v_check_out
    FROM bookings WHERE id = p_booking_id FOR UPDATE;

    IF v_status IS DISTINCT FROM 'Pending' THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Chỉ có thể thêm loại phòng khi booking ở trạng thái Pending (hiện tại: %)', v_status
        USING ERRCODE = 'P0019';
    END IF;

    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY: quantity phải > 0'
        USING ERRCODE = 'P0006';
    END IF;

    -- Inventory check + decrement across all nights
    v_cur_date := v_check_in;
    WHILE v_cur_date < v_check_out LOOP
        SELECT (total_inventory - total_reserved)
        INTO v_available
        FROM room_type_inventory
        WHERE room_type_id = p_room_type_id AND date = v_cur_date
        FOR UPDATE;

        IF v_available IS NULL THEN
            RAISE EXCEPTION 'SYSTEM: Chưa thiết lập inventory loại phòng % ngày %', p_room_type_id, v_cur_date
            USING ERRCODE = 'P0003';
        END IF;

        IF v_available < p_quantity THEN
            RAISE EXCEPTION 'OVERBOOKING: Không đủ phòng loại % ngày % (Còn: %)', p_room_type_id, v_cur_date, v_available
            USING ERRCODE = 'P0001';
        END IF;

        UPDATE room_type_inventory
        SET total_reserved = total_reserved + p_quantity
        WHERE room_type_id = p_room_type_id AND date = v_cur_date;

        v_cur_date := v_cur_date + 1;
    END LOOP;

    -- Insert booking_detail (agreed_price filled by trg_snapshot_price trigger)
    INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price, is_breakfast_included)
    VALUES (p_booking_id, p_room_type_id, p_quantity, 0, p_is_breakfast_included);
END;
$$;

-- Step C: Finalise — set booking Active + apply time surcharges
CREATE OR REPLACE PROCEDURE finalize_booking(
    p_booking_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status booking_status;
BEGIN
    SELECT status INTO v_status FROM bookings WHERE id = p_booking_id FOR UPDATE;

    IF v_status IS DISTINCT FROM 'Pending' THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Booking % không ở trạng thái Pending', p_booking_id
        USING ERRCODE = 'P0020';
    END IF;

    UPDATE bookings SET status = 'Active' WHERE id = p_booking_id;

    PERFORM apply_time_surcharges(p_booking_id);
END;
$$;

-- =============================================================
-- Gap 2: Invoice issuance & payment recording
-- Rationale: invoices table exists but no write procedures;
-- the payment view cannot function without them.
-- =============================================================

CREATE OR REPLACE PROCEDURE issue_invoice(
    p_booking_id INT,
    p_staff_id   INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status    booking_status;
    v_total     DECIMAL(10,2);
    v_paid      DECIMAL(10,2);
BEGIN
    SELECT status, total_amount, amount_paid
    INTO v_status, v_total, v_paid
    FROM bookings WHERE id = p_booking_id FOR UPDATE;

    IF v_status NOT IN ('Active', 'Checked-in', 'Completed') THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Không thể xuất hóa đơn cho booking trạng thái %', v_status
        USING ERRCODE = 'P0016';
    END IF;

    -- Upsert: re-issue updates amount when booking total changes (e.g. services added)
    INSERT INTO invoices (booking_id, issued_by, total_amount, amount_paid, balance, status)
    VALUES (p_booking_id, p_staff_id, v_total, v_paid, v_total - v_paid, 'Issued')
    ON CONFLICT (booking_id) DO UPDATE
        SET total_amount = EXCLUDED.total_amount,
            amount_paid  = EXCLUDED.amount_paid,
            balance      = EXCLUDED.balance,
            status       = 'Issued',
            issued_at    = NOW(),
            issued_by    = EXCLUDED.issued_by
    WHERE invoices.status <> 'Void';
END;
$$;

CREATE OR REPLACE PROCEDURE record_payment(
    p_booking_id INT,
    p_amount     DECIMAL(10,2),
    p_staff_id   INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status    booking_status;
    v_total     DECIMAL(10,2);
    v_paid      DECIMAL(10,2);
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_AMOUNT: Số tiền thanh toán phải > 0'
        USING ERRCODE = 'P0021';
    END IF;

    SELECT status, total_amount, amount_paid
    INTO v_status, v_total, v_paid
    FROM bookings WHERE id = p_booking_id FOR UPDATE;

    IF v_status NOT IN ('Active', 'Checked-in', 'Completed') THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Không thể thanh toán cho booking trạng thái %', v_status
        USING ERRCODE = 'P0017';
    END IF;

    IF v_paid + p_amount > v_total THEN
        RAISE EXCEPTION 'OVERPAYMENT: Vượt quá tổng hóa đơn. Còn lại cần thanh toán: %', (v_total - v_paid)
        USING ERRCODE = 'P0018';
    END IF;

    UPDATE bookings
    SET amount_paid = amount_paid + p_amount,
        updated_by  = p_staff_id
    WHERE id = p_booking_id;

    UPDATE invoices
    SET amount_paid = amount_paid + p_amount,
        balance     = balance - p_amount,
        status      = CASE
                        WHEN (amount_paid + p_amount) >= total_amount THEN 'Paid'
                        ELSE 'Issued'
                      END
    WHERE booking_id = p_booking_id
      AND status <> 'Void';
END;
$$;

-- =============================================================
-- Gap 3: Pre-assign a specific physical room to an Active booking
-- Rationale: create_reservation / finalize_booking reserve at
-- inventory level only (room_type). The Calendar renders boxes at
-- room level, so room_assignments must be populated before check-in.
-- TetrisRoom also needs this to be able to cancel + re-insert rows.
-- =============================================================

CREATE OR REPLACE PROCEDURE pre_assign_room(
    p_booking_id INT,
    p_room_id    INT,
    p_staff_id   INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status            booking_status;
    v_check_in          TIMESTAMP;
    v_check_out         TIMESTAMP;
    v_room_type_id      INT;
BEGIN
    SELECT status, check_in, check_out
    INTO v_status, v_check_in, v_check_out
    FROM bookings WHERE id = p_booking_id FOR UPDATE;

    IF v_status IS DISTINCT FROM 'Active' THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: pre_assign_room chỉ áp dụng cho booking Active (hiện tại: %)', v_status
        USING ERRCODE = 'P0014';
    END IF;

    -- Validate room type matches a booking_detail of this booking
    SELECT r.room_type_id INTO v_room_type_id
    FROM rooms r
    WHERE r.id = p_room_id;

    IF NOT EXISTS (
        SELECT 1 FROM booking_details
        WHERE booking_id = p_booking_id AND room_type_id = v_room_type_id
    ) THEN
        RAISE EXCEPTION 'ROOM_TYPE_MISMATCH: Phòng % không thuộc loại phòng nào trong booking %', p_room_id, p_booking_id
        USING ERRCODE = 'P0015';
    END IF;

    -- EXCLUDE constraint on room_assignments enforces no overlap automatically
    INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
    VALUES (p_booking_id, p_room_id, v_check_in, v_check_out, FALSE);
END;
$$;

-- =============================================================
-- Gap 4: Calendar view
-- Rationale: v_room_status_now only reflects rooms that are
-- currently Checked-in. The Calendar must display future Active
-- bookings that already have a pre-assigned room, as well as
-- in-house Checked-in rooms — across a date range.
-- =============================================================

CREATE OR REPLACE VIEW v_calendar AS
SELECT
    ra.id                   AS assignment_id,
    r.hotel_id,
    rt.id                   AS room_type_id,
    rt.type_name,
    r.id                    AS room_id,
    r.room_number,
    r.status                AS room_status,
    b.id                    AS booking_id,
    b.status                AS booking_status,
    c.full_name             AS customer_name,
    c.phone_number          AS customer_phone,
    ra.check_in,
    ra.check_out,
    b.total_amount,
    b.amount_paid,
    (b.total_amount - b.amount_paid)    AS balance,
    b.updated_at            AS booking_updated_at
FROM room_assignments ra
JOIN rooms          r   ON r.id   = ra.room_id
JOIN room_types     rt  ON rt.id  = r.room_type_id
JOIN bookings       b   ON b.id   = ra.booking_id
JOIN customers      c   ON c.id   = b.customer_id
WHERE ra.is_cancelled = FALSE
  AND b.status IN ('Active', 'Checked-in');

-- =============================================================
-- Gap 5: TetrisRoom defragmentation procedure
-- Rationale: The Calendar may accumulate scattered Active
-- pre-assignments over time. This procedure cancels all Active
-- (not yet Checked-in) room_assignments for a hotel, then
-- re-packs them greedily (earliest-check-in first, leftmost-room
-- first) to minimize fragmentation and free contiguous slots.
-- =============================================================

CREATE OR REPLACE PROCEDURE tetrisroom_defrag(
    p_hotel_id INT,
    p_staff_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    r_type    RECORD;
    r_booking RECORD;
    r_room    RECORD;
    v_inserted BOOLEAN;
BEGIN
    FOR r_type IN
        SELECT id AS room_type_id
        FROM room_types
        WHERE hotel_id = p_hotel_id
    LOOP
        -- 1. Cancel all Active pre-assignments for this room type
        UPDATE room_assignments ra
        SET is_cancelled = TRUE
        FROM bookings b, rooms r
        WHERE ra.booking_id = b.id
          AND ra.room_id    = r.id
          AND r.room_type_id = r_type.room_type_id
          AND b.status      = 'Active'
          AND ra.is_cancelled = FALSE;

        -- 2. Re-assign greedily: earliest check_in first, lowest room_number first
        FOR r_booking IN
            SELECT DISTINCT b.id AS booking_id, b.check_in, b.check_out
            FROM bookings b
            JOIN booking_details bd
              ON bd.booking_id   = b.id
             AND bd.room_type_id = r_type.room_type_id
            WHERE b.hotel_id = p_hotel_id
              AND b.status   = 'Active'
            ORDER BY b.check_in
        LOOP
            v_inserted := FALSE;

            FOR r_room IN
                SELECT r.id AS room_id
                FROM rooms r
                WHERE r.room_type_id = r_type.room_type_id
                  AND r.hotel_id     = p_hotel_id
                  AND NOT EXISTS (
                      SELECT 1 FROM room_assignments ra2
                      WHERE ra2.room_id       = r.id
                        AND ra2.is_cancelled  = FALSE
                        AND tsrange(ra2.check_in, ra2.check_out, '[)')
                         && tsrange(r_booking.check_in, r_booking.check_out, '[)')
                  )
                ORDER BY r.room_number
                LIMIT 1
            LOOP
                INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
                VALUES (r_booking.booking_id, r_room.room_id, r_booking.check_in, r_booking.check_out, FALSE);
                v_inserted := TRUE;
                EXIT;
            END LOOP;

            IF NOT v_inserted THEN
                RAISE WARNING 'TETRISROOM: Không tìm được phòng trống cho booking % (check_in: %)',
                    r_booking.booking_id, r_booking.check_in;
            END IF;
        END LOOP;
    END LOOP;
END;
$$;

-- =============================================================
-- Gap 6: Search services by name (used in Add Reservation popup)
-- =============================================================

CREATE OR REPLACE FUNCTION search_services(
    p_hotel_id INT,
    p_keyword  VARCHAR DEFAULT ''
)
RETURNS TABLE (
    service_id   INT,
    service_name VARCHAR,
    unit_price   DECIMAL,
    category     VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, s.name, s.unit_price, s.category
    FROM services s
    WHERE s.hotel_id = p_hotel_id
      AND (p_keyword = '' OR s.name ILIKE '%' || p_keyword || '%')
    ORDER BY s.category, s.name;
END;
$$ LANGUAGE plpgsql;

COMMIT;
