# INVOICING & REPORTING VIEWS
_Đặc tả Logic Dịch vụ, Hóa đơn và Báo cáo_

Tài liệu này bao gồm cấu trúc bảng cho các dịch vụ phụ trợ, hóa đơn thanh toán và các view (Cảnh quay dữ liệu) hỗ trợ công tác kế toán, quản lý.

## 1. DDL Bảng Phụ trợ (Dịch vụ & Hóa đơn)

```sql
CREATE TYPE invoice_status AS ENUM ('Draft', 'Issued', 'Paid', 'Void');

CREATE TABLE services (
    id SERIAL PRIMARY KEY,
    hotel_id INT NOT NULL REFERENCES hotels(id),
    name VARCHAR(100) NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL CHECK (unit_price >= 0),
    category VARCHAR(50), -- Spa, F&B, Minibar, Laundry...
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE (hotel_id, name)
);

CREATE TABLE service_usage (
    id SERIAL PRIMARY KEY,
    booking_id INT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    service_id INT NOT NULL REFERENCES services(id),
    quantity INT NOT NULL CHECK (quantity > 0),
    used_at TIMESTAMP DEFAULT NOW(),
    staff_id INT REFERENCES staff(id)
);

CREATE TABLE invoices (
    id SERIAL PRIMARY KEY,
    booking_id INT NOT NULL REFERENCES bookings(id),
    issued_at TIMESTAMP DEFAULT NOW(),
    issued_by INT REFERENCES staff(id),
    total_amount DECIMAL(10, 2) NOT NULL,
    amount_paid DECIMAL(10, 2) NOT NULL,
    balance DECIMAL(10, 2) NOT NULL,
    status invoice_status DEFAULT 'Draft'
);
```

## 2. Trigger Cập nhật Total Amount Tự động

```sql
/*
 * Mục đích: Tự động đánh thức việc tính lại giá trị của booking khi có biến động từ Service.
 * Input: Phát sinh INSERT/UPDATE/DELETE trên service_usage.
 * Output/Side effects: Update cột total_amount bảng bookings hiện hành ở thời gian thực.
 */
CREATE OR REPLACE FUNCTION sync_total_amount()
RETURNS TRIGGER AS $$
DECLARE
    v_booking_id INT;
    v_room_cost DECIMAL := 0;
    v_surcharge_cost DECIMAL := 0;
    v_service_cost DECIMAL := 0;
    v_nights INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_booking_id := OLD.booking_id;
    ELSE
        v_booking_id := NEW.booking_id;
    END IF;

    -- Tính số đêm (nếu 0 thì tối thiểu là 1)
    SELECT DATE_PART('day', check_out - check_in) INTO v_nights 
    FROM bookings WHERE id = v_booking_id;
    IF v_nights = 0 THEN v_nights := 1; END IF;

    -- Lấy tổng phần phòng
    SELECT COALESCE(SUM(agreed_price * quantity * v_nights), 0) INTO v_room_cost
    FROM booking_details WHERE booking_id = v_booking_id;

    -- Lấy tổng phụ thu
    SELECT COALESCE(SUM(amount), 0) INTO v_surcharge_cost
    FROM booking_surcharges WHERE booking_id = v_booking_id;

    -- Lấy tổng dịch vụ
    SELECT COALESCE(SUM(su.quantity * s.unit_price), 0) INTO v_service_cost
    FROM service_usage su JOIN services s ON su.service_id = s.id
    WHERE su.booking_id = v_booking_id;

    -- Cập nhật tiền tổng
    UPDATE bookings 
    SET total_amount = v_room_cost + v_surcharge_cost + v_service_cost
    WHERE id = v_booking_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_total_amount
AFTER INSERT OR UPDATE OR DELETE ON service_usage
FOR EACH ROW EXECUTE FUNCTION sync_total_amount();
```

## 3. Reporting Views (Cảnh quay báo cáo)

### 3.1. Tỷ lệ lấp đầy phòng hàng ngày
```sql
CREATE OR REPLACE VIEW v_daily_occupancy AS
SELECT 
    hotel_id,
    room_type_id,
    date,
    total_inventory,
    total_reserved,
    CASE 
        WHEN total_inventory = 0 THEN 0 
        ELSE ROUND((total_reserved * 100.0) / total_inventory, 2) 
    END AS occupancy_rate
FROM room_type_inventory rti
JOIN room_types rt ON rti.room_type_id = rt.id;
```

### 3.2. Doanh thu hàng tháng định danh khách sạn
```sql
CREATE OR REPLACE VIEW v_monthly_revenue AS
WITH SurchargeSum AS (
    SELECT booking_id, COALESCE(SUM(amount), 0) AS total_surcharges
    FROM booking_surcharges
    GROUP BY booking_id
),
ServiceSum AS (
    SELECT su.booking_id, COALESCE(SUM(su.quantity * s.unit_price), 0) AS total_services
    FROM service_usage su
    JOIN services s ON su.service_id = s.id
    GROUP BY su.booking_id
)
SELECT 
    b.hotel_id,
    DATE_TRUNC('month', b.check_out) AS report_month,
    SUM(b.total_amount) AS total_revenue,
    SUM(COALESCE(ss.total_surcharges, 0)) AS total_surcharges,
    SUM(COALESCE(svc.total_services, 0)) AS total_services,
    -- Tiền phòng gốc = Total - Surcharges - Services
    SUM(b.total_amount - COALESCE(ss.total_surcharges, 0) - COALESCE(svc.total_services, 0)) AS total_room_cost,
    SUM(b.amount_paid) AS actual_collected
FROM bookings b
LEFT JOIN SurchargeSum ss ON b.id = ss.booking_id
LEFT JOIN ServiceSum svc ON b.id = svc.booking_id
WHERE b.status IN ('Completed', 'Checked-in')
GROUP BY b.hotel_id, DATE_TRUNC('month', b.check_out);
```

### 3.3. Bảng tóm tắt công nợ khách hàng (Folio)
```sql
CREATE OR REPLACE VIEW v_booking_summary AS
SELECT 
    b.id AS booking_id,
    c.full_name AS customer_name,
    STRING_AGG(DISTINCT rt.type_name, ', ') AS room_types,
    GREATEST(DATE_PART('day', b.check_out - b.check_in), 1) AS nights,
    b.total_amount,
    b.amount_paid,
    (b.total_amount - b.amount_paid) AS balance
FROM bookings b
JOIN customers c ON b.customer_id = c.id
JOIN booking_details bd ON b.id = bd.booking_id
JOIN room_types rt ON bd.room_type_id = rt.id
GROUP BY b.id, c.full_name, b.check_in, b.check_out, b.total_amount, b.amount_paid;
```

### 3.4. Bảng điều khiển Lễ tân (Front Desk Dashboard)
```sql
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
JOIN room_types rt ON r.room_type_id = rt.id
LEFT JOIN room_assignments ra ON r.id = ra.room_id AND NOW() BETWEEN ra.check_in AND ra.check_out
LEFT JOIN bookings b ON ra.booking_id = b.id AND b.status = 'Checked-in'
LEFT JOIN customers c ON b.customer_id = c.id;
```

## 4. Kịch bản Kiểm thử Views (Test Plan)

### STT | Tên Kịch bản | Phương pháp Kiểm thử | Kết quả Mong đợi |
| --- | --- | --- | --- |
| **TC-30** | Test Tỷ lệ lấp đầy | Đặt 1 phòng trên tổng 4 phòng. Query view `v_daily_occupancy`. | `occupancy_rate` báo chính xác 25%. |
| **TC-31** | Lấp đầy chia cho 0 | Query `v_daily_occupancy` đối với ngày khách sạn chưa vận hành (Total=0). | Trả về 0%, không ném lỗi Division by Zero. |
| **TC-32** | Test Doanh thu nhiều nguồn | `INSERT` 1 booking tiền phòng $100, mua Minibar $20. Query `v_monthly_revenue`. | `total_revenue` hiển thị $120 ở đúng tháng Check-out. |
| **TC-33** | Cập nhật tự động (Trigger) | Gọi món Minibar vào `service_usage`, select trực tiếp bảng `Bookings`. | Cột `total_amount` phải thay đổi tức thì, KHÔNG cần thủ tục `check_out` chạy. |
| **TC-34** | Test Công nợ Balance | Thanh toán cọc $50 trước cho đơn $100. Đọc `v_booking_summary`. | `total_amount=100`, `amount_paid=50`, `balance=50`. |
| **TC-35** | Màn hình Lễ Tân | `CALL check_in_booking`. Query view `v_room_status_now`. | Phòng hiển thị khách đang ở `current_guest` và ngày giờ `expected_check_out`. |
