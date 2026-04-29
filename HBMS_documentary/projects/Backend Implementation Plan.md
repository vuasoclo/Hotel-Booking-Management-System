# HBMS Backend — Kế hoạch Triển khai & Fix

> **Mục tiêu:** Làm backend FastAPI hoạt động đúng với 21 endpoints, liên kết frontend HTML ↔ backend ↔ PostgreSQL; insert mock data để demo toàn bộ flow.

---

## 1. Tổng quan kiến trúc

```
frontend/ (Nginx :3000)
  ├── index.html           → POST /api/auth/login
  ├── calendar.html        → GET /api/calendar, POST defragment, pre-assign
  ├── new-reservation.html → GET /api/rooms/available, POST begin/rooms/finalize
  ├── booking-detail.html  → GET /api/bookings/{id}, POST checkin/checkout/cancel/invoice/payment
  ├── rooms.html           → GET /api/rooms/status, POST housekeeping
  └── statistics.html      → GET /api/statistics

backend/ (FastAPI :8000)
  └── main.py ←→ database.py ←→ PostgreSQL hbms_db :5432

database/
  └── HBMS_full_deployment.sql  (auto-init qua docker-entrypoint)
```

---

## 2. Bug Report — Signature mismatch (main.py vs SQL)

> [!CAUTION]
> Các endpoint sau đang gọi Stored Procedure với **sai số tham số**. Phải fix trước khi test.

| # | Endpoint | main.py gọi | SQL thực tế | Fix cần làm |
|---|---|---|---|---|
| A | `POST /bookings/{id}/checkin` | `check_in_booking(id, staff_id)` — 2 params | `check_in_booking(booking_id, room_id, staff_id)` — 3 params | Thêm `room_id` vào `CheckInRequest` |
| B | `POST /calendar/pre-assign` | `pre_assign_room(booking_id, room_id)` — 2 params | `pre_assign_room(booking_id, room_id, staff_id)` — 3 params | Thêm `staff_id` vào `PreAssignRequest` |
| C | `POST /calendar/defragment` | `tetrisroom_defrag(hotel_id)` — 1 param | `tetrisroom_defrag(hotel_id, staff_id)` — 2 params | Thêm `staff_id` query param |
| D | `POST /bookings/{id}/finalize` | `finalize_booking(id, staff_id)` — 2 params | `finalize_booking(booking_id)` — 1 param | Bỏ `staff_id` khỏi CALL |
| E | `POST /bookings/{id}/payment` | `record_payment(id, amount, method, staff_id)` — 4 params | `record_payment(id, amount, staff_id)` — 3 params | Bỏ `payment_method` khỏi CALL |
| F | `GET /bookings/{id}` | Query `v_booking_summary` — thiếu `status`, `check_in`, `check_out`, `phone` | View không expose đủ fields | JOIN trực tiếp từ `bookings` + `customers` |

---

## 3. Fix chi tiết từng Bug trong `main.py`

### Bug A — check_in_booking (thiếu room_id)

```python
class CheckInRequest(BaseModel):
    room_id: int      # ← thêm mới
    staff_id: int

@app.post("/api/bookings/{booking_id}/checkin", tags=["Bookings"])
def checkin(booking_id: int, body: CheckInRequest):
    execute("CALL check_in_booking(%s, %s, %s)", (booking_id, body.room_id, body.staff_id))
    return {"success": True}
```

> [!NOTE]
> Frontend `booking-detail.html` cần thêm UI để chọn `room_id` trước khi check-in (dropdown phòng Available cùng loại).

### Bug B — pre_assign_room (thiếu staff_id)

```python
class PreAssignRequest(BaseModel):
    booking_id: int
    room_id: int
    staff_id: int     # ← thêm mới

@app.post("/api/calendar/pre-assign", tags=["Calendar"])
def pre_assign(body: PreAssignRequest):
    execute("CALL pre_assign_room(%s, %s, %s)", (body.booking_id, body.room_id, body.staff_id))
    return {"success": True}
```

### Bug C — tetrisroom_defrag (thiếu staff_id)

```python
@app.post("/api/calendar/defragment", tags=["Calendar"])
def defragment(hotel_id: int, staff_id: int):   # ← thêm staff_id
    execute("CALL tetrisroom_defrag(%s, %s)", (hotel_id, staff_id))
    return {"success": True, "message": "Phân bổ phòng đã được tối ưu."}
```

### Bug D — finalize_booking (thừa staff_id)

```python
@app.post("/api/bookings/{booking_id}/finalize", tags=["Bookings"])
def finalize_booking(booking_id: int, body: FinalizeBookingRequest):
    execute("CALL finalize_booking(%s)", (booking_id,))  # ← bỏ staff_id
    return {"success": True}
```

### Bug E — record_payment (thừa payment_method)

```python
@app.post("/api/bookings/{booking_id}/payment", tags=["Bookings"])
def record_payment(booking_id: int, body: RecordPaymentRequest):
    execute(
        "CALL record_payment(%s, %s, %s)",
        (booking_id, body.amount, body.staff_id)  # ← bỏ body.payment_method
    )
    return {"success": True}
```

### Bug F — get_booking_detail (thiếu fields)

```python
@app.get("/api/bookings/{booking_id}", tags=["Bookings"])
def get_booking_detail(booking_id: int):
    summary = execute("""
        SELECT
            b.id            AS booking_id,
            b.status,
            b.check_in,
            b.check_out,
            b.total_amount,
            b.amount_paid,
            (b.total_amount - b.amount_paid) AS balance,
            c.full_name     AS customer_name,
            c.phone_number  AS customer_phone,
            c.identity_card AS id_number,
            c.date_of_birth,
            STRING_AGG(DISTINCT rt.type_name, ', ') AS room_types,
            GREATEST((b.check_out::DATE - b.check_in::DATE), 1) AS nights
        FROM bookings b
        JOIN customers c   ON c.id  = b.customer_id
        JOIN booking_details bd ON bd.booking_id = b.id
        JOIN room_types rt ON rt.id = bd.room_type_id
        WHERE b.id = %s
        GROUP BY b.id, b.status, b.check_in, b.check_out,
                 b.total_amount, b.amount_paid,
                 c.full_name, c.phone_number, c.identity_card, c.date_of_birth
    """, (booking_id,), fetch="one")

    if not summary:
        raise HTTPException(status_code=404, detail="Booking không tồn tại.")

    surcharges  = execute("SELECT * FROM booking_surcharges WHERE booking_id = %s", (booking_id,), fetch="all")
    assignments = execute("""
        SELECT ra.*, r.room_number FROM room_assignments ra
        JOIN rooms r ON ra.room_id = r.id WHERE ra.booking_id = %s
    """, (booking_id,), fetch="all")
    services = execute("""
        SELECT su.*, s.name AS service_name, s.unit_price FROM service_usage su
        JOIN services s ON su.service_id = s.id WHERE su.booking_id = %s
    """, (booking_id,), fetch="all")

    return {
        **dict(summary),
        "surcharges":       surcharges   or [],
        "room_assignments": assignments  or [],
        "services":         services     or [],
    }
```

---

## 4. Schema mismatch — customers & staff

> [!WARNING]
> `main.py` dùng tên cột sai so với schema thực tế trong `HBMS_full_deployment.sql`.

| Vị trí | main.py dùng | Tên cột thực tế |
|---|---|---|
| `/api/customers/lookup` | `phone` | `phone_number` |
| `/api/customers/lookup` | `id_number` | `identity_card` |
| `/api/auth/login` | `username`, `password_hash` | **Không tồn tại** trong bảng `staff` |
| `/api/auth/login` | `full_name` | `name` |

**Fix customers/lookup:**
```python
result = execute(
    "SELECT id, full_name, phone_number, identity_card, date_of_birth FROM customers WHERE phone_number = %s",
    (body.phone,), fetch="one"
)
```

**Fix staff login** — cần ALTER TABLE thêm 2 cột:
```sql
-- Thêm vào HBMS_full_deployment.sql (sau CREATE TABLE staff)
ALTER TABLE staff ADD COLUMN IF NOT EXISTS username VARCHAR(50) UNIQUE;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
```

```python
# Sửa query login
result = execute(
    "SELECT id AS staff_id, name, role FROM staff WHERE username = %s AND password_hash = %s",
    (body.username, body.password),
    fetch="one"
)
```

---

## 5. Mock Data Script

> Tạo file: `DEMO/database/HBMS_mock_data.sql`

```sql
-- =============================================================
-- HBMS Mock Data — Demo toàn bộ flow
-- Chạy SAU HBMS_full_deployment.sql
-- =============================================================

-- 1. Hotel
INSERT INTO hotels (name, address, hotline) VALUES
  ('The Grand HBMS', '123 Lê Lợi, Q1, TP.HCM', '028-1234-5678');
-- id = 1

-- 2. Staff + login accounts
INSERT INTO staff (hotel_id, name, role, username, password_hash) VALUES
  (1, 'Nguyễn Admin', 'Admin', 'admin', 'admin123'),
  (1, 'Trần Lễ Tân',  'Staff', 'staff', 'staff123');
-- id: 1=Admin, 2=Staff

-- 3. Customers
INSERT INTO customers (full_name, phone_number, email, identity_card, date_of_birth) VALUES
  ('Phạm Văn An',     '0901111111', 'an@email.com',    '079201001111', '1990-05-15'),
  ('Lê Thị Bình',    '0902222222', 'binh@email.com',  '079201002222', '1985-08-20'),
  ('Hoàng Minh Cường','0903333333', 'cuong@email.com', '079201003333', '1992-03-10');
-- id: 1, 2, 3

-- 4. Surcharge Policies
INSERT INTO surcharge_policies (policy_type, description, multiplier, start_time, end_time) VALUES
  ('EarlyCheckIn', 'Check-in trước 9h (50%)',  0.50, '06:00', '09:00'),
  ('EarlyCheckIn', 'Check-in 9h–14h (30%)',    0.30, '09:00', '14:00'),
  ('LateCheckOut',  'Check-out 14h–18h (50%)',  0.50, '14:00', '18:00');

-- 5. Room Types
INSERT INTO room_types (hotel_id, type_name, base_price, max_capacity) VALUES
  (1, 'Standard',  800000, 2),
  (1, 'Deluxe',   1200000, 2),
  (1, 'Suite',    2500000, 4);
-- id: 1=Standard, 2=Deluxe, 3=Suite

-- 6. Rooms vật lý
INSERT INTO rooms (hotel_id, room_number, room_type_id, status) VALUES
  (1, '101', 1, 'Available'),
  (1, '102', 1, 'Available'),
  (1, '103', 1, 'Dirty'),
  (1, '201', 2, 'Available'),
  (1, '202', 2, 'Available'),
  (1, '301', 3, 'Available'),
  (1, '302', 3, 'Maintenance');
-- room_id: 101→1, 102→2, 103→3, 201→4, 202→5, 301→6, 302→7

-- 7. Services
INSERT INTO services (hotel_id, name, unit_price, category) VALUES
  (1, 'Bữa sáng buffet',   150000, 'Food'),
  (1, 'Giặt ủi (bộ)',       80000, 'Laundry'),
  (1, 'Spa 60 phút',        350000, 'Wellness'),
  (1, 'Thuê xe máy/ngày',   200000, 'Transport'),
  (1, 'Minibar',             50000, 'Food');

-- 8. Inventory (30 ngày từ hôm nay)
INSERT INTO room_type_inventory (room_type_id, date, total_inventory, total_reserved)
SELECT
    rt.id,
    d::DATE,
    CASE rt.type_name
        WHEN 'Standard' THEN 3
        WHEN 'Deluxe'   THEN 2
        WHEN 'Suite'    THEN 2
    END,
    0
FROM room_types rt
CROSS JOIN generate_series(CURRENT_DATE, CURRENT_DATE + 29, '1 day') d
WHERE rt.hotel_id = 1;

-- 9. Booking 1 — Active (Phạm Văn An, Standard, 2 đêm)
INSERT INTO bookings (hotel_id, customer_id, status, check_in, check_out, total_amount, amount_paid, idempotency_key)
VALUES (1, 1, 'Active',
        CURRENT_DATE + interval '2 days' + time '14:00',
        CURRENT_DATE + interval '4 days' + time '12:00',
        1600000, 500000, gen_random_uuid());

INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price, is_breakfast_included)
VALUES (1, 1, 1, 800000, FALSE);

UPDATE room_type_inventory SET total_reserved = total_reserved + 1
WHERE room_type_id = 1
  AND date BETWEEN CURRENT_DATE + 2 AND CURRENT_DATE + 3;

INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
VALUES (1, 1,
        CURRENT_DATE + interval '2 days' + time '14:00',
        CURRENT_DATE + interval '4 days' + time '12:00',
        FALSE);

-- 10. Booking 2 — Checked-in (Lê Thị Bình, Deluxe, đang ở)
INSERT INTO bookings (hotel_id, customer_id, status, check_in, check_out, total_amount, amount_paid, idempotency_key)
VALUES (1, 2, 'Checked-in',
        CURRENT_DATE - interval '1 day' + time '14:00',
        CURRENT_DATE + interval '2 days' + time '12:00',
        3600000, 1000000, gen_random_uuid());

INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price, is_breakfast_included)
VALUES (2, 2, 1, 1200000, TRUE);

UPDATE room_type_inventory SET total_reserved = total_reserved + 1
WHERE room_type_id = 2
  AND date BETWEEN CURRENT_DATE - 1 AND CURRENT_DATE + 1;

INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
VALUES (2, 4,
        CURRENT_DATE - interval '1 day' + time '14:00',
        CURRENT_DATE + interval '2 days' + time '12:00',
        FALSE);

UPDATE rooms SET status = 'Occupied' WHERE id = 4;

INSERT INTO service_usage (booking_id, service_id, quantity, used_at, staff_id)
VALUES (2, 1, 3, NOW(), 2),
       (2, 3, 1, NOW(), 2);

-- 11. Booking 3 — Completed + Paid (Hoàng Minh Cường)
INSERT INTO bookings (hotel_id, customer_id, status, check_in, check_out, total_amount, amount_paid, idempotency_key)
VALUES (1, 3, 'Completed',
        CURRENT_DATE - interval '5 days' + time '14:00',
        CURRENT_DATE - interval '2 days' + time '12:00',
        3600000, 3600000, gen_random_uuid());

INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price, is_breakfast_included)
VALUES (3, 1, 1, 800000,  FALSE),
       (3, 2, 1, 1200000, FALSE);

INSERT INTO invoices (booking_id, issued_by, total_amount, amount_paid, balance, status)
VALUES (3, 1, 3600000, 3600000, 0, 'Paid');
```

---

## 6. Cập nhật docker-compose.yml

```yaml
# Thay volumes của service db:
volumes:
  - pgdata:/var/lib/postgresql/data
  - ./database/HBMS_full_deployment.sql:/docker-entrypoint-initdb.d/01_init.sql
  - ./database/HBMS_mock_data.sql:/docker-entrypoint-initdb.d/02_mock.sql
```

> [!NOTE]
> PostgreSQL Docker chạy tất cả `.sql` trong `/docker-entrypoint-initdb.d/` theo thứ tự alphabet. Prefix `01_`, `02_` để đảm bảo thứ tự đúng.

**Reset và rebuild:**
```bash
docker compose down -v   # xóa volume cũ
docker compose up --build
```

---

## 7. Checklist Integration Frontend ↔ Backend

### `index.html`
- [ ] `POST /api/auth/login {username, password}` → lưu `{staff_id, name, role}` vào `sessionStorage`
- [ ] Redirect `calendar.html`
- [ ] **Cần:** ALTER TABLE staff thêm `username`, `password_hash`

### `calendar.html`
- [ ] `GET /api/calendar?start_date=&end_date=` → render Gantt blocks
- [ ] Hover highlight theo `booking_id` (JS thuần)
- [ ] Drag-drop → `POST /api/calendar/pre-assign {booking_id, room_id, staff_id}`
- [ ] Defragment → `POST /api/calendar/defragment?hotel_id=1&staff_id=1`
- [ ] Click block → `booking-detail.html?id={booking_id}`
- [ ] **Fix:** Bug B, Bug C

### `new-reservation.html`
- [ ] `GET /api/rooms/available?checkin=&checkout=` → list room types
- [ ] `POST /api/customers/lookup {phone}` → auto-fill
- [ ] `POST /api/bookings/begin` → nhận `booking_id`
- [ ] `POST /api/bookings/{id}/rooms` (multi room-type)
- [ ] `POST /api/bookings/{id}/finalize`
- [ ] **Fix:** Bug D, Fix `phone_number` alias

### `booking-detail.html`
- [ ] `GET /api/bookings/{id}` → render đầy đủ (status, check_in/out, customer info)
- [ ] State machine: ẩn/hiện nút theo `status`
- [ ] Check-in: dropdown chọn `room_id` Available → `POST checkin {room_id, staff_id}`
- [ ] Check-out: `POST checkout {staff_id}`
- [ ] Add Service: search → `POST services {service_id, quantity, staff_id}`
- [ ] Issue Invoice: `POST invoice {staff_id}`
- [ ] Record Payment: `POST payment {amount, staff_id}`
- [ ] Cancel: `POST cancel`
- [ ] **Fix:** Bug A, Bug E, Bug F

### `rooms.html`
- [ ] `GET /api/rooms/status` → grid cards theo trạng thái
- [ ] Filter dropdown (frontend)
- [ ] Click Occupied card → `booking-detail.html?id=`
- [ ] `POST /api/rooms/{id}/housekeeping?staff_id=1`

### `statistics.html`
- [ ] `GET /api/statistics` → `{daily_occupancy[], monthly_revenue[]}`
- [ ] Render KPI (Occupancy Rate, Revenue, ADR, Bookings)
- [ ] Heatmap calendar + bar chart doanh thu

---

## 8. Thứ tự thực hiện (4 Phase)

```
Phase 1 — Fix Schema
  ├── Thêm username + password_hash vào bảng staff
  └── Fix alias phone → phone_number, id_number → identity_card trong main.py

Phase 2 — Fix Stored Procedure Calls
  ├── Bug A: CheckInRequest thêm room_id
  ├── Bug B: PreAssignRequest thêm staff_id
  ├── Bug C: defragment endpoint thêm staff_id param
  ├── Bug D: finalize_booking bỏ staff_id
  ├── Bug E: record_payment bỏ payment_method
  └── Bug F: get_booking_detail JOIN trực tiếp

Phase 3 — Insert Mock Data
  ├── Tạo HBMS_mock_data.sql
  ├── Cập nhật docker-compose.yml (mount 02_mock.sql)
  └── docker compose down -v && docker compose up --build

Phase 4 — Integration Test qua /docs
  ├── Login → lấy staff_id
  ├── Tạo booking mới (begin → rooms → finalize)
  ├── Kiểm tra calendar hiện booking block
  ├── Check-in (chọn room_id)
  ├── Add service
  ├── Check-out → room Dirty
  ├── Housekeeping → room Available
  └── Xem statistics (occupancy + revenue)
```

---

## 9. Tổng hợp files cần tạo / sửa

| File | Hành động | Tóm tắt |
|---|---|---|
| `DEMO/backend/main.py` | **Sửa** | Fix Bug A–F |
| `DEMO/database/HBMS_full_deployment.sql` | **Sửa nhỏ** | Thêm `username`, `password_hash` vào `staff` |
| `DEMO/database/HBMS_mock_data.sql` | **Tạo mới** | Script mock data Section 5 |
| `DEMO/docker-compose.yml` | **Sửa** | Mount thêm `02_mock.sql` |
