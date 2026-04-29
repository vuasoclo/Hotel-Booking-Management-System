from fastapi import APIRouter, HTTPException
from models.schemas import (
    BeginBookingRequest, AddRoomDetailRequest, FinalizeBookingRequest,
    CheckInRequest, CheckOutRequest, IssueInvoiceRequest, RecordPaymentRequest
)
from utils.db import execute

router = APIRouter(prefix="/api/bookings", tags=["Bookings"])

@router.post("/begin")
def begin_booking(body: BeginBookingRequest):
    """Bước 1/3 tạo booking: Tạo bản ghi booking với trạng thái Pending."""
    result = execute(
        "CALL begin_booking(%s, %s, %s::TIMESTAMP, %s::TIMESTAMP, %s::UUID)",
        (body.hotel_id, body.customer_id, body.check_in_date, body.check_out_date, body.idempotency_key),
        fetch="one"
    )
    return result

@router.post("/{booking_id}/rooms")
def add_room_detail(booking_id: int, body: AddRoomDetailRequest):
    """Bước 2/3 tạo booking: Thêm loại phòng và số lượng."""
    execute(
        "CALL add_room_detail_to_booking(%s, %s, %s, %s)",
        (booking_id, body.room_type_id, body.quantity, body.is_breakfast_included)
    )
    return {"success": True}

@router.post("/{booking_id}/finalize")
def finalize_booking(booking_id: int, body: FinalizeBookingRequest):
    """Bước 3/3 tạo booking: Kiểm tra inventory, tính giá, apply surcharges, chuyển Active."""
    execute("CALL finalize_booking(%s)", (booking_id,))
    return {"success": True}

@router.get("/{booking_id}")
def get_booking_detail(booking_id: int):
    """Lấy toàn bộ thông tin chi tiết của 1 booking."""
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

    surcharges = execute("SELECT * FROM booking_surcharges WHERE booking_id = %s", (booking_id,), fetch="all")
    assignments = execute("SELECT ra.*, r.room_number FROM room_assignments ra JOIN rooms r ON ra.room_id = r.id WHERE ra.booking_id = %s", (booking_id,), fetch="all")
    services = execute("SELECT su.*, s.name AS service_name, s.unit_price FROM service_usage su JOIN services s ON su.service_id = s.id WHERE su.booking_id = %s", (booking_id,), fetch="all")

    return {
        **dict(summary),
        "surcharges": surcharges or [],
        "room_assignments": assignments or [],
        "services": services or [],
    }

@router.post("/{booking_id}/checkin")
def checkin(booking_id: int, body: CheckInRequest):
    """Check-in: chuyển booking từ Active → Checked-in."""
    execute("CALL check_in_booking(%s, %s, %s)", (booking_id, body.room_id, body.staff_id))
    return {"success": True}

@router.post("/{booking_id}/checkout")
def checkout(booking_id: int, body: CheckOutRequest):
    """Check-out: chuyển booking từ Checked-in → Completed, room → Dirty."""
    execute("CALL check_out_booking(%s, %s)", (booking_id, body.staff_id))
    return {"success": True}

@router.post("/{booking_id}/cancel")
def cancel_booking(booking_id: int):
    """Hủy booking."""
    execute("UPDATE bookings SET status = 'Cancelled' WHERE id = %s AND status = 'Active'", (booking_id,))
    return {"success": True}

@router.post("/{booking_id}/invoice")
def issue_invoice(booking_id: int, body: IssueInvoiceRequest):
    """Xuất hóa đơn cho booking."""
    execute("CALL issue_invoice(%s, %s)", (booking_id, body.staff_id))
    return {"success": True}

@router.post("/{booking_id}/payment")
def record_payment(booking_id: int, body: RecordPaymentRequest):
    """Ghi nhận thanh toán cho booking."""
    execute("CALL record_payment(%s, %s, %s)", (booking_id, body.amount, body.staff_id))
    return {"success": True}
