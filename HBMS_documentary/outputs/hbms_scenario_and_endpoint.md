# HBMS — Kịch bản vận hành & Đối chiếu SQL

---

## Tổng quan: 5 file HTML
```
calendar.html        → Theo dõi tổng thể
new-reservation.html → Tạo booking mới
booking-detail.html  → Vận hành booking (check-in → check-out → thanh toán)
rooms.html           → Quản lý trạng thái phòng & housekeeping
statistics.html      → Báo cáo doanh thu & công suất
```

---

## Kịch bản vận hành từng View

### 1. `calendar.html` — Bảng điều khiển tổng thể

**Mô tả:** Màn hình chính lễ tân nhìn vào mỗi sáng. Hiển thị tất cả booking theo dạng Gantt ngang (phòng × ngày).

**Có thể làm:**
- Xem toàn bộ booking trong khoảng ngày (block màu xanh dương = Active, xanh lam = Checked-in)
- Kéo thả block để gán lại phòng cụ thể (`pre_assign_room`)
- Bấm nút **Defragment** để tối ưu tự động việc phân bổ phòng (`tetrisroom_defrag`)
- **Double-click** vào block → điều hướng sang `booking-detail.html?id=xxx`
- Bấm **+ New Reservation** trên sidebar → `new-reservation.html`

**Không làm được:** Xem trạng thái vật lý phòng (Dirty/Maintenance) — đó là của `rooms.html`.

---

### 2. `new-reservation.html` — Tạo đặt phòng mới

**Mô tả:** Luồng 2 bước để tạo một booking.

**Có thể làm:**
- **Bước 1:** Nhập ngày check-in/check-out → tìm kiếm phòng còn trống
  - Hiển thị cảnh báo phụ thu nếu check-in trước 14:00 (Early Check-in)
  - Chọn loại phòng + số lượng + có/không bữa sáng (`is_breakfast_included`)
- **Bước 2 (panel phải):** Nhập thông tin khách (phone → lookup → auto-fill nếu đã có)
  - Thêm dịch vụ kèm theo lúc đặt phòng
  - Xem tổng chi phí preview
  - Bấm **Book Now** để hoàn tất

**Luồng SQL:** `begin_booking()` → `add_room_detail_to_booking()` → `finalize_booking()` → `apply_time_surcharges()`

---

### 3. `booking-detail.html` — Trung tâm vận hành booking

**Mô tả:** 1 màn hình xử lý toàn bộ vòng đời sau khi booking được tạo. Nút bấm tự động thay đổi theo trạng thái.

**State machine (Action Bar thay đổi theo status):**

| Status | Nút hiển thị |
|---|---|
| `Active` | [Cancel] · [Issue Invoice] · [Record Payment] · **[Check-in]** |
| `Checked-in` | [+ Add Service] (không ở taskbar mà service) · [Issue Invoice] · [Record Payment] · **[Check-out]** |
| `Completed` | [Issue Invoice] · **[Completed]** (disabled) |
| `Cancelled` | Tất cả ẩn, badge đỏ Cancelled |

**Có thể làm:**
- Xem thông tin khách (tên, SĐT, CMND, DOB)
- Xem chi tiết lưu trú (ngày, số đêm, danh sách phòng gán)
- Xem Cost Breakdown (accordion: Rooms / Surcharges / Services) + Total / Paid / Balance
- Xem bảng dịch vụ đã dùng
- **[Check-in]** → `check_in_booking()` — chỉ khi Active
- **[Check-out]** → `check_out_booking()` — chỉ khi Checked-in
- **[+ Add Service]** → modal search + add → `service_usage INSERT` — chỉ khi Checked-in
- **[Issue Invoice]** → modal preview → `issue_invoice()` — Active/Checked-in/Completed
- **[Record Payment]** → modal amount + method → `record_payment()` — Active/Checked-in/Completed
- **[Cancel Booking]** → `UPDATE status='Cancelled'` — chỉ khi Active

---

### 4. `rooms.html` — Bảng trạng thái phòng

**Mô tả:** Grid card tất cả phòng, nhóm theo loại. Dành cho quản lý buồng phòng.

**Có thể làm:**
- Xem trạng thái vật lý thực tế từng phòng: Available / Occupied / Dirty / Maintenance
- Filter theo trạng thái (dropdown)
- Xem tóm tắt số lượng từng trạng thái (summary bar)
- **Click vào card Occupied** → điều hướng sang `booking-detail.html?id=xxx`
- **[✓ Clean]** trên card Dirty → `housekeeping_complete()` → phòng trở lại Available

---

### 5. `statistics.html` — Báo cáo

**Mô tả:** Dashboard số liệu cho quản lý.

**Có thể làm:**
- Xem KPI cards: Occupancy Rate, Total Revenue, Bookings Count, ADR
- Xem Heatmap công suất theo ngày (từ `v_daily_occupancy`)
- Xem biểu đồ doanh thu theo tháng: Room Cost / Surcharges / Services (từ `v_monthly_revenue`)

---

## Toàn bộ API Endpoints (19 endpoints)

| # | Method | Endpoint | SQL Object | View gọi |
|---|---|---|---|---|
| 1 | GET | `/api/calendar` | `v_calendar` | calendar.html |
| 2 | POST | `/api/calendar/defragment` | `tetrisroom_defrag()` | calendar.html |
| 3 | POST | `/api/calendar/pre-assign` | `pre_assign_room()` | calendar.html (drag) |
| 4 | GET | `/api/rooms/available?checkin=&checkout=` | `search_available_rooms()` | new-reservation.html |
| 5 | POST | `/api/customers/lookup` | SELECT FROM customers WHERE phone | new-reservation.html |
| 6 | POST | `/api/bookings/begin` | `begin_booking()` | new-reservation.html |
| 7 | POST | `/api/bookings/{id}/rooms` | `add_room_detail_to_booking()` | new-reservation.html |
| 8 | POST | `/api/bookings/{id}/finalize` | `finalize_booking()` | new-reservation.html |
| 9 | GET | `/api/services/search?q=` | SELECT FROM services | new-reservation.html |
| 10 | POST | `/api/bookings/{id}/services` | INSERT INTO service_usage | new-reservation.html + booking-detail.html |
| 11 | GET | `/api/bookings/{id}` | `v_booking_summary` + surcharges + assignments | booking-detail.html |
| 12 | POST | `/api/bookings/{id}/checkin` | `check_in_booking()` | booking-detail.html |
| 13 | POST | `/api/bookings/{id}/checkout` | `check_out_booking()` | booking-detail.html |
| 14 | POST | `/api/bookings/{id}/cancel` | UPDATE bookings SET status='Cancelled' | booking-detail.html |
| 15 | POST | `/api/bookings/{id}/invoice` | `issue_invoice()` | booking-detail.html |
| 16 | POST | `/api/bookings/{id}/payment` | `record_payment()` | booking-detail.html |
| 17 | GET | `/api/rooms/status` | `v_room_status_now` | rooms.html |
| 18 | POST | `/api/rooms/{id}/housekeeping` | `housekeeping_complete()` | rooms.html |
| 19 | GET | `/api/statistics` | `v_daily_occupancy` + `v_monthly_revenue` | statistics.html |
