
## 5. Spec 2 file HTML cần build (Small & Beautiful)

### File 1: `booking-detail.html`

**Mục đích:** 1 màn duy nhất xử lý toàn bộ vòng đời booking sau khi tạo.

**Data sources:** `v_booking_summary`, `service_usage JOIN services`, `booking_surcharges`, `invoices`

**SQL procedures gọi:** `check_in_booking`, `check_out_booking`, `issue_invoice`, `record_payment`, `search_services`, `service_usage INSERT`, `status = 'Cancelled'`

**Layout (Bootstrap cards, không fancy):**
```
┌── TOPBAR (giống 4 file cũ) ────────────────────────────────┐
├── SIDEBAR (Calendar | New Reservation | Statistics | Rooms) ┤
│                                                             │
│  ← Quay lại   Booking #BK-001            ● Active          │
│                                                             │
│  [Card] Guest Info: name, phone, DOB                        │
│  [Card] Stay: check-in, check-out, rooms, nights            │
│  [Card] Cost Breakdown:                                      │
│    accordion: Rooms | Surcharges | Services                 │
│    Total / Paid / Balance                                   │
│  [Card] Services: table + [+ Add Service] button            │
│                                                             │
│  Action bar (bottom sticky):                                │
│    Nút hiển thị theo status:                                │
│    Active   → [Check-in] [Record Payment] [Issue Invoice] [Cancel]│
│    Checked-in → [Check-out] [Add Service] [Record Payment]  │
│    Completed → [Issue Invoice] (readonly otherwise)         │
│    Cancelled → (all disabled)                               │
└─────────────────────────────────────────────────────────────┘
```

**Modals tích hợp trong file:**
- Modal "Add Service" (Bootstrap modal — giống serviceModal trong new-reservation.html cũ)  
- Modal "Record Payment" (amount input + quick fill 25/50/Full + method select)

**Không cần:** Customer detail page, animation, confetti, CMND display

---

### File 2: `rooms.html`

**Mục đích:** Xem trạng thái phòng thực tế + housekeeping action.

**Data sources:** `v_room_status_now`

**SQL procedures gọi:** `housekeeping_complete()`

**Layout (Bootstrap cards, không fancy):**
```
┌── TOPBAR ──────────────────────────────────────────────────┐
├── SIDEBAR ──────────────────────────────────────────────────┤
│                                                             │
│  Room Status            [Filter: All | Available | Dirty…]  │
│                                                             │
│  Summary row: 🟢 8 Avail  🔵 5 Occupied  🟡 2 Dirty  🔴 1 Maint│
│                                                             │
│  [Group: Deluxe King]                                       │
│  ┌────────┐ ┌────────┐ ┌────────┐                          │
│  │ D101   │ │ D102   │ │ D103   │                          │
│  │Occupied│ │ Dirty  │ │ Avail  │                          │
│  │NV An   │ │        │ │        │                          │
│  │→03/05  │ │[✓Clean]│ │        │                          │
│  └────────┘ └────────┘ └────────┘                          │
│                                                             │
│  [Group: Suite]                                             │
│  ┌────────┐ ┌────────┐                                      │
│  │ S201   │ │ S202   │                                      │
│  │ Avail  │ │Mainten.│                                      │
│  └────────┘ └────────┘                                      │
└─────────────────────────────────────────────────────────────┘
```

**Click vào card Occupied** → link đến `booking-detail.html?id=xxx`  
**Nút "✓ Clean"** → gọi `POST /api/rooms/{id}/housekeeping` → reload card

**Không cần:** List view toggle, filter sidebar phức tạp, Room inventory setup, Room type CRUD

---

## 6. Cập nhật Sidebar (bổ sung 2 item mới)

Sidebar hiện tại chỉ có 3 mục. Cập nhật thêm:

```
📅  Calendar          → calendar.html
➕  New Reservation   → new-reservation.html  
🛏  Rooms             → rooms.html            ← MỚI
📊  Statistics        → statistics.html
```

**Không thêm:** Bookings list, Customers, Services, Invoices, Settings (tất cả đều được xử lý qua các màn trên).

---

## 7. API Endpoints tối thiểu (chỉ những gì 6 file HTML cần)

| Endpoint | Method | SQL Object | File HTML |
|---|---|---|---|
| `GET /api/calendar` | GET | `v_calendar` | calendar.html |
| `POST /api/defragment` | POST | `tetrisroom_defrag()` | calendar.html |
| `GET /api/rooms/available` | GET | `search_available_rooms()` | new-reservation.html |
| `POST /api/customers/lookup` | POST | `customers` by phone | new-reservation.html |
| `POST /api/bookings` | POST | `begin_booking()` | new-reservation.html |
| `POST /api/bookings/{id}/rooms` | POST | `add_room_detail_to_booking()` | new-reservation.html |
| `POST /api/bookings/{id}/finalize` | POST | `finalize_booking()` | new-reservation.html |
| `GET /api/services/search` | GET | `search_services()` | new-reservation.html |
| `POST /api/bookings/{id}/services` | POST | `service_usage INSERT` | new-reservation.html |
| `GET /api/bookings/{id}` | GET | `v_booking_summary` + surcharges | booking-detail.html |
| `POST /api/bookings/{id}/checkin` | POST | `check_in_booking()` | booking-detail.html |
| `POST /api/bookings/{id}/checkout` | POST | `check_out_booking()` | booking-detail.html |
| `POST /api/bookings/{id}/cancel` | POST | UPDATE status='Cancelled' | booking-detail.html |
| `POST /api/bookings/{id}/invoice` | POST | `issue_invoice()` | booking-detail.html |
| `POST /api/bookings/{id}/payment` | POST | `record_payment()` | booking-detail.html |
| `GET /api/rooms/status` | GET | `v_room_status_now` | rooms.html |
| `POST /api/rooms/{id}/housekeeping` | POST | `housekeeping_complete()` | rooms.html |
| `GET /api/statistics/occupancy` | GET | `v_daily_occupancy` | statistics.html |
| `GET /api/statistics/revenue` | GET | `v_monthly_revenue` | statistics.html |

**Tổng: 19 endpoints — đủ để demo toàn bộ vòng đời booking.**
