from fastapi import APIRouter
from models.schemas import PreAssignRequest
from utils.db import execute

router = APIRouter(prefix="/api/calendar", tags=["Calendar"])

@router.get("")
def get_calendar(start_date: str, end_date: str):
    """
    Lấy dữ liệu cho Gantt calendar.
    Trả về TẤT CẢ phòng (LEFT JOIN) — phòng không có booking vẫn xuất hiện.
    """
    result = execute(
        """
        SELECT
            r.hotel_id,
            rt.id           AS room_type_id,
            rt.type_name,
            r.id            AS room_id,
            r.room_number,
            r.status        AS room_status,
            ra.id           AS assignment_id,
            b.id            AS booking_id,
            b.status        AS booking_status,
            c.full_name     AS customer_name,
            c.phone_number  AS customer_phone,
            ra.check_in,
            ra.check_out
        FROM rooms r
        JOIN room_types rt ON rt.id = r.room_type_id
        LEFT JOIN room_assignments ra
            ON ra.room_id = r.id
            AND ra.is_cancelled = FALSE
            AND ra.check_in  < %s::DATE
            AND ra.check_out > %s::DATE
        LEFT JOIN bookings b
            ON b.id = ra.booking_id
            AND b.status IN ('Active', 'Checked-in')
        LEFT JOIN customers c ON c.id = b.customer_id
        ORDER BY rt.type_name, r.room_number, ra.check_in
        """,
        (end_date, start_date),
        fetch="all"
    )
    return result or []

@router.post("/defragment")
def defragment(hotel_id: int, staff_id: int):
    """Gọi procedure tối ưu phân bổ phòng (Tetris algorithm)."""
    execute("CALL tetrisroom_defrag(%s, %s)", (hotel_id, staff_id))
    execute("DELETE FROM room_assignments WHERE is_cancelled = TRUE")
    return {"success": True, "message": "Phân bổ phòng đã được tối ưu."}

@router.post("/pre-assign")
def pre_assign(body: PreAssignRequest):
    """Gán tay một booking vào phòng cụ thể (kéo thả trên Calendar)."""
    try:
        execute("CALL pre_assign_room(%s, %s, %s, %s)", (body.booking_id, body.old_room_id, body.room_id, body.staff_id))
        execute("DELETE FROM room_assignments WHERE is_cancelled = TRUE")
        return {"success": True}
    except Exception as e:
        err_msg = str(e)
        if "exclude_overlapping_assignments" in err_msg:
            return {"success": False, "error": "Phòng đã có lịch đặt khác trong thời gian này (ngay cả khi không hiển thị hết trên màn hình)."}
        if "ROOM_TYPE_MISMATCH" in err_msg:
            return {"success": False, "error": "Phòng này không thuộc loại phòng của booking."}
        return {"success": False, "error": err_msg}
