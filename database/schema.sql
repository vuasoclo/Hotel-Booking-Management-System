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
CREATE UNIQUE INDEX IF NOT EXISTS uq_invoice_active_booking
ON invoices (booking_id)
WHERE status <> 'Void';
CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);
CREATE INDEX IF NOT EXISTS idx_rooms_status ON rooms(status);
