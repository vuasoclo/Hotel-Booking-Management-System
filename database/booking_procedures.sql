CREATE OR REPLACE PROCEDURE check_in_booking(
    p_booking_id INT,
    p_room_id INT,
    p_staff_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_booking_status booking_status;
    v_room_status room_status;
    v_check_in TIMESTAMP;
    v_check_out TIMESTAMP;
BEGIN
    SELECT status, check_in, check_out
    INTO v_booking_status, v_check_in, v_check_out
    FROM bookings
    WHERE id = p_booking_id
    FOR UPDATE;
    IF v_booking_status NOT IN ('Active', 'Checked-in') THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Booking % không ở trạng thái Active hoặc Checked-in (hiện tại: %)', p_booking_id, v_booking_status
        USING ERRCODE = 'P0011';
    END IF;
    SELECT status
    INTO v_room_status
    FROM rooms
    WHERE id = p_room_id
    FOR UPDATE;
    IF v_room_status IS DISTINCT FROM 'Available' THEN
        RAISE EXCEPTION 'ROOM_NOT_AVAILABLE: Phòng % không sẵn sàng. Trạng thái hiện tại: %', p_room_id, v_room_status
        USING ERRCODE = 'P0010';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM room_assignments
        WHERE booking_id = p_booking_id
          AND room_id = p_room_id
          AND is_cancelled = FALSE
    ) THEN
        INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
        VALUES (p_booking_id, p_room_id, v_check_in, v_check_out, FALSE);
    END IF;
    UPDATE rooms
    SET status = 'Occupied',
        updated_by = p_staff_id
    WHERE id = p_room_id;
    UPDATE bookings
    SET status = 'Checked-in',
        updated_by = p_staff_id
    WHERE id = p_booking_id;
END;
$$;
CREATE OR REPLACE PROCEDURE check_out_booking(
    p_booking_id INT,
    p_staff_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_booking_status booking_status;
    v_room_cost DECIMAL(10, 2) := 0;
    v_surcharge_cost DECIMAL(10, 2) := 0;
    v_service_cost DECIMAL(10, 2) := 0;
    v_total DECIMAL(10, 2) := 0;
    v_nights INT;
BEGIN
    SELECT status, GREATEST((check_out::DATE - check_in::DATE), 1)
    INTO v_booking_status, v_nights
    FROM bookings
    WHERE id = p_booking_id
    FOR UPDATE;
    IF v_booking_status IS DISTINCT FROM 'Checked-in' THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Chỉ có thể check-out booking ở trạng thái Checked-in'
        USING ERRCODE = 'P0012';
    END IF;
    SELECT COALESCE(SUM(agreed_price * quantity * v_nights), 0)
    INTO v_room_cost
    FROM booking_details
    WHERE booking_id = p_booking_id;
    SELECT COALESCE(SUM(amount), 0)
    INTO v_surcharge_cost
    FROM booking_surcharges
    WHERE booking_id = p_booking_id;
    SELECT COALESCE(SUM(su.quantity * s.unit_price), 0)
    INTO v_service_cost
    FROM service_usage su
    JOIN services s ON s.id = su.service_id
    WHERE su.booking_id = p_booking_id;
    v_total := v_room_cost + v_surcharge_cost + v_service_cost;
    UPDATE bookings
    SET total_amount = v_total,
        status = 'Completed',
        updated_by = p_staff_id
    WHERE id = p_booking_id;
    UPDATE rooms
    SET status = 'Dirty',
        updated_by = p_staff_id
    WHERE id IN (
        SELECT ra.room_id
        FROM room_assignments ra
        WHERE ra.booking_id = p_booking_id
          AND ra.is_cancelled = FALSE
    );
    UPDATE room_assignments
    SET check_out = NOW()
    WHERE booking_id = p_booking_id
      AND is_cancelled = FALSE
      AND check_out > NOW();
END;
$$;
CREATE OR REPLACE PROCEDURE housekeeping_complete(
    p_room_id INT,
    p_staff_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_status room_status;
BEGIN
    SELECT status
    INTO v_room_status
    FROM rooms
    WHERE id = p_room_id
    FOR UPDATE;
    IF v_room_status IS DISTINCT FROM 'Dirty' THEN
        RAISE EXCEPTION 'HOUSEKEEPING_INVALID: Chỉ cho phép khi phòng ở trạng thái Dirty'
        USING ERRCODE = 'P0013';
    END IF;
    UPDATE rooms
    SET status = 'Available',
        updated_by = p_staff_id
    WHERE id = p_room_id;
END;
$$;

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
    DECLARE
        v_base_price DECIMAL(10, 2);
    BEGIN
        SELECT base_price INTO v_base_price FROM room_types WHERE id = p_room_type_id;
        INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price, is_breakfast_included)
        VALUES (p_booking_id, p_room_type_id, p_quantity, v_base_price, p_is_breakfast_included);
    END;
END;
$$;
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

CREATE OR REPLACE PROCEDURE pre_assign_room(
    p_booking_id   INT,
    p_from_room_id INT,
    p_to_room_id   INT,
    p_staff_id     INT
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
    SELECT r.room_type_id INTO v_room_type_id
    FROM rooms r
    WHERE r.id = p_to_room_id;
    IF NOT EXISTS (
        SELECT 1 FROM booking_details
        WHERE booking_id = p_booking_id AND room_type_id = v_room_type_id
    ) THEN
        RAISE EXCEPTION 'ROOM_TYPE_MISMATCH: Phòng % không thuộc loại phòng nào trong booking %', p_to_room_id, p_booking_id
        USING ERRCODE = 'P0015';
    END IF;
    UPDATE room_assignments
    SET is_cancelled = TRUE
    WHERE booking_id   = p_booking_id
      AND room_id      = p_from_room_id
      AND is_cancelled = FALSE;
    INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
    VALUES (p_booking_id, p_to_room_id, v_check_in, v_check_out, FALSE);
END;
$$;
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
FROM rooms r
JOIN room_types rt ON rt.id = r.room_type_id
LEFT JOIN room_assignments ra ON ra.room_id = r.id AND ra.is_cancelled = FALSE
LEFT JOIN bookings b ON b.id = ra.booking_id AND b.status IN ('Active', 'Checked-in')
LEFT JOIN customers c ON c.id = b.customer_id;
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
        UPDATE room_assignments ra
        SET is_cancelled = TRUE
        FROM bookings b, rooms r
        WHERE ra.booking_id = b.id
          AND ra.room_id    = r.id
          AND r.room_type_id = r_type.room_type_id
          AND b.status      = 'Active'
          AND ra.is_cancelled = FALSE;
        FOR r_booking IN
            SELECT b.id AS booking_id, b.check_in, b.check_out, bd.quantity
            FROM bookings b
            JOIN booking_details bd
              ON bd.booking_id   = b.id
             AND bd.room_type_id = r_type.room_type_id
            WHERE b.hotel_id = p_hotel_id
              AND b.status   = 'Active'
            ORDER BY b.check_in
        LOOP
            FOR i IN 1..r_booking.quantity LOOP
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
    END LOOP;
END;
$$;
