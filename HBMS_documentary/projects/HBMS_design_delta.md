# HBMS — Danh sách chỉnh sửa thiết kế
*Đối chiếu: Đặc tả + Kiến trúc + Tính năng → sau khi áp lời khuyên db hotel*

---

## Cách đọc file này

- **[THÊM]** — thứ chưa có trong thiết kế, cần bổ sung
- **[SỬA]** — thứ đã có nhưng cần chỉnh lại
- **[GHI BÁO CÁO]** — không cần implement, nhưng phải viết lý do vào báo cáo
- **[BỎ]** — thứ nên loại khỏi scope để tránh over-engineer

Ưu tiên: **P1** (bắt buộc) → **P2** (nên làm) → **P3** (điểm cộng)

---

## 1. Schema — Thay đổi cấu trúc bảng

### [SỬA] P1 — Tách luồng đặt phòng thành 2 pha

**Vấn đề hiện tại:** `Booking_Details` liên kết thẳng `BookingID → RoomID` (phòng vật lý cụ thể).
Điều này khiến EXCLUDE CONSTRAINT phải hoạt động từ lúc đặt, và không xử lý được đổi phòng do bảo trì.

**Sửa thành mô hình Hybrid:**

```
Pha 1 — Đặt phòng (Reservation):
  Booking_Details: BookingID → RoomTypeID (loại phòng, không phải phòng cụ thể)
  → Kiểm tra số lượng còn trống qua room_type_inventory

Pha 2 — Check-in (Assignment):
  Room_Assignments: BookingID → RoomID (phòng vật lý cụ thể)
  → EXCLUDE CONSTRAINT đặt ở đây, không phải ở Booking_Details
```

**Bảng cần thêm:**

```sql
-- Bảng đếm tồn kho theo ngày
room_type_inventory (
    room_type_id   INT,
    date           DATE,
    total_inventory INT,   -- tổng số phòng loại này
    total_reserved  INT,   -- đã đặt
    -- CHECK: total_reserved <= total_inventory
    PRIMARY KEY (room_type_id, date)
)

-- Bảng gán phòng cụ thể lúc check-in
room_assignments (
    id            SERIAL PRIMARY KEY,
    booking_id    INT REFERENCES bookings(id),
    room_id       INT REFERENCES rooms(id),
    assigned_at   TIMESTAMP DEFAULT NOW(),
    -- EXCLUDE CONSTRAINT chống trùng lịch đặt ở đây
    EXCLUDE USING gist (
        room_id WITH =,
        daterange(check_in, check_out, '[)') WITH &&
    )
)
```

---

### [THÊM] P1 — ON DELETE behavior cho tất cả FK

File đặc tả hiện tại định nghĩa FK nhưng không nói `ON DELETE` làm gì.
Đây là lỗ hổng Consistency nghiêm trọng.

| FK | Hành vi đúng | Lý do |
|---|---|---|
| `Booking_Details → Bookings` | `ON DELETE CASCADE` | Xóa đơn thì xóa luôn chi tiết |
| `Booking_Details → Room_Types` | `ON DELETE RESTRICT` | Không cho xóa loại phòng còn booking |
| `Rooms → Room_Types` | `ON DELETE RESTRICT` | Không xóa loại phòng còn phòng vật lý |
| `Service_Usage → Bookings` | `ON DELETE CASCADE` | Dịch vụ gắn với đơn, đơn mất thì mất theo |
| `Invoices → Bookings` | `ON DELETE RESTRICT` | Không xóa đơn đã có hóa đơn |

---

### [THÊM] P1 — Soft Delete cho Bookings

**Vấn đề:** File đặc tả không nói rõ hủy booking thì làm gì với dòng data.

**Sửa:** Không bao giờ `DELETE` từ bảng `Bookings`. Thêm:

```sql
ALTER TABLE bookings ADD COLUMN status VARCHAR(20) 
    CHECK (status IN ('Pending', 'Active', 'Checked-in', 'Completed', 'Cancelled'));

ALTER TABLE bookings ADD COLUMN cancelled_at TIMESTAMP;
ALTER TABLE bookings ADD COLUMN cancel_reason TEXT;
```

EXCLUDE CONSTRAINT trên `Room_Assignments` thêm điều kiện `WHERE (status != 'Cancelled')` để booking đã hủy không chiếm slot.

---

### [THÊM] P2 — Audit fields trên các bảng core

Thêm vào `Bookings`, `Rooms`, `Room_Types`, `Invoices`:

```sql
created_at   TIMESTAMP DEFAULT NOW(),
updated_at   TIMESTAMP DEFAULT NOW(),
updated_by   INT REFERENCES staff(id)   -- ai sửa lần cuối
```

Thêm trigger tự động cập nhật `updated_at`:

```sql
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;
```

---

### [THÊM] P3 — Idempotency Key cho Bookings

Tránh trường hợp user bấm "Đặt phòng" 2 lần tạo 2 đơn:

```sql
ALTER TABLE bookings ADD COLUMN idempotency_key UUID UNIQUE;
```

Application sinh `UUID` trước khi gọi API — nếu gửi lại với cùng key thì trả về đơn cũ thay vì tạo mới.

---

## 2. Constraints — Thay đổi vị trí và loại ràng buộc

### [SỬA] P1 — Di chuyển EXCLUDE CONSTRAINT

**Hiện tại (thiết kế cũ):** EXCLUDE đặt trên `Booking_Details` (link BookingID → RoomID).

**Sau khi đổi sang Hybrid:** EXCLUDE đặt trên `Room_Assignments` (chỉ hoạt động từ lúc Check-in).

Giai đoạn Reservation kiểm tra tồn kho qua `room_type_inventory`, không dùng EXCLUDE.

---

### [THÊM] P1 — CHECK CONSTRAINT cho room_type_inventory

```sql
ALTER TABLE room_type_inventory
    ADD CONSTRAINT no_overbook
    CHECK (total_reserved <= total_inventory);
```

Nếu muốn cho phép overbooking 10% (tùy chọn P3):
```sql
CHECK (total_reserved <= FLOOR(total_inventory * 1.1))
```

---

### [SỬA] P2 — EXCLUDE CONSTRAINT thêm điều kiện lọc status

Booking đã hủy không được chiếm slot:

```sql
EXCLUDE USING gist (
    room_id WITH =,
    daterange(check_in, check_out, '[)') WITH &&
) WHERE (status != 'Cancelled')   -- thêm dòng này
```

---

## 3. Triggers — Thay đổi logic

### [SỬA] P1 — Trigger snapshot giá lấy từ đâu

**Hiện tại:** Trigger lấy giá từ `Room_Types.base_price`.

**Vấn đề:** Hệ thống có bảng `Price_Policies` (giá theo mùa/ngày lễ) nhưng trigger chưa dùng.

**Sửa logic trigger:**
```
agreed_price = giá trong Price_Policies nếu có policy cho ngày check_in
             = Room_Types.base_price nếu không có policy nào
```

---

### [THÊM] P2 — Trigger cập nhật room_type_inventory

Khi INSERT vào `Booking_Details` (đặt loại phòng):
```sql
UPDATE room_type_inventory
SET total_reserved = total_reserved + 1
WHERE room_type_id = NEW.room_type_id
  AND date BETWEEN NEW.check_in AND NEW.check_out - 1;
```

Khi booking bị hủy (UPDATE status = 'Cancelled'):
```sql
UPDATE room_type_inventory
SET total_reserved = total_reserved - 1
WHERE ...;
```

---

### [THÊM] P2 — Trigger State Machine đầy đủ

File đặc tả có nhắc State Machine nhưng chưa liệt kê transition hợp lệ.

```
Available  → Occupied    (Check-in)         ✓ hợp lệ
Available  → Maintenance (Admin set)        ✓ hợp lệ
Occupied   → Dirty       (Check-out)        ✓ hợp lệ
Dirty      → Available   (Housekeeping xong) ✓ hợp lệ
Maintenance→ Available   (Admin set)        ✓ hợp lệ

Dirty      → Occupied    (Check-in thẳng)   ✗ CHẶN
Maintenance→ Occupied    (Check-in thẳng)   ✗ CHẶN
```

Trigger BEFORE UPDATE kiểm tra transition có nằm trong whitelist không, nếu không thì RAISE EXCEPTION.

---

## 4. Views / Materialized Views — Thêm mới

### [THÊM] P2 — Các View cần có cho Dashboard

File kiến trúc nhắc đến Materialized View nhưng chưa định nghĩa cụ thể là view gì.

| Tên View | Trả lời câu hỏi | Loại |
|---|---|---|
| `v_room_occupancy` | Tỷ lệ lấp đầy theo khách sạn/tháng | Materialized View |
| `v_revenue_by_month` | Doanh thu theo tháng | Materialized View |
| `v_popular_room_types` | Loại phòng được đặt nhiều nhất | View thường |
| `v_active_bookings` | Booking đang active + thông tin phòng | View thường |

Materialized View cần `REFRESH MATERIALIZED VIEW` — có thể schedule bằng `pg_cron` hoặc refresh thủ công sau mỗi đêm.

---

## 5. Stored Procedure — Bổ sung

### [SỬA] P1 — Procedure đặt phòng cần update lại flow

Flow cũ: INSERT Booking → INSERT Booking_Details (RoomID)

Flow mới:
```
BEGIN TRANSACTION
  1. Kiểm tra room_type_inventory còn trống không
  2. INSERT Booking
  3. INSERT Booking_Details (RoomTypeID, không phải RoomID)
  4. UPDATE room_type_inventory: total_reserved + số đêm
COMMIT
```

---

## 6. Kiến trúc — Chỉ cần ghi vào báo cáo

### [GHI BÁO CÁO] P2

| Quyết định kiến trúc | Lý do cần ghi |
|---|---|
| Partitioning bảng `Bookings` theo tháng | Lịch sử đặt phòng tích lũy theo năm, query chủ yếu theo tháng gần |
| Master-Slave Replication | Tỷ lệ Search >> Booking, cần tách read replica |
| Row-Level Security | Hệ thống cho nhiều khách sạn thuê chung 1 DB |
| Không implement Redis | Scope đồ án, nhưng trong thực tế dùng cho Soft Lock TTL |

---

## Tóm tắt theo thứ tự làm

```
P1 — Làm ngay (ảnh hưởng core design):
  □ Thêm bảng room_type_inventory + room_assignments
  □ Di chuyển EXCLUDE CONSTRAINT sang room_assignments
  □ Sửa Booking_Details: RoomTypeID thay vì RoomID
  □ Bổ sung ON DELETE behavior cho tất cả FK
  □ Thêm status + soft delete cho Bookings
  □ Sửa Stored Procedure theo flow mới

P2 — Làm sau khi P1 ổn định:
  □ Sửa Trigger snapshot giá dùng Price_Policies
  □ Thêm Trigger cập nhật room_type_inventory
  □ Thêm Trigger State Machine với whitelist
  □ Thêm audit fields + trigger updated_at
  □ Tạo 4 View/Materialized View
  □ Viết phần kiến trúc vào báo cáo

P3 — Điểm cộng nếu còn thời gian:
  □ Idempotency key
  □ Overbooking CHECK (110%)
  □ pg_cron schedule refresh Materialized View
```
