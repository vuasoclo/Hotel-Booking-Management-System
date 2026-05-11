# HBMS — Báo Cáo Đánh Giá & Kế Hoạch Nâng Cấp

> **Dự án:** Hotel Booking Management System (Little Hotelier)  
> **Ngày đánh giá:** 11/05/2026  
> **Tổng quan:** 8 lỗi Critical · 11 Warning · 14 Improvement  

---

## 1. DATABASE — 10 vấn đề

### 1.1 [CRITICAL] SQL Injection trong statistics.py

**File:** `backend/routes/statistics.py`  
**Mô tả:** Tham số `room_type_id` từ query string được nối trực tiếp vào SQL bằng f-string:

```python
# ❌ Hiện tại — SQL injection vulnerable
occ_where.append(f"v.room_type_id = {room_type_id}")
```

**Fix:** Dùng parameterized query:

```python
# ✅ Sửa lại
occ_where.append("v.room_type_id = %s")
params.append(room_type_id)
```

### 1.2 [CRITICAL] Mật khẩu lưu plain text

**File:** `backend/routes/auth.py` + bảng `staff`  
**Mô tả:** Cột `password_hash` thực tế lưu mật khẩu thô. Backend so sánh trực tiếp `WHERE password_hash = %s`.

**Fix:** Dùng `bcrypt`:

```python
# Khi tạo staff
import bcrypt
hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt())

# Khi xác thực
staff = execute("SELECT * FROM staff WHERE username = %s", (username,), fetch="one")
if staff and bcrypt.checkpw(password.encode(), staff["password_hash"].encode()):
    return staff
```

### 1.3 [CRITICAL] Thiếu index quan trọng

**File:** `database/HBMS_full_deployment.sql`  
**Hiện tại:** Chỉ có 2 index (`idx_bookings_status`, `idx_rooms_status`).

**Cần thêm:**

```sql
CREATE INDEX idx_room_assignments_booking ON room_assignments(booking_id, is_cancelled);
CREATE INDEX idx_room_assignments_room_time ON room_assignments(room_id, check_in, check_out) WHERE is_cancelled = FALSE;
CREATE INDEX idx_booking_details_booking ON booking_details(booking_id);
CREATE INDEX idx_service_usage_booking ON service_usage(booking_id);
CREATE INDEX idx_customers_phone ON customers(phone_number);
CREATE INDEX idx_bookings_hotel_status ON bookings(hotel_id, status);
```

### 1.4 [WARNING] Inventory loop N+1 problem

**File:** `add_room_detail_to_booking()` procedure  
**Mô tả:** Loop từng ngày check-in→check-out, mỗi ngày 1 SELECT + 1 UPDATE. Booking 30 đêm = 60 queries.

**Fix:** Thay bằng batch query dùng `generate_series()`.

### 1.5 [WARNING] Không có audit trail

**Mô tả:** Không có bảng lưu lịch sử thay đổi booking status, payment, room assignment.

**Fix:** Tạo bảng `audit_log(id, entity_type, entity_id, action, old_value, new_value, staff_id, created_at)` và trigger.

### 1.6 [WARNING] Thiếu soft delete

**Mô tả:** Không có cơ chế soft delete cho customer, service. Xóa sẽ vi phạm FK.

### 1.7 [IMPROVE] Chưa partition room_type_inventory

**Mô tả:** Bảng sẽ tăng tuyến tính. Nên partition theo tháng.

### 1.8 [IMPROVE] check_in_booking chỉ xử lý 1 phòng

**Mô tả:** Procedure nhận 1 `p_room_id`. Booking multi-room phải loop frontend → không atomic.

**Fix:** Tạo `check_in_all_rooms(p_booking_id, p_staff_id)` xử lý batch.

### 1.9 [IMPROVE] Logic tính total_amount lặp 3 nơi

**Mô tả:** `recalculate_booking_total()`, `check_out_booking()`, `v_monthly_revenue` đều tính cùng formula.

### 1.10 [IMPROVE] Thiếu constraint ngày check-in trong tương lai

---

## 2. BACKEND — 9 vấn đề

### 2.1 [CRITICAL] Không có connection pool

**File:** `backend/utils/db.py`  
**Mô tả:** `get_conn()` tạo TCP connection mới mỗi request.

**Fix:**

```python
from psycopg2.pool import ThreadedConnectionPool
pool = ThreadedConnectionPool(minconn=2, maxconn=20, **DB_CONFIG)

def get_conn():
    return pool.getconn()

# Trả connection về pool khi done
def release_conn(conn):
    pool.putconn(conn)
```

### 2.2 [CRITICAL] Không có authentication middleware

**Mô tả:** Sau login, backend không verify request nào. Mọi endpoint đều public.

**Fix:** Implement JWT:

```python
from fastapi import Depends
from fastapi.security import HTTPBearer

security = HTTPBearer()

def get_current_user(credentials = Depends(security)):
    token = credentials.credentials
    payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
    return payload

@router.get("/protected")
def protected(user = Depends(get_current_user)):
    ...
```

### 2.3 [WARNING] hotel_id hardcode = 1

**Mô tả:** Frontend và một số route hardcode `hotel_id: 1`.

### 2.4 [WARNING] Error handling thiếu granularity

**Mô tả:** Tất cả exception → HTTP 400 + `str(e)`. Leak stack trace.

### 2.5 [WARNING] CORS allow_origins=["*"]

### 2.6 [WARNING] Input validation yếu

**Mô tả:** `check_in_date: str` chấp nhận mọi string. Không validate datetime, phone pattern, amount range.

### 2.7 [IMPROVE] Thiếu pagination

### 2.8 [IMPROVE] Không có logging/monitoring

### 2.9 [IMPROVE] Sync psycopg2 block FastAPI event loop

---

## 3. FRONTEND — 9 vấn đề (ƯU TIÊN NÂNG CẤP)

### 3.1 [CRITICAL] XSS qua innerHTML

**File:** Toàn bộ HTML files  
**Mô tả:** Data từ API inject trực tiếp qua `innerHTML` + template literals:

```javascript
// ❌ Hiện tại
tbody.innerHTML += `<td>${srv.service_name}</td>`;
```

**Fix:** Escape HTML hoặc dùng `textContent`. Tốt nhất: chuyển sang React/Vue (auto-escape).

### 3.2 [CRITICAL] API URL hardcode localhost:9000

**Fix:** Dùng config hoặc relative URL + reverse proxy.

### 3.3 [WARNING] Code duplication cực lớn

**Mô tả:** Header, sidebar, auth guard, format functions copy-paste qua 6 file HTML.

**Fix:** Chuyển sang SPA framework. Tạo shared layout component.

### 3.4 [WARNING] Calendar UX hạn chế

- Chỉ 7 ngày, không tuần/tháng view
- Drag-and-drop chỉ mouse → không mobile
- Không search, không tooltip
- Không hiện tổng phòng trống

### 3.5 [WARNING] Statistics chart thủ công

**Mô tả:** Revenue chart dùng div với height inline. Không tooltips, không responsive.

**Fix:** Dùng Chart.js hoặc Recharts.

### 3.6 [WARNING] Heatmap sắp xếp ngược

### 3.7 [WARNING] Không có loading states

**Mô tả:** Không spinner, không skeleton. Dùng `alert()` cho errors.

### 3.8 [IMPROVE] Room type filter hardcode

### 3.9 [IMPROVE] CSS variables undefined

**Mô tả:** `--radius-md`, `--shadow-sm`, `--color-info-100` dùng trong class nhưng không define trong `:root`.

---

## 4. SECURITY — 5 vấn đề

### 4.1 [CRITICAL] Không có authentication system thực sự

### 4.2 [CRITICAL] Plain text password

### 4.3 [WARNING] Không rate limiting

### 4.4 [WARNING] DB credentials hardcode

### 4.5 [WARNING] Không HTTPS enforcement

---

## 5. Thứ tự ưu tiên nâng cấp

| # | Hạng mục | Mức độ | Effort |
|---|----------|--------|--------|
| 1 | Frontend → React SPA | High | 3-5 ngày |
| 2 | JWT Authentication | Critical | 1-2 ngày |
| 3 | SQL injection fix | Critical | 0.5 ngày |
| 4 | Password hashing | Critical | 0.5 ngày |
| 5 | Connection pool | Critical | 0.5 ngày |
| 6 | Database indexes | High | 0.5 ngày |
| 7 | Input validation | Medium | 1 ngày |
| 8 | Error handling & logging | Medium | 1 ngày |
| 9 | Rate limiting + CORS | Medium | 0.5 ngày |
| 10 | Audit trail | Low | 1-2 ngày |
