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
    username VARCHAR(50) UNIQUE,
    password_hash VARCHAR(255),
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

DROP TRIGGER IF EXISTS trg_sync_total_amount_bd ON booking_details;
CREATE TRIGGER trg_sync_total_amount_bd
AFTER INSERT OR UPDATE OR DELETE ON booking_details
FOR EACH ROW
EXECUTE FUNCTION sync_total_amount();

DROP TRIGGER IF EXISTS trg_sync_total_amount_bs ON booking_surcharges;
CREATE TRIGGER trg_sync_total_amount_bs
AFTER INSERT OR UPDATE OR DELETE ON booking_surcharges
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

-- =============================================================
-- [DEPRECATED] create_reservation() — Phase 3
-- Thay thế bởi 3-step flow trong Phase 5:
--   begin_booking() → add_room_detail_to_booking() → finalize_booking()
-- Lý do: create_reservation() chỉ hỗ trợ 1 loại phòng per booking.
--         Flow 3-step hỗ trợ multi room-type và idempotent retries tốt hơn.
-- Không xóa hoàn toàn để tham khảo logic gốc.
-- =============================================================
/*
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
...
*/

CREATE OR REPLACE FUNCTION search_available_rooms(
    p_start_date DATE,
    p_end_date   DATE
)
RETURNS TABLE (
    room_type_id      INT,
    type_name         VARCHAR,
    min_available     INT,
    base_price        DECIMAL,
    has_missing_dates BOOLEAN   -- ← thêm cột này
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        rt.id,
        rt.type_name,
        -- Nếu có ngày thiếu → trả 0 (không khả dụng), tránh MIN tính trên tập không đủ
        CASE
            WHEN BOOL_OR(rti.date IS NULL)
            THEN 0
            ELSE MIN(rti.total_inventory - rti.total_reserved)::INT
        END                                AS min_available,
        rt.base_price,
        BOOL_OR(rti.date IS NULL)          AS has_missing_dates
    FROM room_types rt
    -- Sinh ra đủ mọi ngày trong khoảng, không phụ thuộc inventory đã có hay chưa
    CROSS JOIN generate_series(
        p_start_date,
        p_end_date - 1,        -- exclusive end, khớp với create_reservation loop
        '1 day'::interval
    ) AS d(dt)
    LEFT JOIN room_type_inventory rti
           ON rti.room_type_id = rt.id
          AND rti.date         = d.dt::DATE
    GROUP BY rt.id, rt.type_name, rt.base_price;
    -- Bỏ HAVING → trả về tất cả loại phòng, UI tự phân loại theo min_available và has_missing_dates
END;
$$ LANGUAGE plpgsql;

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

    -- Giải phóng phòng cho các ngày tiếp theo nếu khách checkout sớm
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

-- =============================================================
-- Phase 5: Gap-fill Additions (Scenario 1 & 2)
-- =============================================================

-- Gap 1: Multi-room-type reservation in a single booking
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

-- Step B: Attach one room-type line to an existing Pending booking
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

-- Step C: Finalise booking and apply time surcharges
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

-- Gap 2: Invoice issuance & payment recording
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
                        WHEN (amount_paid + p_amount) >= total_amount THEN 'Paid'::invoice_status
                        ELSE 'Issued'::invoice_status
                      END
    WHERE booking_id = p_booking_id
      AND status <> 'Void';
END;
$$;

-- Gap 3: Pre-assign room for Active booking
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

    -- Hủy assignment cũ của phòng cụ thể này trước khi gán phòng mới
    UPDATE room_assignments
    SET is_cancelled = TRUE
    WHERE booking_id   = p_booking_id
      AND room_id      = p_from_room_id
      AND is_cancelled = FALSE;

    INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
    VALUES (p_booking_id, p_to_room_id, v_check_in, v_check_out, FALSE);
END;
$$;

-- Gap 4: Calendar view
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

-- Gap 5: TetrisRoom defragmentation
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

-- Gap 6: Search services by name
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
