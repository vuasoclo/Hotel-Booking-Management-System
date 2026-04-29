# HBMS — Phân tích `new-reservation.html`: Hiện trạng, Lỗi & Kế hoạch sửa

> **Phạm vi:** Tính năng tạo booking mới (new-reservation.html) và toàn bộ luồng từ Search → Book Now → hiển thị Calendar.
> **Rule:** Không thay đổi DB nếu không xin phép. Logic nghiệp vụ xử lý ở Backend & Frontend.

---

## 1. Sơ đồ luồng hiện tại vs mục tiêu

```
[HIỆN TẠI — bị broken]
Search → Select Rooms → Proceed → Fill Guest → Book Now
  ├─ POST /api/bookings/begin          (tạo booking Pending) ✅
  ├─ POST /api/bookings/{id}/rooms × N (add_room_detail)     ✅
  ├─ POST /api/bookings/{id}/services  (service_usage)       ✅
  └─ POST /api/bookings/{id}/finalize  (→ Active)            ✅
                                        ↑ DỪNG TẠI ĐÂY
                                        Không có room_assignments
                                        → Booking tạo xong nhưng invisible trên Calendar

[MỤC TIÊU]
Book Now → 1 transaction duy nhất trên backend:
  1. begin_booking()
  2. add_room_detail_to_booking() × types
  3. (breakfast) INSERT booking_surcharges × types có breakfast
  4. finalize_booking()
  5. auto_assign_rooms() — tìm phòng vật lý + INSERT room_assignments
     └─ Nếu không đủ phòng thực tế → ROLLBACK toàn bộ → trả lỗi 409
  → Redirect calendar.html ✅
```

---

## 2. Kiểm tra DB Objects liên quan

| DB Object | Loại | Dùng cho | Hiện trạng |
|---|---|---|---|
| `search_available_rooms()` | Function | Search phòng trống theo inventory | ✅ Đủ |
| `customers` | Table | Lookup khách theo SĐT | ✅ Đủ cho lookup; ❌ Không có create |
| `begin_booking()` | Function | Tạo booking Pending | ✅ Đủ |
| `add_room_detail_to_booking()` | Procedure | Gắn room_type + lock inventory | ✅ Đủ — nhưng xem Lỗi #1 |
| `set_agreed_price()` | Trigger | Snapshot giá khi insert booking_details | ✅ Đủ |
| `finalize_booking()` | Procedure | Chuyển Pending → Active | ✅ Đủ |
| `apply_time_surcharges()` | Function | Tính phụ thu giờ | ✅ Tự động trong finalize |
| `recalculate_booking_total()` | Function | Tính lại total_amount | ✅ Tự động qua trigger |
| `booking_surcharges` | Table | Lưu phụ thu (incl. breakfast) | ✅ Có thể dùng cho breakfast |
| `room_assignments` | Table | Gán phòng vật lý | ❌ **Không được gọi trong Book Now** |
| `rooms` | Table | Danh sách phòng vật lý | ✅ Sẵn để query |
| `v_calendar` | View | Hiển thị Calendar | ✅ Đủ — nhưng phụ thuộc room_assignments |
| `service_usage` | Table | Thêm dịch vụ | ✅ Đủ |
| `tetrisroom_defrag()` | Procedure | Tối ưu phân bổ phòng | ⚠️ Không dùng ở đây (batch, không atomic) |

---

## 3. Phân tích Lỗi chi tiết

---

### Lỗi #1 — Breakfast không được tính tiền

**Nguồn gốc (DB):**
- `booking_details.agreed_price` được set bởi trigger `set_agreed_price()` → luôn = `base_price` từ `room_types`
- `add_room_detail_to_booking()` hardcode `agreed_price = 0` → trigger bắt và thay bằng `base_price`
- `recalculate_booking_total()` tính: `SUM(agreed_price × quantity × nights)` — **không có thành phần breakfast**
- `apply_time_surcharges()` chỉ xử lý `EarlyCheckIn` / `LateCheckOut`
- **Không có cột `breakfast_price` nào trong `room_types` hay bất kỳ bảng nào**

**Nguồn gốc (Frontend):**
- `renderSelectedRooms()`: `roomTotalCost += r.subtotal` — subtotal = `price × qty × nights`, không cộng breakfast
- `updateTotal()`: chỉ hiển thị `roomTotalCost + serviceTotalCost`

**Hậu quả:**
- Checkbox "+ Breakfast" tick hay không → giá preview và giá DB đều như nhau
- Khách check-out, `check_out_booking()` cũng tính sai do `booking_surcharges` không có dòng breakfast

**Fix — Không thay đổi DB:**

*Backend (khi xử lý `/api/bookings/{id}/rooms` hoặc trong endpoint tổng hợp):*
```
Sau khi gọi add_room_detail_to_booking(booking_id, room_type_id, quantity, is_breakfast):
  IF is_breakfast_included = TRUE:
    breakfast_price = lookup từ bảng services WHERE name ILIKE '%breakfast%' LIMIT 1
    -- Hoặc config cứng trong backend nếu chưa có service Breakfast
    nights = (check_out::DATE - check_in::DATE)
    surcharge_amount = breakfast_price × quantity × nights
    INSERT INTO booking_surcharges
      (booking_id, surcharge_type, amount, description)
    VALUES
      (booking_id, 'Other', surcharge_amount,
       'Breakfast — ' || room_type_name || ' × ' || quantity || ' room(s) × ' || nights || ' night(s)')
    -- recalculate_booking_total() tự kích hoạt qua trigger trên booking_surcharges? 
    -- KHÔNG — trigger sync_total_amount chỉ watch service_usage
    -- Phải gọi PERFORM recalculate_booking_total(booking_id) sau khi INSERT surcharges
```

> **Lưu ý:** trigger `sync_total_amount` chỉ được đặt trên bảng `service_usage`, KHÔNG phải `booking_surcharges`. Vì vậy sau khi INSERT vào `booking_surcharges`, backend phải tự gọi `SELECT recalculate_booking_total(booking_id)`.

*Frontend (`addRoom` và `renderSelectedRooms`):*
```javascript
// Cần truyền breakfastPrice vào addRoom
window.addRoom = function(typeId, typeName, price, maxAvail, breakfastPrice) {
  const isBreakfast = document.getElementById(`breakfast-${typeId}`).checked;
  const effectivePrice = isBreakfast ? price + breakfastPrice : price;
  // dùng effectivePrice để tính subtotal trong preview
  ...
}
```
> Breakfast price phải được truyền từ backend về trong response của `search_available_rooms` hoặc lookup riêng từ `/api/services/search?q=breakfast`.

---

### Lỗi #2 — Có thể Add quá số phòng tìm được

**Nguồn gốc (Frontend — `addRoom()`):**
```javascript
// BUG: find theo (typeId, isBreakfast) — không gộp tất cả variants của cùng typeId
const existing = selectedRooms.find(r => r.typeId === typeId && r.isBreakfast === isBreakfast);
if (existing) {
  if (existing.qty >= maxAvail) { ... return; }  // ← chỉ check qty của 1 variant
  existing.qty++;
}
```

**Ví dụ lỗi:** `maxAvail = 1` với Deluxe Room.
- User click "+ Add" Deluxe (no breakfast) → qty=1, check pass ✅
- User tick breakfast, click "+ Add" Deluxe (with breakfast) → **new entry** → qty=1, pass ✅  
- Kết quả: 2 entries × Deluxe, tổng qty = 2 > maxAvail = 1 ❌

**Fix — Frontend:**
```javascript
window.addRoom = function(typeId, typeName, price, maxAvail) {
  // Tổng qty hiện tại của typeId này (mọi variants)
  const totalQtyForType = selectedRooms
    .filter(r => r.typeId === typeId)
    .reduce((sum, r) => sum + r.qty, 0);

  if (totalQtyForType >= maxAvail) {
    alert(`Chỉ còn ${maxAvail} phòng loại ${typeName} trống trong khoảng thời gian này.`);
    return;
  }
  // ... tiếp tục như cũ
};
```

---

### Lỗi #3 — Không assign phòng vật lý sau Book Now *(lỗi nghiêm trọng nhất)*

**Nguồn gốc:**
- `finalize_booking()` chỉ: `UPDATE bookings SET status='Active'` + `apply_time_surcharges()`
- Không có bước nào INSERT vào `room_assignments`
- `v_calendar` query: `LEFT JOIN room_assignments ra ON ra.room_id = r.id AND ra.is_cancelled = FALSE` → **booking không có assignment sẽ không hiện trên calendar**

**Fix — Backend (trong endpoint finalize hoặc endpoint tổng hợp):**

Sau khi `finalize_booking()` thành công, backend thực hiện auto-assign trong cùng transaction:

```sql
-- Lặp qua từng booking_detail
FOR EACH detail IN (
  SELECT room_type_id, quantity FROM booking_details WHERE booking_id = :booking_id
):
  -- Lặp quantity lần để assign từng phòng riêng lẻ
  FOR i IN 1..detail.quantity:
    room_id = SELECT r.id
              FROM rooms r
              WHERE r.room_type_id = detail.room_type_id
                AND r.hotel_id = :hotel_id
                AND r.id NOT IN (:already_assigned_in_this_loop)
                AND NOT EXISTS (
                  SELECT 1 FROM room_assignments ra
                  WHERE ra.room_id = r.id
                    AND ra.is_cancelled = FALSE
                    AND tsrange(ra.check_in, ra.check_out, '[)')
                     && tsrange(:check_in, :check_out, '[)')
                )
              ORDER BY r.room_number
              LIMIT 1

    IF room_id IS NULL:
      RAISE / Return 409 Conflict: "Không đủ phòng [type] để phân bổ"
      -- Backend ROLLBACK toàn bộ transaction
      
    INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
    VALUES (:booking_id, room_id, :check_in, :check_out, FALSE)
    
    already_assigned.append(room_id)
```

> **Quan trọng:** bảng `room_assignments` đã có EXCLUDE constraint (`exclude_overlapping_assignments`) chống overlap cho cùng phòng. Tuy nhiên query thủ công vẫn cần thiết để tìm phòng trống trước khi INSERT, tránh lỗi từ constraint.

---

### Lỗi #4 — Không có atomic rollback khi flow bị gián đoạn

**Nguồn gốc — Frontend gọi 3 endpoint riêng rẽ:**
```javascript
// Nếu step 2 (rooms) fail, booking Pending vẫn tồn tại trong DB → rác
// Nếu step 3 (finalize) fail, booking Pending + inventory đã bị lock → rác
await fetch('/api/bookings/begin')      // bước 1
await fetch('/api/bookings/{id}/rooms') // bước 2 — nếu lỗi ở đây
await fetch('/api/bookings/{id}/finalize') // bước 3
```

**Fix — Backend:** Gộp toàn bộ luồng vào **1 endpoint duy nhất** hoặc 1 DB transaction:

```
POST /api/bookings/create
Body: {
  hotel_id, customer_id, check_in, check_out,
  idempotency_key,
  rooms: [ { room_type_id, quantity, is_breakfast_included } ],
  services: [ { service_id, quantity } ],
  staff_id
}

Backend xử lý trong 1 transaction:
  1. begin_booking()
  2. add_room_detail_to_booking() × rooms
  3. [breakfast] INSERT booking_surcharges, recalculate_booking_total()
  4. [services] INSERT service_usage × services
  5. finalize_booking()
  6. auto_assign_rooms() — nếu fail → ROLLBACK toàn bộ → HTTP 409
  COMMIT → HTTP 201 { booking_id }

Frontend chỉ gọi 1 request → đơn giản hơn, không rủi ro partial state.
```

> **Frontend hiện tại vẫn có thể giữ 3-step API** nếu backend cũ cần tương thích, nhưng phải bổ sung cleanup: nếu bước nào fail thì gọi `DELETE /api/bookings/{id}` (cancel) để dọn Pending booking. Tuy nhiên việc gộp vào 1 endpoint sạch hơn nhiều.

---

### Lỗi phụ #5 — Không tạo được khách hàng mới

**Hiện trạng:** Nếu `POST /api/customers/lookup` không tìm thấy → frontend alert "Backend chưa hỗ trợ tạo mới" → `currentGuestId = null` → nút Book Now disabled mãi.

**Fix — Backend:** Thêm endpoint `POST /api/customers` với body:
```json
{
  "full_name": "...",
  "phone_number": "...",
  "identity_card": "...",
  "date_of_birth": "YYYY-MM-DD"
}
```
INSERT INTO customers, trả về `customer_id`.

**Fix — Frontend:** Khi lookup trả 404, hiện form tạo mới inline (hiện tại `guest-dob` đang bị `d-none`, cần bỏ ẩn) và gọi endpoint tạo mới.

> ⚠️ Lưu ý: bảng `customers` có constraint `chk_customer_age` (≥ 18 tuổi). Frontend cần validate DOB trước khi submit.

---

## 4. Tổng hợp: Cần làm gì ở đâu?

| # | Lỗi | Layer sửa | Cần thay đổi DB? |
|---|---|---|---|
| 1 | Breakfast không tính tiền | **Backend** (INSERT booking_surcharges + gọi recalculate) + **Frontend** (preview price) | ❌ Không (dùng booking_surcharges sẵn có) |
| 2 | Add quá số phòng available | **Frontend** (aggregated qty check) | ❌ Không |
| 3 | Không assign phòng vật lý | **Backend** (auto_assign sau finalize, cùng transaction) | ❌ Không (INSERT room_assignments trực tiếp) |
| 4 | Không rollback khi fail | **Backend** (gộp vào 1 transaction/endpoint) | ❌ Không |
| 5 | Không tạo khách mới | **Backend** (endpoint POST /api/customers) + **Frontend** | ❌ Không |

**→ Không cần thay đổi DB cho bất kỳ lỗi nào ở trên.**

---

## 5. Đề xuất xin phép thay đổi DB (tùy chọn, tăng chất lượng)

Các thay đổi dưới đây **không bắt buộc** nhưng sẽ làm hệ thống sạch hơn:

### 5a. Thêm cột `breakfast_price` vào `room_types`
```sql
-- XIN PHÉP trước khi chạy
ALTER TABLE room_types ADD COLUMN breakfast_price DECIMAL(10,2) NOT NULL DEFAULT 0;
```
**Lý do:** Hiện tại breakfast price phải lookup từ `services` table (fragile, có thể không có service "Breakfast") hoặc hardcode. Có cột riêng trong `room_types` sẽ rõ ràng, dễ quản lý và `search_available_rooms` có thể trả về luôn giá breakfast.

**Ảnh hưởng:** Phải update `search_available_rooms()` để trả thêm `breakfast_price`. Không phá vỡ trigger hay procedure hiện tại.

---

### 5b. Thêm trigger `sync_total_on_surcharge` trên `booking_surcharges`
```sql
-- XIN PHÉP trước khi chạy
DROP TRIGGER IF EXISTS trg_sync_total_on_surcharge ON booking_surcharges;
CREATE TRIGGER trg_sync_total_on_surcharge
AFTER INSERT OR UPDATE OR DELETE ON booking_surcharges
FOR EACH ROW EXECUTE FUNCTION sync_total_amount();
```
**Lý do:** Hiện trigger `sync_total_amount` chỉ watch `service_usage`. Khi backend INSERT vào `booking_surcharges` (cho breakfast), phải tự gọi `recalculate_booking_total()` thủ công. Nếu có trigger này, total_amount sẽ tự cập nhật, giảm nguy cơ quên.

**Ảnh hưởng:** Không phá vỡ gì. Cần đảm bảo `sync_total_amount` function hoạt động đúng với `booking_surcharges` (hiện nó dùng `booking_id` field — ✅ có sẵn trong `booking_surcharges`).

> Tuy nhiên `sync_total_amount` dùng `NEW.booking_id` / `OLD.booking_id` — cần kiểm tra function body hiện tại có xử lý đúng cho bảng ngoài `service_usage` không. Nếu function hardcode logic `service_usage` thì phải refactor trước.

---

### 5c. Stored Procedure `auto_assign_rooms(p_booking_id INT)` 
```sql
-- XIN PHÉP trước khi chạy
CREATE OR REPLACE PROCEDURE auto_assign_rooms(p_booking_id INT)
-- Logic: loop booking_details, với mỗi room_type × quantity, tìm phòng trống và INSERT room_assignments
-- Raise nếu không đủ phòng (sẽ trigger rollback từ caller)
```
**Lý do:** Đóng gói logic assign vào DB, tái sử dụng được từ cả backend API lẫn `tetrisroom_defrag` (sau này). Hiện `tetrisroom_defrag` cũng chỉ assign 1 phòng per booking_detail (không xử lý quantity > 1).

---

## 6. Thứ tự ưu tiên triển khai

```
Ưu tiên 1 (block calendar — phải làm trước):
  └─ Lỗi #3: Auto-assign rooms trong backend (1 transaction)
  └─ Lỗi #4: Gộp thành 1 endpoint /api/bookings/create

Ưu tiên 2 (sai nghiệp vụ):
  └─ Lỗi #1: Breakfast pricing — Backend + Frontend
  └─ Lỗi #2: Qty cap — Frontend

Ưu tiên 3 (UX):
  └─ Lỗi #5: Tạo khách hàng mới — Backend + Frontend

Tùy chọn (sau khi xin phép):
  └─ 5a: breakfast_price column
  └─ 5b: trigger sync surcharge
  └─ 5c: auto_assign_rooms procedure
```

---

## 7. Cấu trúc endpoint mới đề xuất

```
POST /api/bookings/create
──────────────────────────
Request Body:
{
  "hotel_id": 1,
  "customer_id": 42,
  "check_in": "2026-05-01 14:00:00",
  "check_out": "2026-05-03 12:00:00",
  "idempotency_key": "uuid-v4",
  "rooms": [
    { "room_type_id": 2, "quantity": 2, "is_breakfast_included": true },
    { "room_type_id": 3, "quantity": 1, "is_breakfast_included": false }
  ],
  "services": [
    { "service_id": 5, "quantity": 1 }
  ],
  "staff_id": 1
}

Response 201:
{ "booking_id": 123 }

Response 409 (không đủ phòng vật lý):
{ "error": "ROOM_ASSIGN_FAILED", "detail": "Không đủ phòng Deluxe để phân bổ (cần 2, còn 1)" }

Response 409 (overbooking inventory):
{ "error": "OVERBOOKING", "detail": "Không đủ phòng loại 2 ngày 2026-05-02 (Còn: 0)" }
```

> **Frontend update:** Thay 3 fetch() bằng 1 fetch duy nhất tới `/api/bookings/create`, xử lý response 201 → redirect calendar, response 4xx → hiện lỗi inline (không dùng alert).