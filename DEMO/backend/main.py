"""
HBMS Backend — FastAPI
Mapping to: HBMS_scenario_and_endpoint.md (21 endpoints)
Run: uvicorn main:app --reload  (from DEMO/backend/)
Docs: http://127.0.0.1:8000/docs
"""

from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional
from database import get_conn
import os

app = FastAPI(
    title="HBMS — Hotel Booking Management System",
    description="Backend API cho đồ án DBMS. Tất cả logic nghiệp vụ nằm trong PostgreSQL Stored Procedures.",
    version="1.0.0",
)

# ─── Đường dẫn tới thư mục Frontend ──────────────────────────────────────────
FRONTEND_DIR = os.path.join(os.path.dirname(__file__), "..", "frontend")

# ─── Pydantic Models (Request Body) ──────────────────────────────────────────

class LoginRequest(BaseModel):
    username: str
    password: str

class CustomerLookupRequest(BaseModel):
    phone: str

class BeginBookingRequest(BaseModel):
    hotel_id: int
    customer_id: int
    check_in: str       # ISO 8601: "2026-04-28T14:00:00"
    check_out: str      # ISO 8601: "2026-04-30T12:00:00"
    idempotency_key: str

class AddRoomDetailRequest(BaseModel):
    room_type_id: int
    quantity: int
    is_breakfast_included: bool

class FinalizeBookingRequest(BaseModel):
    staff_id: int

class AddServiceRequest(BaseModel):
    service_id: int
    quantity: int
    staff_id: int

class CheckInRequest(BaseModel):
    staff_id: int

class CheckOutRequest(BaseModel):
    staff_id: int

class IssueInvoiceRequest(BaseModel):
    staff_id: int

class RecordPaymentRequest(BaseModel):
    amount: float
    payment_method: str  # "Cash" | "Card" | "Transfer"
    staff_id: int

class PreAssignRequest(BaseModel):
    booking_id: str
    room_id: int

# ─── Helper ───────────────────────────────────────────────────────────────────

def execute(sql: str, params: tuple = (), fetch: str = "none"):
    """Utility thực thi SQL và trả về kết quả."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            if fetch == "one":
                result = cur.fetchone()
            elif fetch == "all":
                result = cur.fetchall()
            else:
                result = None
            conn.commit()
        return result
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        conn.close()


# ═════════════════════════════════════════════════════════════════════════════
# #20 — AUTH: POST /api/auth/login
# ═════════════════════════════════════════════════════════════════════════════
@app.post("/api/auth/login", tags=["Auth"])
def login(body: LoginRequest):
    """
    Xác thực tài khoản staff.
    Trả về: { staff_id, name, role }
    """
    result = execute(
        "SELECT id AS staff_id, full_name AS name, role FROM staff WHERE username = %s AND password_hash = %s",
        (body.username, body.password),
        fetch="one"
    )
    if not result:
        raise HTTPException(status_code=401, detail="Sai tài khoản hoặc mật khẩu.")
    return result


# #21 — AUTH: POST /api/auth/logout
@app.post("/api/auth/logout", tags=["Auth"])
def logout():
    """Frontend tự xóa sessionStorage. Endpoint này chỉ để log hoặc invalidate token sau này."""
    return {"success": True}


# ═════════════════════════════════════════════════════════════════════════════
# #1 — CALENDAR: GET /api/calendar
# ═════════════════════════════════════════════════════════════════════════════
@app.get("/api/calendar", tags=["Calendar"])
def get_calendar(start_date: str, end_date: str):
    """
    Lấy dữ liệu cho Gantt calendar.
    Query params: start_date=2026-04-25&end_date=2026-05-01
    """
    result = execute(
        "SELECT * FROM v_calendar WHERE check_in < %s AND check_out > %s",
        (end_date, start_date),
        fetch="all"
    )
    return result or []


# #2 — CALENDAR: POST /api/calendar/defragment
@app.post("/api/calendar/defragment", tags=["Calendar"])
def defragment(hotel_id: int):
    """Gọi procedure tối ưu phân bổ phòng (Tetris algorithm)."""
    execute("CALL tetrisroom_defrag(%s)", (hotel_id,))
    return {"success": True, "message": "Phân bổ phòng đã được tối ưu."}


# #3 — CALENDAR: POST /api/calendar/pre-assign
@app.post("/api/calendar/pre-assign", tags=["Calendar"])
def pre_assign(body: PreAssignRequest):
    """Gán tay một booking vào phòng cụ thể (kéo thả trên Calendar)."""
    execute("CALL pre_assign_room(%s, %s)", (body.booking_id, body.room_id))
    return {"success": True}


# ═════════════════════════════════════════════════════════════════════════════
# #4 — ROOMS: GET /api/rooms/available
# ═════════════════════════════════════════════════════════════════════════════
@app.get("/api/rooms/available", tags=["Rooms"])
def get_available_rooms(checkin: str, checkout: str):
    """
    Tìm loại phòng còn trống trong khoảng ngày.
    Query params: checkin=2026-04-28&checkout=2026-04-30
    """
    result = execute(
        "SELECT * FROM search_available_rooms(%s::DATE, %s::DATE)",
        (checkin, checkout),
        fetch="all"
    )
    return result or []


# #17 — ROOMS: GET /api/rooms/status
@app.get("/api/rooms/status", tags=["Rooms"])
def get_rooms_status():
    """Lấy trạng thái vật lý tất cả phòng từ view v_room_status_now."""
    result = execute("SELECT * FROM v_room_status_now", fetch="all")
    return result or []


# #18 — ROOMS: POST /api/rooms/{room_id}/housekeeping
@app.post("/api/rooms/{room_id}/housekeeping", tags=["Rooms"])
def complete_housekeeping(room_id: int, staff_id: int):
    """Đánh dấu phòng đã được dọn dẹp, chuyển từ Dirty → Available."""
    execute("CALL housekeeping_complete(%s, %s)", (room_id, staff_id))
    return {"success": True}


# ═════════════════════════════════════════════════════════════════════════════
# #5 — CUSTOMERS: POST /api/customers/lookup
# ═════════════════════════════════════════════════════════════════════════════
@app.post("/api/customers/lookup", tags=["Customers"])
def lookup_customer(body: CustomerLookupRequest):
    """
    Tìm kiếm khách hàng theo số điện thoại.
    Trả về thông tin nếu đã có, null nếu chưa có.
    """
    result = execute(
        "SELECT id, full_name, phone, id_number, date_of_birth FROM customers WHERE phone = %s",
        (body.phone,),
        fetch="one"
    )
    return result  # None nếu không tìm thấy — Frontend tự hiểu là khách mới


# ═════════════════════════════════════════════════════════════════════════════
# #6 — BOOKINGS: POST /api/bookings/begin
# ═════════════════════════════════════════════════════════════════════════════
@app.post("/api/bookings/begin", tags=["Bookings"])
def begin_booking(body: BeginBookingRequest):
    """
    Bước 1/3 tạo booking: Tạo bản ghi booking với trạng thái Pending.
    Trả về booking_id mới tạo.
    """
    result = execute(
        "CALL begin_booking(%s, %s, %s::TIMESTAMP, %s::TIMESTAMP, %s::UUID)",
        (body.hotel_id, body.customer_id, body.check_in, body.check_out, body.idempotency_key),
        fetch="one"
    )
    return result


# #7 — BOOKINGS: POST /api/bookings/{id}/rooms
@app.post("/api/bookings/{booking_id}/rooms", tags=["Bookings"])
def add_room_detail(booking_id: int, body: AddRoomDetailRequest):
    """
    Bước 2/3 tạo booking: Thêm loại phòng và số lượng.
    Có thể gọi nhiều lần cho nhiều loại phòng.
    """
    execute(
        "CALL add_room_detail_to_booking(%s, %s, %s, %s)",
        (booking_id, body.room_type_id, body.quantity, body.is_breakfast_included)
    )
    return {"success": True}


# #8 — BOOKINGS: POST /api/bookings/{id}/finalize
@app.post("/api/bookings/{booking_id}/finalize", tags=["Bookings"])
def finalize_booking(booking_id: int, body: FinalizeBookingRequest):
    """
    Bước 3/3 tạo booking: Kiểm tra inventory, tính giá, apply surcharges, chuyển Active.
    Sau bước này booking sẽ hiển thị trên Calendar.
    """
    execute(
        "CALL finalize_booking(%s, %s)",
        (booking_id, body.staff_id)
    )
    return {"success": True}


# #11 — BOOKINGS: GET /api/bookings/{id}
@app.get("/api/bookings/{booking_id}", tags=["Bookings"])
def get_booking_detail(booking_id: int):
    """
    Lấy toàn bộ thông tin chi tiết của 1 booking.
    Gọi view v_booking_summary + bảng surcharges + room_assignments.
    """
    summary = execute(
        "SELECT * FROM v_booking_summary WHERE booking_id = %s",
        (booking_id,), fetch="one"
    )
    if not summary:
        raise HTTPException(status_code=404, detail="Booking không tồn tại.")

    surcharges = execute(
        "SELECT * FROM booking_surcharges WHERE booking_id = %s",
        (booking_id,), fetch="all"
    )
    assignments = execute(
        "SELECT ra.*, r.room_number FROM room_assignments ra JOIN rooms r ON ra.room_id = r.id WHERE ra.booking_id = %s",
        (booking_id,), fetch="all"
    )
    services = execute(
        "SELECT su.*, s.name AS service_name FROM service_usage su JOIN services s ON su.service_id = s.id WHERE su.booking_id = %s",
        (booking_id,), fetch="all"
    )

    return {
        **dict(summary),
        "surcharges": surcharges or [],
        "room_assignments": assignments or [],
        "services": services or [],
    }


# #9 — SERVICES: GET /api/services/search
@app.get("/api/services/search", tags=["Services"])
def search_services(q: str = ""):
    """Tìm kiếm dịch vụ theo tên. Query param: q=spa"""
    result = execute(
        "SELECT id, name, price FROM services WHERE name ILIKE %s",
        (f"%{q}%",), fetch="all"
    )
    return result or []


# #10 — SERVICES: POST /api/bookings/{id}/services
@app.post("/api/bookings/{booking_id}/services", tags=["Services"])
def add_service(booking_id: int, body: AddServiceRequest):
    """Thêm dịch vụ sử dụng trong booking (khi Checked-in)."""
    execute(
        "INSERT INTO service_usage (booking_id, service_id, quantity, used_at, staff_id) VALUES (%s, %s, %s, NOW(), %s)",
        (booking_id, body.service_id, body.quantity, body.staff_id)
    )
    return {"success": True}


# #12 — BOOKINGS: POST /api/bookings/{id}/checkin
@app.post("/api/bookings/{booking_id}/checkin", tags=["Bookings"])
def checkin(booking_id: int, body: CheckInRequest):
    """Check-in: chuyển booking từ Active → Checked-in."""
    execute("CALL check_in_booking(%s, %s)", (booking_id, body.staff_id))
    return {"success": True}


# #13 — BOOKINGS: POST /api/bookings/{id}/checkout
@app.post("/api/bookings/{booking_id}/checkout", tags=["Bookings"])
def checkout(booking_id: int, body: CheckOutRequest):
    """Check-out: chuyển booking từ Checked-in → Completed, room → Dirty."""
    execute("CALL check_out_booking(%s, %s)", (booking_id, body.staff_id))
    return {"success": True}


# #14 — BOOKINGS: POST /api/bookings/{id}/cancel
@app.post("/api/bookings/{booking_id}/cancel", tags=["Bookings"])
def cancel_booking(booking_id: int):
    """Hủy booking, trigger tự động release inventory."""
    execute(
        "UPDATE bookings SET status = 'Cancelled' WHERE id = %s AND status = 'Active'",
        (booking_id,)
    )
    return {"success": True}


# #15 — BOOKINGS: POST /api/bookings/{id}/invoice
@app.post("/api/bookings/{booking_id}/invoice", tags=["Bookings"])
def issue_invoice(booking_id: int, body: IssueInvoiceRequest):
    """Xuất hóa đơn cho booking."""
    execute("CALL issue_invoice(%s, %s)", (booking_id, body.staff_id))
    return {"success": True}


# #16 — BOOKINGS: POST /api/bookings/{id}/payment
@app.post("/api/bookings/{booking_id}/payment", tags=["Bookings"])
def record_payment(booking_id: int, body: RecordPaymentRequest):
    """Ghi nhận thanh toán cho booking."""
    execute(
        "CALL record_payment(%s, %s, %s, %s)",
        (booking_id, body.amount, body.payment_method, body.staff_id)
    )
    return {"success": True}


# #19 — STATISTICS: GET /api/statistics
@app.get("/api/statistics", tags=["Statistics"])
def get_statistics():
    """Lấy dữ liệu dashboard: KPI, occupancy heatmap, revenue chart."""
    occupancy = execute("SELECT * FROM v_daily_occupancy ORDER BY date DESC LIMIT 30", fetch="all")
    revenue   = execute("SELECT * FROM v_monthly_revenue ORDER BY month DESC LIMIT 12", fetch="all")
    return {
        "daily_occupancy": occupancy or [],
        "monthly_revenue": revenue or [],
    }


# ═════════════════════════════════════════════════════════════════════════════
# SERVE FRONTEND — Phục vụ các file HTML/CSS/JS tĩnh
# Phải đặt SAU các API routes để không bị xung đột
# ═════════════════════════════════════════════════════════════════════════════
app.mount("/css", StaticFiles(directory=os.path.join(FRONTEND_DIR, "css")), name="css")

@app.get("/", include_in_schema=False)
def serve_index():
    return FileResponse(os.path.join(FRONTEND_DIR, "index.html"))

@app.get("/{page_name}.html", include_in_schema=False)
def serve_page(page_name: str):
    file_path = os.path.join(FRONTEND_DIR, f"{page_name}.html")
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Trang không tồn tại.")
    return FileResponse(file_path)
