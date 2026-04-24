-- =============================================================
-- HBMS Full Deployment (Phase 1 + Phase 2)
-- Scope:
--   Phase 1: Core Schema & DDL
--   Phase 2: Triggers & Automation
-- Database: PostgreSQL
-- =============================================================

BEGIN;

-- =============================================================
-- Phase 1: Schema & Core DDL
-- =============================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'booking_status') THEN
        CREATE TYPE booking_status AS ENUM ('Pending', 'Active', 'Checked-in', 'Completed', 'Cancelled');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'room_status') THEN
        CREATE TYPE room_status AS ENUM ('Available', 'Occupied', 'Dirty', 'Maintenance');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'surcharge_type') THEN
        CREATE TYPE surcharge_type AS ENUM ('EarlyCheckIn', 'LateCheckOut', 'Holiday', 'Weekend', 'Other');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'invoice_status') THEN
        CREATE TYPE invoice_status AS ENUM ('Draft', 'Issued', 'Paid', 'Void');
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS hotels (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    address TEXT NOT NULL,
    hotline VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS customers (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE,
    identity_card VARCHAR(50) UNIQUE,
    date_of_birth DATE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT chk_customer_age CHECK (EXTRACT(YEAR FROM AGE(date_of_birth)) >= 18)
);

CREATE TABLE IF NOT EXISTS staff (
    id SERIAL PRIMARY KEY,
    hotel_id INT REFERENCES hotels(id),
    name VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS surcharge_policies (
    id SERIAL PRIMARY KEY,
    policy_type surcharge_type NOT NULL,
    description VARCHAR(255),
    multiplier DECIMAL(5, 2) NOT NULL CHECK (multiplier >= 0),
    start_time TIME,
    end_time TIME,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS room_types (
    id SERIAL PRIMARY KEY,
    hotel_id INT NOT NULL REFERENCES hotels(id),
    type_name VARCHAR(50) NOT NULL,
    base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
    max_capacity INT NOT NULL CHECK (max_capacity > 0),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    updated_by INT REFERENCES staff(id),
    UNIQUE (hotel_id, type_name)
);

CREATE TABLE IF NOT EXISTS rooms (
    id SERIAL PRIMARY KEY,
    hotel_id INT NOT NULL REFERENCES hotels(id),
    room_number VARCHAR(10) NOT NULL,
    room_type_id INT NOT NULL REFERENCES room_types(id) ON DELETE RESTRICT,
    status room_status DEFAULT 'Available',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    updated_by INT REFERENCES staff(id),
    UNIQUE (hotel_id, room_number)
);

CREATE TABLE IF NOT EXISTS room_type_inventory (
    room_type_id INT REFERENCES room_types(id),
    date DATE NOT NULL,
    total_inventory INT NOT NULL DEFAULT 0 CHECK (total_inventory >= 0),
    total_reserved INT NOT NULL DEFAULT 0 CHECK (total_reserved >= 0),
    CONSTRAINT no_overbook CHECK (total_reserved <= total_inventory),
    PRIMARY KEY (room_type_id, date)
);

CREATE TABLE IF NOT EXISTS bookings (
    id SERIAL PRIMARY KEY,
    hotel_id INT NOT NULL REFERENCES hotels(id),
    customer_id INT NOT NULL REFERENCES customers(id),
    status booking_status DEFAULT 'Pending',
    idempotency_key UUID UNIQUE,
    check_in TIMESTAMP NOT NULL,
    check_out TIMESTAMP NOT NULL CHECK (check_out > check_in),
    total_amount DECIMAL(10, 2) DEFAULT 0 CHECK (total_amount >= 0),
    amount_paid DECIMAL(10, 2) DEFAULT 0 CHECK (amount_paid >= 0),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    updated_by INT REFERENCES staff(id),
    cancelled_at TIMESTAMP,
    cancel_reason TEXT,
    CONSTRAINT chk_amount_paid CHECK (amount_paid <= total_amount)
);

CREATE TABLE IF NOT EXISTS booking_details (
    id SERIAL PRIMARY KEY,
    booking_id INT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    room_type_id INT NOT NULL REFERENCES room_types(id) ON DELETE RESTRICT,
    agreed_price DECIMAL(10, 2) NOT NULL CHECK (agreed_price >= 0),
    quantity INT NOT NULL CHECK (quantity > 0),
    is_breakfast_included BOOLEAN DEFAULT FALSE,
    CONSTRAINT uq_booking_room_type UNIQUE (booking_id, room_type_id)
);

CREATE TABLE IF NOT EXISTS booking_surcharges (
    id SERIAL PRIMARY KEY,
    booking_id INT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    surcharge_type surcharge_type NOT NULL,
    amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
    description VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS room_assignments (
    id SERIAL PRIMARY KEY,
    booking_id INT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    room_id INT NOT NULL REFERENCES rooms(id) ON DELETE RESTRICT,
    check_in TIMESTAMP NOT NULL,
    check_out TIMESTAMP NOT NULL CHECK (check_out > check_in),
    is_cancelled BOOLEAN DEFAULT FALSE,
    assigned_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT exclude_overlapping_assignments EXCLUDE USING gist (
        room_id WITH =,
        tsrange(check_in, check_out, '[)') WITH &&
    ) WHERE (is_cancelled = FALSE)
);

CREATE TABLE IF NOT EXISTS services (
    id SERIAL PRIMARY KEY,
    hotel_id INT NOT NULL REFERENCES hotels(id),
    name VARCHAR(100) NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL CHECK (unit_price >= 0),
    category VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE (hotel_id, name)
);

CREATE TABLE IF NOT EXISTS service_usage (
    id SERIAL PRIMARY KEY,
    booking_id INT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    service_id INT NOT NULL REFERENCES services(id),
    quantity INT NOT NULL CHECK (quantity > 0),
    used_at TIMESTAMP DEFAULT NOW(),
    staff_id INT REFERENCES staff(id)
);

CREATE TABLE IF NOT EXISTS invoices (
    id SERIAL PRIMARY KEY,
    booking_id INT NOT NULL REFERENCES bookings(id),
    issued_at TIMESTAMP DEFAULT NOW(),
    issued_by INT REFERENCES staff(id),
    total_amount DECIMAL(10, 2) NOT NULL CHECK (total_amount >= 0),
    amount_paid DECIMAL(10, 2) NOT NULL CHECK (amount_paid >= 0),
    balance DECIMAL(10, 2) NOT NULL,
    status invoice_status DEFAULT 'Draft',
    CONSTRAINT chk_invoice_balance CHECK (balance = total_amount - amount_paid),
    CONSTRAINT uq_invoice_booking UNIQUE (booking_id)
);

-- Partial index: Chỉ cho phép một invoice active mỗi booking (không tính trạng thái Void)
CREATE UNIQUE INDEX IF NOT EXISTS uq_invoice_active_booking 
ON invoices (booking_id) 
WHERE status <> 'Void';

-- =============================================================
-- Phase 2: Triggers & Automation
-- =============================================================

CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rooms_updated ON rooms;
CREATE TRIGGER trg_rooms_updated
BEFORE UPDATE ON rooms
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS trg_bookings_updated ON bookings;
CREATE TRIGGER trg_bookings_updated
BEFORE UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();

CREATE OR REPLACE FUNCTION set_agreed_price()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.agreed_price IS NULL OR NEW.agreed_price = 0 THEN
        SELECT base_price INTO NEW.agreed_price
        FROM room_types
        WHERE id = NEW.room_type_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_snapshot_price ON booking_details;
CREATE TRIGGER trg_snapshot_price
BEFORE INSERT ON booking_details
FOR EACH ROW
EXECUTE FUNCTION set_agreed_price();

CREATE OR REPLACE FUNCTION release_inventory_on_cancel()
RETURNS TRIGGER AS $$
DECLARE
    r RECORD;
    v_cur_date DATE;
    v_end_date DATE;
BEGIN
    FOR r IN
        SELECT room_type_id, quantity
        FROM booking_details
        WHERE booking_id = NEW.id
    LOOP
        v_cur_date := NEW.check_in::DATE;
        v_end_date := NEW.check_out::DATE;

        WHILE v_cur_date < v_end_date LOOP
            UPDATE room_type_inventory
            SET total_reserved = GREATEST(total_reserved - r.quantity, 0)
            WHERE room_type_id = r.room_type_id
              AND date = v_cur_date;

            v_cur_date := v_cur_date + 1;
        END LOOP;
    END LOOP;

    UPDATE room_assignments
    SET is_cancelled = TRUE
    WHERE booking_id = NEW.id
      AND is_cancelled = FALSE;

    IF NEW.cancelled_at IS NULL THEN
        NEW.cancelled_at := NOW();
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_release_inventory_on_cancel ON bookings;
CREATE TRIGGER trg_release_inventory_on_cancel
BEFORE UPDATE ON bookings
FOR EACH ROW
WHEN (NEW.status = 'Cancelled' AND OLD.status <> 'Cancelled')
EXECUTE FUNCTION release_inventory_on_cancel();

CREATE OR REPLACE FUNCTION recalculate_booking_total(p_booking_id INT)
RETURNS VOID AS $$
DECLARE
    v_nights INT;
    v_room_cost DECIMAL(10, 2) := 0;
    v_surcharge_cost DECIMAL(10, 2) := 0;
    v_service_cost DECIMAL(10, 2) := 0;
BEGIN
    IF p_booking_id IS NULL THEN
        RETURN;
    END IF;

    SELECT GREATEST((check_out::DATE - check_in::DATE), 1)
    INTO v_nights
    FROM bookings
    WHERE id = p_booking_id;

    IF v_nights IS NULL THEN
        RETURN;
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

    UPDATE bookings
    SET total_amount = v_room_cost + v_surcharge_cost + v_service_cost
    WHERE id = p_booking_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_total_amount()
RETURNS TRIGGER AS $$
DECLARE
    v_new_booking_id INT;
    v_old_booking_id INT;
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new_booking_id := NEW.booking_id;
    END IF;

    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        v_old_booking_id := OLD.booking_id;
    END IF;

    IF TG_OP = 'UPDATE' AND v_old_booking_id IS DISTINCT FROM v_new_booking_id THEN
        PERFORM recalculate_booking_total(v_old_booking_id);
        PERFORM recalculate_booking_total(v_new_booking_id);
    ELSE
        PERFORM recalculate_booking_total(COALESCE(v_new_booking_id, v_old_booking_id));
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_total_amount ON service_usage;
CREATE TRIGGER trg_sync_total_amount
AFTER INSERT OR UPDATE OR DELETE ON service_usage
FOR EACH ROW
EXECUTE FUNCTION sync_total_amount();

-- =============================================================
-- Phase 3: Reservation Procedures & Time Surcharges
-- =============================================================

CREATE OR REPLACE FUNCTION apply_time_surcharges(p_booking_id INT)
RETURNS VOID AS $$
DECLARE
    v_check_in TIMESTAMP;
    v_check_out TIMESTAMP;
BEGIN
    SELECT check_in, check_out
    INTO v_check_in, v_check_out
    FROM bookings
    WHERE id = p_booking_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'BOOKING_NOT_FOUND: booking_id % không tồn tại', p_booking_id
        USING ERRCODE = 'P0004';
    END IF;

    -- Làm sạch phụ thu theo giờ trước khi tính lại để tránh trùng khi retry.
    DELETE FROM booking_surcharges
    WHERE booking_id = p_booking_id
      AND surcharge_type IN ('EarlyCheckIn', 'LateCheckOut');

    INSERT INTO booking_surcharges (booking_id, surcharge_type, amount, description)
    SELECT
        p_booking_id,
        sp.policy_type,
        (bd.agreed_price * sp.multiplier * bd.quantity)::DECIMAL(10, 2) AS amount,
        COALESCE(sp.description, 'Auto time surcharge')
    FROM booking_details bd
    JOIN surcharge_policies sp
      ON sp.is_active = TRUE
     AND (
            (sp.policy_type = 'EarlyCheckIn' AND v_check_in::TIME BETWEEN sp.start_time AND sp.end_time)
         OR (sp.policy_type = 'LateCheckOut' AND v_check_out::TIME BETWEEN sp.start_time AND sp.end_time)
     )
    WHERE bd.booking_id = p_booking_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE create_reservation(
    p_hotel_id INT,
    p_customer_id INT,
    p_room_type_id INT,
    p_quantity INT,
    p_check_in TIMESTAMP,
    p_check_out TIMESTAMP,
    p_is_breakfast_included BOOLEAN,
    p_idempotency_key UUID
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_booking_id INT;
    v_cur_date DATE := p_check_in::DATE;
    v_end_date DATE := p_check_out::DATE;
    v_available INT;
BEGIN
    IF p_check_out <= p_check_in THEN
        RAISE EXCEPTION 'INVALID_PERIOD: check_out phải lớn hơn check_in'
        USING ERRCODE = 'P0005';
    END IF;

    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'INVALID_QUANTITY: quantity phải lớn hơn 0'
        USING ERRCODE = 'P0006';
    END IF;

    BEGIN
        INSERT INTO bookings (
            hotel_id,
            customer_id,
            idempotency_key,
            check_in,
            check_out,
            status
        )
        VALUES (
            p_hotel_id,
            p_customer_id,
            p_idempotency_key,
            p_check_in,
            p_check_out,
            'Pending'
        )
        RETURNING id INTO v_booking_id;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'DUPLICATE: idempotency_key % đã tồn tại', p_idempotency_key
            USING ERRCODE = 'P0002';
    END;

    INSERT INTO booking_details (
        booking_id,
        room_type_id,
        quantity,
        agreed_price,
        is_breakfast_included
    )
    VALUES (
        v_booking_id,
        p_room_type_id,
        p_quantity,
        0,
        p_is_breakfast_included
    );

    WHILE v_cur_date < v_end_date LOOP
        SELECT (total_inventory - total_reserved)
        INTO v_available
        FROM room_type_inventory
        WHERE room_type_id = p_room_type_id
          AND date = v_cur_date
        FOR UPDATE;

        IF v_available IS NULL THEN
            RAISE EXCEPTION 'SYSTEM: Chưa thiết lập phòng loại % trong ngày %', p_room_type_id, v_cur_date
            USING ERRCODE = 'P0003';
        END IF;

        IF v_available < p_quantity THEN
            RAISE EXCEPTION 'OVERBOOKING: Không đủ phòng loại % trong ngày % (Còn: %)',
                p_room_type_id, v_cur_date, v_available
            USING ERRCODE = 'P0001';
        END IF;

        UPDATE room_type_inventory
        SET total_reserved = total_reserved + p_quantity
        WHERE room_type_id = p_room_type_id
          AND date = v_cur_date;

        v_cur_date := v_cur_date + 1;
    END LOOP;

    UPDATE bookings
    SET status = 'Active'
    WHERE id = v_booking_id;

    PERFORM apply_time_surcharges(v_booking_id);

    -- Transaction lifecycle do tầng Application quản lý.
    -- Procedure này chỉ thực hiện DML và raise lỗi nghiệp vụ.
END;
$$;

-- =============================================================
-- Phase 4: Room Operations + Reporting Views
-- =============================================================

CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);
CREATE INDEX IF NOT EXISTS idx_rooms_status ON rooms(status);

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

    IF v_booking_status IS DISTINCT FROM 'Active' THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Booking % không ở trạng thái Active', p_booking_id
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

    INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
    VALUES (p_booking_id, p_room_id, v_check_in, v_check_out, FALSE);

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

CREATE OR REPLACE VIEW v_daily_occupancy AS
SELECT
    rt.hotel_id,
    rti.room_type_id,
    rti.date,
    rti.total_inventory,
    rti.total_reserved,
    CASE
        WHEN rti.total_inventory = 0 THEN 0
        ELSE ROUND((rti.total_reserved * 100.0) / rti.total_inventory, 2)
    END AS occupancy_rate
FROM room_type_inventory rti
JOIN room_types rt ON rt.id = rti.room_type_id;

CREATE OR REPLACE VIEW v_monthly_revenue AS
WITH booking_base AS (
    SELECT
        b.id,
        b.hotel_id,
        DATE_TRUNC('month', b.check_out) AS report_month,
        b.amount_paid,
        GREATEST((b.check_out::DATE - b.check_in::DATE), 1) AS nights
    FROM bookings b
    WHERE b.status IN ('Completed', 'Checked-in')
),
room_sum AS (
    SELECT
        bb.id AS booking_id,
        COALESCE(SUM(bd.agreed_price * bd.quantity * bb.nights), 0) AS total_room_cost
    FROM booking_base bb
    LEFT JOIN booking_details bd ON bd.booking_id = bb.id
    GROUP BY bb.id
),
surcharge_sum AS (
    SELECT
        bs.booking_id,
        COALESCE(SUM(bs.amount), 0) AS total_surcharges
    FROM booking_surcharges bs
    GROUP BY bs.booking_id
),
service_sum AS (
    SELECT
        su.booking_id,
        COALESCE(SUM(su.quantity * s.unit_price), 0) AS total_services
    FROM service_usage su
    JOIN services s ON s.id = su.service_id
    GROUP BY su.booking_id
)
SELECT
    bb.hotel_id,
    bb.report_month,
    SUM(COALESCE(rs.total_room_cost, 0)) AS total_room_cost,
    SUM(COALESCE(ss.total_surcharges, 0)) AS total_surcharges,
    SUM(COALESCE(svs.total_services, 0)) AS total_services,
    SUM(COALESCE(rs.total_room_cost, 0) + COALESCE(ss.total_surcharges, 0) + COALESCE(svs.total_services, 0)) AS total_revenue,
    SUM(bb.amount_paid) AS actual_collected
FROM booking_base bb
LEFT JOIN room_sum rs ON rs.booking_id = bb.id
LEFT JOIN surcharge_sum ss ON ss.booking_id = bb.id
LEFT JOIN service_sum svs ON svs.booking_id = bb.id
GROUP BY bb.hotel_id, bb.report_month;

CREATE OR REPLACE VIEW v_booking_summary AS
SELECT
    b.id AS booking_id,
    c.full_name AS customer_name,
    STRING_AGG(DISTINCT rt.type_name, ', ') AS room_types,
    GREATEST((b.check_out::DATE - b.check_in::DATE), 1) AS nights,
    b.total_amount,
    b.amount_paid,
    (b.total_amount - b.amount_paid) AS balance
FROM bookings b
JOIN customers c ON c.id = b.customer_id
JOIN booking_details bd ON bd.booking_id = b.id
JOIN room_types rt ON rt.id = bd.room_type_id
GROUP BY b.id, c.full_name, b.check_in, b.check_out, b.total_amount, b.amount_paid;

CREATE OR REPLACE VIEW v_room_status_now AS
SELECT
    r.hotel_id,
    r.id AS room_id,
    r.room_number,
    rt.type_name,
    r.status AS physical_status,
    c.full_name AS current_guest,
    b.check_out AS expected_check_out
FROM rooms r
JOIN room_types rt ON rt.id = r.room_type_id
LEFT JOIN room_assignments ra
       ON ra.room_id = r.id
      AND ra.is_cancelled = FALSE
      AND NOW() >= ra.check_in
      AND NOW() < ra.check_out
LEFT JOIN bookings b
       ON b.id = ra.booking_id
      AND b.status = 'Checked-in'
LEFT JOIN customers c ON c.id = b.customer_id;

CREATE OR REPLACE PROCEDURE reset_hbms_data()
LANGUAGE plpgsql
AS $$
BEGIN
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
END;
$$;

COMMIT;
