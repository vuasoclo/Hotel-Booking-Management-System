# DATABASE PHYSICAL SCHEMA & DDL SCRIPT
_Phiên bản: Hybrid Model (2 Pha Đặt Phòng)_
_Hệ quản trị: PostgreSQL_

Dưới đây là đặc tả cấu trúc vật lý của cơ sở dữ liệu dựa trên sự thay đổi thiết kế từ `HBMS_design_delta.md`.

## 1. Định nghĩa Kiểu dữ liệu & Enum

```sql
CREATE TYPE booking_status AS ENUM ('Pending', 'Active', 'Checked-in', 'Completed', 'Cancelled');
CREATE TYPE room_status AS ENUM ('Available', 'Occupied', 'Dirty', 'Maintenance');
```

## 2. Bảng Danh mục & Cấu trúc tĩnh

```sql
CREATE TABLE staff (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE room_types (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) UNIQUE NOT NULL,      -- Deluxe, Suite...
    base_price DECIMAL(10, 2) NOT NULL CHECK (base_price >= 0),
    max_capacity INT NOT NULL CHECK (max_capacity > 0),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    updated_by INT REFERENCES staff(id)
);

CREATE TABLE rooms (
    id SERIAL PRIMARY KEY,
    room_number VARCHAR(10) UNIQUE NOT NULL,    -- 101, 202...
    room_type_id INT NOT NULL REFERENCES room_types(id) ON DELETE RESTRICT,
    status room_status DEFAULT 'Available',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    updated_by INT REFERENCES staff(id)
);
```

## 3. Quản lý Tồn kho 

```sql
CREATE TABLE room_type_inventory (
    room_type_id INT REFERENCES room_types(id),
    date DATE NOT NULL,
    total_inventory INT NOT NULL DEFAULT 0,     -- Tổng số phòng của loại này
    total_reserved INT NOT NULL DEFAULT 0,      -- Số phòng đã được đặt
    CONSTRAINT no_overbook CHECK (total_reserved <= total_inventory),
    PRIMARY KEY (room_type_id, date)
);
```

## 4. Quản lý Giao dịch Đặt phòng (Pha 1)

```sql
CREATE TABLE bookings (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL, -- Tham chiếu tới customer table
    status booking_status DEFAULT 'Pending',
    idempotency_key UUID UNIQUE, -- Chống tạo đơn rác 2 lần
    total_amount DECIMAL(10, 2) DEFAULT 0,
    check_in DATE NOT NULL,
    check_out DATE NOT NULL CHECK (check_out > check_in),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    updated_by INT REFERENCES staff(id),
    cancelled_at TIMESTAMP,
    cancel_reason TEXT
);

CREATE TABLE booking_details (
    id SERIAL PRIMARY KEY,
    booking_id INT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    room_type_id INT NOT NULL REFERENCES room_types(id) ON DELETE RESTRICT,
    agreed_price DECIMAL(10, 2) NOT NULL CHECK (agreed_price >= 0), -- Snapshot giá
    quantity INT NOT NULL CHECK (quantity > 0)
);
```

## 5. Quản lý Gán phòng Check-in (Pha 2)

Sử dụng `EXCLUDE CONSTRAINT` trên khoảng thời gian để ngăn việc một phòng vật lý bị gán cho 2 booking khác nhau trùng lấp. Mệnh đề `WHERE` đảm bảo các booking bị Cancel không giữ phòng.

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE room_assignments (
    id SERIAL PRIMARY KEY,
    booking_id INT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    room_id INT NOT NULL REFERENCES rooms(id) ON DELETE RESTRICT,
    assigned_at TIMESTAMP DEFAULT NOW(),
    
    -- EXCLUDE CONSTRAINT: Không cho phép trùng (Overlap)
    CONSTRAINT exclude_overlapping_assignments EXCLUDE USING gist (
        room_id WITH =,
        daterange((SELECT check_in FROM bookings WHERE id = booking_id), 
                  (SELECT check_out FROM bookings WHERE id = booking_id), '[)') WITH &&
    ) WHERE (booking_id IN (SELECT id FROM bookings WHERE status != 'Cancelled'))
);
```
*(Ghi chú: Trong PostgreSQL thực tế, bạn không thể sử dụng Subquery trực tiếp ở EXCLUDE USING gist. Do đó ta sẽ cần denormalize (mang cột check_in/check_out xuống bảng `room_assignments`) hoặc dùng trigger kiểm tra. Chi tiết sẽ tinh chỉnh ở bước implement, nhưng đặc tả constraint phải thể hiện rõ ý định này)*

## 6. Audit & Automation Triggers

```sql
-- Hàm trigger tự động cập nhật updated_at
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_rooms_updated
BEFORE UPDATE ON rooms FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_bookings_updated
BEFORE UPDATE ON bookings FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
```