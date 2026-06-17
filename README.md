# Hotel Booking Management System (HBMS)

HBMS là hệ thống quản lý đặt phòng khách sạn, xây dựng theo mô hình 3 lớp: Frontend tĩnh, Backend API, Database PostgreSQL. Dự án tập trung vào nghiệp vụ quản lý phòng, đặt phòng, lịch phòng, dịch vụ, hóa đơn, thanh toán và thống kê doanh thu/công suất phòng.

Hệ thống chạy bằng Docker Compose để đảm bảo cài đặt nhanh, đồng nhất môi trường và tự động khởi tạo cơ sở dữ liệu từ các file SQL trong thư mục `database/`.

---

## 1. Công nghệ sử dụng

| Thành phần | Công nghệ | Vai trò |
|---|---|---|
| Frontend | HTML, CSS, JavaScript, Nginx | Giao diện người dùng, phục vụ tại port `3000` |
| Backend | Python 3.10, FastAPI, Uvicorn | REST API xử lý nghiệp vụ, phục vụ tại port `9000` |
| Database | PostgreSQL 15 | Lưu trữ dữ liệu, ràng buộc toàn vẹn, procedure/function/view/trigger |
| Container | Docker, Docker Compose | Build, chạy và liên kết các service |
| DB driver | psycopg2 | Kết nối FastAPI với PostgreSQL |

---

## 2. Kiến trúc tổng quan

```text
+------------------+        HTTP         +------------------+        SQL        +------------------+
|    Frontend      |  <--------------->  |     Backend      |  <------------->  |    PostgreSQL    |
| Nginx / HTML JS  |                    | FastAPI / Python |                  | Schema + Logic   |
| localhost:3000   |                    | localhost:9000   |                  | localhost:6000   |
+------------------+                    +------------------+                  +------------------+
```

### Luồng hoạt động chính

1. Người dùng thao tác trên giao diện web.
2. Frontend gọi REST API của Backend.
3. Backend kiểm tra input, mở kết nối PostgreSQL và gọi SQL/procedure/function tương ứng.
4. Database xử lý nghiệp vụ quan trọng như kiểm tra tồn kho phòng, chống overbooking, tính tiền, cập nhật trạng thái phòng, tạo hóa đơn.
5. Backend trả JSON cho Frontend hiển thị.

---

## 3. Cấu trúc thư mục

```text
Hotel-Booking-Management-System-main/
├── backend/
│   ├── main.py
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── .env
│   ├── models/
│   │   └── schemas.py
│   ├── routes/
│   │   ├── auth.py
│   │   ├── bookings.py
│   │   ├── calendar.py
│   │   ├── customers.py
│   │   ├── rooms.py
│   │   ├── services.py
│   │   └── statistics.py
│   └── utils/
│       └── db.py
├── database/
│   ├── schema.sql
│   ├── functions.sql
│   ├── triggers.sql
│   ├── booking_procedures.sql
│   ├── invoice_procedures.sql
│   ├── views.sql
│   ├── utilities.sql
│   └── seed.sql
├── frontend/
│   ├── index.html
│   ├── calendar.html
│   ├── rooms.html
│   ├── new-reservation.html
│   ├── booking-detail.html
│   ├── statistics.html
│   └── css/
│       └── globals.css
├── .gitignore
├── .python-version
├── docker-compose.yml
├── test_query_safe.sql
└── README.md
```

---

## 4. Thành phần Docker Compose

File `docker-compose.yml` định nghĩa 3 service chính.

### 4.1. `db` - PostgreSQL

- Image: `postgres:15`
- Port: `6000:5432` (máy host dùng `6000`, container PostgreSQL vẫn dùng `5432`)
- Database: `hbms`
- User: `postgres`
- Password: `postgres`
- Volume dữ liệu: `pgdata:/var/lib/postgresql/data`
- Tự động chạy các file SQL trong `/docker-entrypoint-initdb.d/` khi volume database mới được tạo.

Thứ tự init SQL:

```text
01_schema.sql
02_functions.sql
03_triggers.sql
04_booking_procedures.sql
05_invoice_procedures.sql
06_views.sql
07_utilities.sql
08_seed.sql
```

Lưu ý: PostgreSQL chỉ tự chạy các file init này khi database volume còn trống. Nếu volume cũ vẫn tồn tại, dữ liệu cũ sẽ được dùng lại.

### 4.2. `backend` - FastAPI

- Build từ `backend/Dockerfile`
- Port: `9000:8000`
- Chạy Uvicorn với reload:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

- Phụ thuộc vào `db` và chỉ khởi động sau khi PostgreSQL healthy.
- Đọc biến môi trường từ `backend/.env`.
- Mount code backend vào `/app`, giúp thay đổi code được reload nhanh trong môi trường development.

### 4.3. `frontend` - Nginx

- Image: `nginx:alpine`
- Port: `3000:80`
- Mount thư mục `frontend/` vào Nginx document root.
- Phục vụ giao diện HTML/CSS/JS tĩnh.

---

## 5. Database - Thiết kế chi tiết

Database là phần trọng tâm của dự án. Nhiều nghiệp vụ được đặt trực tiếp trong PostgreSQL bằng enum, constraint, trigger, function, procedure và view để đảm bảo logic nhất quán dù API nào gọi vào.

### 5.1. Enum types

File: `database/schema.sql`

| Enum | Giá trị | Ý nghĩa |
|---|---|---|
| `booking_status` | `Pending`, `Active`, `Checked-in`, `Completed`, `Cancelled` | Vòng đời booking |
| `room_status` | `Available`, `Occupied`, `Dirty`, `Maintenance` | Trạng thái vật lý của phòng |
| `surcharge_type` | `EarlyCheckIn`, `LateCheckOut`, `Holiday`, `Weekend`, `Other` | Loại phụ phí |
| `invoice_status` | `Draft`, `Issued`, `Paid`, `Void` | Trạng thái hóa đơn |

### 5.2. Các bảng chính

#### `hotels`

Lưu thông tin khách sạn.

Cột chính:

- `id`: khóa chính.
- `name`: tên khách sạn.
- `address`: địa chỉ.
- `hotline`: số hotline.
- `created_at`: ngày tạo.

Quan hệ:

- Một khách sạn có nhiều staff, room_types, rooms, services, bookings.

#### `customers`

Lưu thông tin khách hàng.

Cột chính:

- `full_name`: họ tên.
- `phone_number`: số điện thoại, unique.
- `email`: email, unique.
- `identity_card`: giấy tờ tùy thân, unique.
- `date_of_birth`: ngày sinh.

Ràng buộc:

- `chk_customer_age`: khách hàng phải từ 18 tuổi trở lên.

#### `staff`

Lưu tài khoản và thông tin nhân viên.

Cột chính:

- `hotel_id`: khách sạn làm việc.
- `name`: tên nhân viên.
- `role`: vai trò, ví dụ `Admin`, `Staff`.
- `username`: tài khoản đăng nhập.
- `password_hash`: mật khẩu trong dữ liệu mẫu hiện đang lưu dạng plain text để phục vụ demo.

Chức năng:

- Dùng cho đăng nhập.
- Ghi nhận người thao tác tại các nghiệp vụ như check-in, check-out, thanh toán, housekeeping.

#### `room_types`

Lưu loại phòng của từng khách sạn.

Cột chính:

- `hotel_id`: khách sạn sở hữu loại phòng.
- `type_name`: tên loại phòng, ví dụ `Standard`, `Deluxe`, `Suite`.
- `base_price`: giá cơ bản mỗi đêm.
- `max_capacity`: sức chứa tối đa.

Ràng buộc:

- `base_price >= 0`.
- `max_capacity > 0`.
- Unique `(hotel_id, type_name)` để không trùng loại phòng trong cùng khách sạn.

#### `rooms`

Lưu phòng vật lý.

Cột chính:

- `hotel_id`: khách sạn sở hữu phòng.
- `room_number`: số phòng.
- `room_type_id`: loại phòng.
- `status`: trạng thái vật lý (`Available`, `Occupied`, `Dirty`, `Maintenance`).

Ràng buộc:

- Unique `(hotel_id, room_number)`.

Vai trò:

- Đại diện phòng thật trên lịch.
- Được gán vào booking qua bảng `room_assignments`.

#### `room_type_inventory`

Lưu tồn kho theo loại phòng và ngày.

Cột chính:

- `room_type_id`: loại phòng.
- `date`: ngày.
- `total_inventory`: tổng số phòng loại đó trong ngày.
- `total_reserved`: số phòng đã được giữ/chốt booking trong ngày.

Ràng buộc:

- Primary key `(room_type_id, date)`.
- `total_inventory >= 0`.
- `total_reserved >= 0`.
- `total_reserved <= total_inventory` qua constraint `no_overbook`.

Vai trò:

- Chống overbooking ở cấp loại phòng.
- Được cập nhật khi thêm chi tiết phòng vào booking hoặc hủy booking.

#### `bookings`

Lưu booking tổng.

Cột chính:

- `hotel_id`: khách sạn.
- `customer_id`: khách hàng.
- `status`: trạng thái booking.
- `idempotency_key`: UUID chống tạo trùng khi submit lại.
- `check_in`, `check_out`: thời gian lưu trú.
- `total_amount`: tổng tiền.
- `amount_paid`: đã thanh toán.
- `cancelled_at`, `cancel_reason`: thông tin hủy.

Ràng buộc:

- `check_out > check_in`.
- `total_amount >= 0`.
- `amount_paid >= 0`.
- `amount_paid <= total_amount`.
- `idempotency_key` unique.

Vòng đời booking:

```text
Pending -> Active -> Checked-in -> Completed
              |
              v
          Cancelled
```

#### `booking_details`

Lưu các loại phòng và số lượng trong booking.

Cột chính:

- `booking_id`: booking cha.
- `room_type_id`: loại phòng.
- `agreed_price`: giá chốt tại thời điểm đặt.
- `quantity`: số lượng phòng.
- `is_breakfast_included`: có kèm bữa sáng hay không.

Ràng buộc:

- Unique `(booking_id, room_type_id)`.
- `quantity > 0`.
- `agreed_price >= 0`.

Vai trò:

- Tính tiền phòng.
- Giữ tồn kho trong `room_type_inventory`.

#### `booking_surcharges`

Lưu phụ phí của booking.

Cột chính:

- `booking_id`: booking cha.
- `surcharge_type`: loại phụ phí.
- `amount`: số tiền.
- `description`: mô tả.

Nguồn phát sinh:

- Early check-in.
- Late check-out.
- Breakfast.
- Phụ phí khác.

#### `surcharge_policies`

Lưu chính sách phụ phí tự động.

Cột chính:

- `policy_type`: loại phụ phí.
- `description`: mô tả.
- `multiplier`: hệ số tính theo giá phòng.
- `start_time`, `end_time`: khung giờ áp dụng.
- `is_active`: còn hiệu lực hay không.

Vai trò:

- Được function `apply_time_surcharges()` dùng để tự tạo phụ phí khi finalize booking.

#### `room_assignments`

Lưu việc gán phòng vật lý cho booking.

Cột chính:

- `booking_id`: booking.
- `room_id`: phòng vật lý.
- `check_in`, `check_out`: khoảng thời gian phòng bị chiếm.
- `is_cancelled`: đánh dấu assignment cũ đã bị hủy.

Ràng buộc quan trọng:

```sql
EXCLUDE USING gist (
    room_id WITH =,
    tsrange(check_in, check_out, '[)') WITH &&
) WHERE (is_cancelled = FALSE)
```

Ý nghĩa:

- Một phòng vật lý không thể bị gán cho hai booking có khoảng thời gian chồng lấn.
- Đây là lớp bảo vệ chống conflict lịch phòng ở cấp database.

#### `services`

Lưu dịch vụ của khách sạn.

Ví dụ:

- Laundry Service.
- Airport Transfer.
- Spa Massage.
- Mini-bar Snack.
- Extra Bed.
- Morning Buffet.

Cột chính:

- `hotel_id`.
- `name`.
- `unit_price`.
- `category`.

Ràng buộc:

- Unique `(hotel_id, name)`.

#### `service_usage`

Lưu dịch vụ đã dùng trong booking.

Cột chính:

- `booking_id`: booking.
- `service_id`: dịch vụ.
- `quantity`: số lượng.
- `used_at`: thời điểm dùng.
- `staff_id`: nhân viên ghi nhận.

Vai trò:

- Tự động cập nhật tổng tiền booking qua trigger đồng bộ tổng tiền.

#### `invoices`

Lưu hóa đơn.

Cột chính:

- `booking_id`: booking được xuất hóa đơn.
- `issued_at`: thời điểm xuất.
- `issued_by`: nhân viên xuất.
- `total_amount`: tổng hóa đơn.
- `amount_paid`: đã thanh toán.
- `balance`: còn lại.
- `status`: trạng thái hóa đơn.

Ràng buộc:

- `balance = total_amount - amount_paid`.
- Unique invoice theo `booking_id`.
- Partial unique index `uq_invoice_active_booking` để mỗi booking chỉ có một hóa đơn chưa void.

---

## 6. Database - Functions

File: `database/functions.sql`

### `recalculate_booking_total(p_booking_id INT)`

Tính lại tổng tiền booking từ 3 nguồn:

1. Tiền phòng: `agreed_price * quantity * nights`.
2. Phụ phí: tổng `booking_surcharges.amount`.
3. Dịch vụ: `service_usage.quantity * services.unit_price`.

Kết quả được cập nhật vào `bookings.total_amount`.

### `apply_time_surcharges(p_booking_id INT)`

Tự động áp dụng phụ phí theo thời gian check-in/check-out.

Cách hoạt động:

- Lấy `check_in`, `check_out` của booking.
- Xóa phụ phí thời gian cũ của booking.
- Dựa vào `surcharge_policies` đang active.
- Nếu giờ check-in nằm trong khung `EarlyCheckIn`, tạo phụ phí early check-in.
- Nếu giờ check-out nằm trong khung `LateCheckOut`, tạo phụ phí late check-out.

### `search_available_rooms(p_start_date DATE, p_end_date DATE)`

Tìm loại phòng còn trống trong khoảng ngày.

Trả về:

- `room_type_id`.
- `type_name`.
- `min_available`: số phòng còn trống ít nhất trong toàn bộ khoảng ngày.
- `base_price`.
- `has_missing_dates`: có thiếu dòng inventory hay không.

Vai trò:

- Dùng cho màn hình tạo đặt phòng.
- Nếu thiếu dữ liệu inventory ngày nào đó, xem như không khả dụng để tránh nhận booking sai.

### `search_services(p_hotel_id INT, p_keyword VARCHAR)`

Tìm dịch vụ theo khách sạn và từ khóa.

Trả về:

- `service_id`.
- `service_name`.
- `unit_price`.
- `category`.

---

## 7. Database - Procedures nghiệp vụ booking

File: `database/booking_procedures.sql`

### `begin_booking(...)`

Tạo booking mới ở trạng thái `Pending`.

Kiểm tra:

- `check_out` phải lớn hơn `check_in`.
- `idempotency_key` không được trùng.

### `add_room_detail_to_booking(...)`

Thêm loại phòng và số lượng vào booking.

Kiểm tra:

- Booking phải ở trạng thái `Pending`.
- `quantity > 0`.
- Từng ngày trong khoảng lưu trú phải có inventory.
- Số phòng còn trống theo loại phòng phải đủ.

Tác động:

- Tăng `room_type_inventory.total_reserved` theo từng ngày.
- Thêm dòng `booking_details`.

### `finalize_booking(p_booking_id INT)`

Chốt booking.

Tác động:

- Kiểm tra booking đang `Pending`.
- Chuyển trạng thái sang `Active`.
- Gọi `apply_time_surcharges()` để áp dụng phụ phí thời gian.

### `pre_assign_room(...)`

Gán thủ công booking vào phòng vật lý.

Kiểm tra:

- Booking phải ở trạng thái `Active`.
- Phòng được gán phải thuộc một trong các loại phòng của booking.

Tác động:

- Hủy assignment cũ nếu có.
- Tạo assignment mới.
- Constraint `exclude_overlapping_assignments` đảm bảo không trùng lịch phòng.

### `tetrisroom_defrag(p_hotel_id INT, p_staff_id INT)`

Tối ưu lại phân bổ phòng theo thuật toán đơn giản kiểu “Tetris”.

Cách hoạt động:

1. Duyệt từng loại phòng trong khách sạn.
2. Hủy các assignment hiện tại của booking `Active` thuộc loại phòng đó.
3. Duyệt booking theo thứ tự `check_in`.
4. Tìm phòng vật lý không bị chồng lịch.
5. Gán booking vào phòng phù hợp.
6. Nếu không tìm được phòng, ghi warning.

Vai trò:

- Dùng cho màn hình Calendar/Gantt.
- Giúp gom và tối ưu lịch phòng.

### `check_in_booking(...)`

Check-in booking.

Kiểm tra:

- Booking phải ở trạng thái `Active` hoặc `Checked-in`.
- Phòng phải đang `Available`.
- Nếu chưa có assignment thì tạo assignment.

Tác động:

- Cập nhật phòng sang `Occupied`.
- Cập nhật booking sang `Checked-in`.

### `check_out_booking(...)`

Check-out booking.

Kiểm tra:

- Booking phải ở trạng thái `Checked-in`.

Tác động:

- Tính lại tổng tiền.
- Cập nhật booking sang `Completed`.
- Cập nhật các phòng liên quan sang `Dirty`.
- Cắt thời gian assignment về `NOW()` nếu check-out sớm.

### `housekeeping_complete(...)`

Hoàn tất dọn phòng.

Kiểm tra:

- Phòng phải đang `Dirty`.

Tác động:

- Chuyển phòng sang `Available`.

---

## 8. Database - Procedures hóa đơn và thanh toán

File: `database/invoice_procedures.sql`

### `issue_invoice(p_booking_id INT, p_staff_id INT)`

Xuất hóa đơn cho booking.

Kiểm tra:

- Booking phải ở trạng thái `Active`, `Checked-in` hoặc `Completed`.

Tác động:

- Tạo invoice mới nếu chưa có.
- Nếu đã có invoice chưa void, cập nhật lại tổng tiền, số tiền đã trả, số dư và người xuất.

### `record_payment(p_booking_id INT, p_amount DECIMAL, p_staff_id INT)`

Ghi nhận thanh toán.

Kiểm tra:

- Số tiền thanh toán phải lớn hơn 0.
- Booking phải ở trạng thái `Active`, `Checked-in` hoặc `Completed`.
- Không cho thanh toán vượt quá tổng hóa đơn.

Tác động:

- Tăng `bookings.amount_paid`.
- Cập nhật `invoices.amount_paid` và `invoices.balance`.
- Nếu trả đủ, invoice chuyển sang `Paid`; nếu chưa đủ, giữ `Issued`.

---

## 9. Database - Triggers

File: `database/triggers.sql`

### `touch_updated_at()`

Cập nhật `updated_at = NOW()` trước khi update.

Đang áp dụng cho:

- `rooms` qua trigger `trg_rooms_updated`.
- `bookings` qua trigger `trg_bookings_updated`.

### `set_agreed_price()`

Tự snapshot giá phòng từ `room_types.base_price` vào `booking_details.agreed_price` nếu giá chưa được truyền hoặc bằng 0.

Mục đích:

- Giữ giá phòng tại thời điểm đặt.
- Tránh booking cũ bị thay đổi giá khi bảng loại phòng đổi giá.

### `release_inventory_on_cancel()`

Khi booking chuyển sang `Cancelled`:

- Giảm `room_type_inventory.total_reserved` cho từng ngày đã giữ.
- Hủy các `room_assignments` đang active.
- Ghi `cancelled_at` nếu chưa có.

### `sync_total_amount()`

Đồng bộ tổng tiền booking sau khi insert/update/delete dữ liệu liên quan.

Đang áp dụng cho:

- `service_usage`.
- `booking_details`.
- `booking_surcharges`.

Tác động:

- Gọi `recalculate_booking_total()` để cập nhật `bookings.total_amount`.

---

## 10. Database - Views báo cáo và hiển thị

File: `database/views.sql`

### `v_daily_occupancy`

Hiển thị công suất phòng theo ngày và loại phòng.

Trường chính:

- `hotel_id`.
- `room_type_id`.
- `date`.
- `total_inventory`.
- `total_reserved`.
- `occupancy_rate`.

Dùng cho dashboard occupancy heatmap.

### `v_monthly_revenue`

Tổng hợp doanh thu theo tháng.

Tách doanh thu thành:

- `total_room_cost`: tiền phòng.
- `total_surcharges`: phụ phí.
- `total_services`: dịch vụ.
- `total_revenue`: tổng doanh thu.
- `actual_collected`: tiền thực thu.

Dùng cho biểu đồ doanh thu và KPI.

### `v_booking_summary`

Tóm tắt booking.

Trường chính:

- `booking_id`.
- `customer_name`.
- `room_types`.
- `nights`.
- `total_amount`.
- `amount_paid`.
- `balance`.

### `v_room_status_now`

Hiển thị trạng thái phòng hiện tại.

Bao gồm:

- Trạng thái vật lý.
- Khách hiện đang ở.
- Ngày check-out dự kiến.

### `v_calendar`

Hiển thị dữ liệu lịch phòng/Gantt calendar.

Bao gồm:

- Phòng.
- Loại phòng.
- Booking.
- Khách hàng.
- Khoảng check-in/check-out.
- Số dư thanh toán.

---

## 11. Database - Utilities và Seed

### `database/utilities.sql`

Có procedure:

```sql
reset_hbms_data()
```

Chức năng:

- `TRUNCATE` toàn bộ bảng nghiệp vụ.
- `RESTART IDENTITY` để reset sequence.
- `CASCADE` để xóa dữ liệu phụ thuộc.

Dùng khi cần làm sạch dữ liệu trong môi trường dev/test.

### `database/seed.sql`

Tạo dữ liệu mẫu gồm:

- 3 khách sạn.
- Tài khoản staff/admin.
- 5 khách hàng.
- 3 loại phòng cho khách sạn chính.
- 14 phòng vật lý.
- 10 dịch vụ.
- Inventory từ `CURRENT_DATE - 5` đến `CURRENT_DATE + 25`.
- 13 booking mẫu với nhiều trạng thái và khoảng ngày.
- Room assignment mẫu.
- Cập nhật `total_reserved` theo booking hiện có.
- Reset sequence sau khi insert dữ liệu có id cố định.

Tài khoản mẫu:

| Username | Password | Role |
|---|---|---|
| `admin` | `adminpassword` | `Admin` |
| `staff` | `staffpassword` | `Staff` |

---

## 12. Backend API

Backend được tổ chức theo router trong `backend/routes/`.

### 12.1. `auth.py`

Prefix: `/api/auth`

| Method | Endpoint | Chức năng |
|---|---|---|
| POST | `/api/auth/login` | Đăng nhập staff bằng username/password |
| POST | `/api/auth/logout` | Logout phía frontend |

### 12.2. `customers.py`

Prefix: `/api/customers`

| Method | Endpoint | Chức năng |
|---|---|---|
| POST | `/api/customers/lookup` | Tìm khách hàng theo số điện thoại |
| POST | `/api/customers` | Tạo khách hàng mới |

### 12.3. `rooms.py`

Prefix: `/api/rooms`

| Method | Endpoint | Chức năng |
|---|---|---|
| GET | `/api/rooms/available` | Tìm loại phòng còn trống theo ngày |
| GET | `/api/rooms/status` | Lấy trạng thái phòng hiện tại |
| POST | `/api/rooms/{room_id}/housekeeping` | Hoàn tất dọn phòng, chuyển Dirty -> Available |

### 12.4. `bookings.py`

Prefix: `/api/bookings`

| Method | Endpoint | Chức năng |
|---|---|---|
| POST | `/api/bookings/create` | Tạo booking đầy đủ trong một transaction |
| POST | `/api/bookings/begin` | Tạo booking bước 1 |
| POST | `/api/bookings/{booking_id}/rooms` | Thêm loại phòng vào booking |
| POST | `/api/bookings/{booking_id}/finalize` | Chốt booking và gán phòng |
| GET | `/api/bookings/{booking_id}` | Lấy chi tiết booking |
| POST | `/api/bookings/{booking_id}/services` | Thêm dịch vụ vào booking |
| POST | `/api/bookings/{booking_id}/checkin` | Check-in booking |
| POST | `/api/bookings/{booking_id}/checkout` | Check-out booking |
| POST | `/api/bookings/{booking_id}/cancel` | Hủy booking |
| POST | `/api/bookings/{booking_id}/invoice` | Xuất hóa đơn |
| POST | `/api/bookings/{booking_id}/payment` | Ghi nhận thanh toán |

Điểm đáng chú ý:

- Endpoint `/api/bookings/create` chạy trong transaction duy nhất bằng `execute_in_transaction()`.
- Nếu bất kỳ bước nào lỗi, toàn bộ booking sẽ rollback.
- Có xử lý `idempotency_key` để tránh tạo booking trùng khi người dùng submit lại.
- Có auto-assign phòng vật lý bằng cách tìm phòng không bị chồng lịch trong `room_assignments`.

### 12.5. `calendar.py`

Prefix: `/api/calendar`

| Method | Endpoint | Chức năng |
|---|---|---|
| GET | `/api/calendar` | Lấy dữ liệu Gantt calendar trong khoảng ngày |
| POST | `/api/calendar/defragment` | Gọi thuật toán tối ưu phân bổ phòng |
| POST | `/api/calendar/pre-assign` | Gán tay booking vào phòng cụ thể |

### 12.6. `services.py`

Prefix: `/api/services`

| Method | Endpoint | Chức năng |
|---|---|---|
| GET | `/api/services/search` | Tìm dịch vụ theo tên |
| POST | `/api/services/bookings/{booking_id}` | Thêm dịch vụ vào booking |

### 12.7. `statistics.py`

Prefix: `/api/statistics`

| Method | Endpoint | Chức năng |
|---|---|---|
| GET | `/api/statistics` | Lấy KPI, công suất phòng, doanh thu tháng |

Tham số hỗ trợ:

- `period`: `all`, `this_month`, `last_month`, `this_quarter`.
- `room_type_id`: lọc theo loại phòng cho phần occupancy.

---

## 13. Frontend

Frontend là các trang HTML tĩnh phục vụ qua Nginx.

| File | Chức năng |
|---|---|
| `index.html` | Trang đăng nhập/trang chính |
| `calendar.html` | Lịch đặt phòng dạng calendar/Gantt |
| `rooms.html` | Quản lý/trạng thái phòng |
| `new-reservation.html` | Tạo đặt phòng mới |
| `booking-detail.html` | Xem chi tiết booking, dịch vụ, hóa đơn, thanh toán |
| `statistics.html` | Dashboard thống kê |
| `css/globals.css` | Style dùng chung |

---

## 14. Các luồng nghiệp vụ chính

### 14.1. Tạo booking mới

```text
Frontend -> POST /api/bookings/create
Backend transaction:
  1. Tạo booking Pending
  2. Gộp room_type trùng
  3. Thêm booking_details
  4. Giữ inventory từng ngày
  5. Thêm phụ phí breakfast nếu có
  6. Finalize booking: Pending -> Active
  7. Áp dụng phụ phí early check-in/late check-out
  8. Tính lại total_amount
  9. Tự gán phòng vật lý không chồng lịch
  10. Thêm dịch vụ nếu có
Commit hoặc rollback toàn bộ
```

### 14.2. Check-in

```text
Active booking + Available room
-> CALL check_in_booking()
-> booking.status = Checked-in
-> rooms.status = Occupied
```

### 14.3. Check-out

```text
Checked-in booking
-> CALL check_out_booking()
-> tính lại tổng tiền
-> booking.status = Completed
-> rooms.status = Dirty
-> assignment.check_out = NOW() nếu check-out sớm
```

### 14.4. Dọn phòng

```text
Dirty room
-> CALL housekeeping_complete()
-> rooms.status = Available
```

### 14.5. Hủy booking

```text
Active booking
-> UPDATE bookings SET status = 'Cancelled'
-> trigger release_inventory_on_cancel()
-> giảm room_type_inventory.total_reserved
-> hủy room_assignments
-> set cancelled_at
```

### 14.6. Xuất hóa đơn và thanh toán

```text
CALL issue_invoice()
-> tạo/cập nhật invoice

CALL record_payment()
-> tăng bookings.amount_paid
-> cập nhật invoice balance
-> nếu trả đủ: invoice.status = Paid
```

---

## 15. Chạy dự án

### 15.1. Yêu cầu

- Docker Desktop hoặc Docker Engine.
- Docker Compose.

Backend luôn chạy trong Docker bằng image `python:3.10-slim`. Không cần cài Python 3.10 trên máy host. Nếu máy host có Python khác phiên bản, ví dụ Python 3.14, vẫn chạy dự án bằng Docker Compose như bình thường.

File `.python-version` được đặt là `3.10` để ghi rõ runtime backend mong muốn và hỗ trợ các công cụ tự chọn Python khi cần.

### 15.2. Build và chạy

Tại thư mục gốc dự án:

```bash
docker compose up --build -d
```

Truy cập:

| Dịch vụ | URL |
|---|---|
| Frontend | http://localhost:3000 |
| Backend API | http://localhost:9000 |
| Swagger UI | http://localhost:9000/docs |
| PostgreSQL | `localhost:6000` |

Thông tin DB:

```text
DB_NAME=hbms
DB_USER=postgres
DB_PASSWORD=postgres
DB_HOST=localhost
DB_PORT=6000
```

Khi chạy trong container backend, `DB_HOST=db` và `DB_PORT=5432` theo `backend/.env`. Cổng `6000` chỉ dùng từ máy host, ví dụ pgAdmin, DBeaver hoặc psql chạy ngoài Docker.

### 15.3. Chạy backend bằng Docker

Backend không chạy trực tiếp bằng Python trên máy host. Luôn chạy qua Docker Compose để đảm bảo đúng Python 3.10:

```powershell
docker compose up --build -d backend
```

Kiểm tra Python trong container backend:

```powershell
docker compose exec backend python --version
```

Kết quả mong muốn:

```text
Python 3.10.x
```

Không commit cache hoặc virtual environment. `.gitignore` đã bỏ qua `__pycache__/`, `*.pyc`, `.venv/`, `venv/`, `env/` và `.env`.

### 15.4. Ý nghĩa mapping port Docker

Docker Compose dùng dạng:

```text
HOST_PORT:CONTAINER_PORT
```

Trong dự án:

| Mapping | Truy cập từ máy host | Cổng bên trong container | Service |
|---|---|---|---|
| `6000:5432` | `localhost:6000` | `5432` | PostgreSQL |
| `9000:8000` | `localhost:9000` | `8000` | FastAPI backend |
| `3000:80` | `localhost:3000` | `80` | Nginx frontend |

Database đổi host port sang `6000` để tránh xung đột với PostgreSQL local thường dùng port `5432`. Không đổi cổng trong container vì PostgreSQL mặc định chạy ổn định ở `5432`, backend nội bộ Docker vẫn kết nối qua `db:5432`.

### 15.5. Kiểm tra trạng thái container

```bash
docker compose ps
```

### 15.6. Xem log

```bash
docker compose logs -f
```

Xem log riêng backend:

```bash
docker compose logs -f backend
```

Xem log riêng database:

```bash
docker compose logs -f db
```

### 15.7. Dừng dự án, giữ dữ liệu

```bash
docker compose down
```

### 15.8. Dừng dự án và xóa dữ liệu database

Dùng khi muốn PostgreSQL nạp lại `schema.sql`, `seed.sql` và các file SQL init từ đầu.

```bash
docker compose down -v
```

Sau đó chạy lại:

```bash
docker compose up --build -d
```

Hoặc gộp một dòng:

```bash
docker compose down -v && docker compose up --build -d
```

### 15.9. Kết nối database bằng pgAdmin 4

Do dự án publish PostgreSQL ra host port `6000`, cấu hình pgAdmin như sau:

```text
Name: HBMS Docker
Host name/address: 127.0.0.1
Port: 6000
Maintenance database: hbms
Username: postgres
Password: postgres
```

Sau khi kết nối, mở:

```text
Servers
└── HBMS Docker
    └── Databases
        └── hbms
            └── Schemas
                └── public
                    ├── Tables
                    └── Views
```

Nếu không thấy bảng, chuột phải `hbms`, `public` hoặc `Tables` rồi chọn `Refresh`.

Query kiểm tra nhanh:

```sql
SELECT current_database(), current_schema(), current_user;

SELECT table_schema, table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_type, table_name;
```

Kết nối đúng sẽ thấy database `hbms`, schema `public`, các bảng như `bookings`, `rooms`, `customers`, `room_assignments`, `services`.

### 15.10. Cài đặt trên máy khác

Các bước cài đặt trên máy mới:

1. Cài Docker Desktop hoặc Docker Engine.
2. Tải source code dự án về máy.
3. Mở terminal tại thư mục gốc dự án, nơi có file `docker-compose.yml`.
4. Kiểm tra port `3000`, `6000`, `9000` chưa bị ứng dụng khác dùng.
5. Chạy build và khởi động:

```bash
docker compose up --build -d
```

6. Kiểm tra container:

```bash
docker compose ps
```

Trạng thái mong muốn:

- `db`: `healthy`.
- `backend`: `Up`.
- `frontend`: `Up`.

7. Truy cập ứng dụng:

```text
Frontend:   http://localhost:3000
Backend:    http://localhost:9000
Swagger UI: http://localhost:9000/docs
Database:   127.0.0.1:6000
```

8. Đăng nhập bằng tài khoản mẫu:

```text
Admin: username = admin, password = adminpassword
Staff: username = staff, password = staffpassword
```

9. Nếu muốn xem database bằng pgAdmin/DBeaver:

```text
Host: 127.0.0.1
Port: 6000
Database: hbms
User: postgres
Password: postgres
```

10. Nếu muốn reset toàn bộ dữ liệu và nạp lại seed:

```bash
docker compose down -v
docker compose up --build -d
```

Lưu ý khi cài trên máy khác:

- Không cần cài Python/PostgreSQL/Nginx thủ công nếu chạy bằng Docker.
- Nếu máy đã có PostgreSQL local ở port `5432`, không ảnh hưởng vì dự án dùng host port `6000`.
- Nếu port `6000` bị chiếm, đổi phần bên trái trong `docker-compose.yml`, ví dụ `15432:5432`; sau đó pgAdmin dùng port mới.
- Không đổi port bên trong container (`5432`) nếu không cần thiết, vì backend nội bộ Docker đang dùng `db:5432`.

---

## 16. Kiểm thử database an toàn

File `test_query_safe.sql` chứa kịch bản test end-to-end database với transaction và savepoint.

Đặc điểm:

- Tạo khách sạn, khách hàng, staff, loại phòng, phòng, inventory, dịch vụ test.
- Gọi các procedure booking.
- Kiểm tra số booking, booking details, room assignments.
- Rollback về savepoint để không giữ dữ liệu test.

Chạy trong container database:

```bash
docker compose exec db psql -U postgres -d hbms -f /path/to/test_query_safe.sql
```

Nếu chạy từ host, có thể mount/copy file vào container trước hoặc dùng psql local.

---

## 17. Ghi chú về dữ liệu và logic

- Inventory theo loại phòng (`room_type_inventory`) dùng để kiểm soát số lượng phòng có thể bán trong từng ngày.
- Assignment theo phòng vật lý (`room_assignments`) dùng để kiểm soát lịch phòng thật trên calendar.
- Constraint GiST exclusion ngăn chồng lịch phòng ở tầng database.
- Trigger hủy booking đảm bảo trả lại inventory và hủy assignment.
- Trigger đồng bộ tổng tiền giúp booking luôn phản ánh tiền phòng, phụ phí và dịch vụ.
- View thống kê giúp backend lấy KPI/doanh thu/công suất mà không phải lặp logic tính toán ở Python.
- Dữ liệu mẫu dùng ngày tương đối theo `CURRENT_DATE`, nên dashboard và lịch luôn có dữ liệu gần ngày hiện tại khi seed lại database.

---

## 18. Hạn chế hiện tại và hướng phát triển

### Hạn chế hiện tại

- Mật khẩu staff trong seed đang lưu plain text, chỉ phù hợp demo.
- Chưa có JWT/session server-side hoàn chỉnh.
- Frontend là HTML/JS tĩnh, chưa dùng framework hiện đại.
- Một số nghiệp vụ vẫn nằm ở backend thay vì gom hoàn toàn vào stored procedure.
- Chưa có migration tool như Alembic/Flyway.

### Hướng phát triển

- Hash mật khẩu bằng bcrypt/argon2.
- Thêm JWT authentication và phân quyền theo role.
- Tách môi trường dev/staging/prod.
- Bổ sung migration versioning.
- Thêm test tự động cho API và database procedures.
- Bổ sung quản lý nhiều khách sạn đầy đủ hơn ở UI.
- Thêm audit log cho thao tác quan trọng.

---

## 19. Tóm tắt

HBMS là hệ thống quản lý đặt phòng khách sạn có trọng tâm database rõ ràng. PostgreSQL không chỉ lưu dữ liệu mà còn đảm nhiệm nhiều phần nghiệp vụ quan trọng: chống overbooking, gán phòng, tính tiền, phụ phí, hóa đơn, thanh toán, cập nhật trạng thái và thống kê. Backend FastAPI đóng vai trò lớp API điều phối, còn Frontend cung cấp giao diện thao tác cho người dùng cuối.
