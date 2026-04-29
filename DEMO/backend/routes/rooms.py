from fastapi import APIRouter
from utils.db import execute

router = APIRouter(prefix="/api/rooms", tags=["Rooms"])

@router.get("/available")
def get_available_rooms(checkin: str, checkout: str):
    """Tìm loại phòng còn trống trong khoảng ngày."""
    result = execute(
        "SELECT * FROM search_available_rooms(%s::DATE, %s::DATE)",
        (checkin, checkout),
        fetch="all"
    )
    return result or []

@router.get("/status")
def get_rooms_status():
    """Lấy trạng thái vật lý tất cả phòng từ view v_room_status_now."""
    result = execute("SELECT * FROM v_room_status_now", fetch="all")
    return result or []

@router.post("/{room_id}/housekeeping")
def complete_housekeeping(room_id: int, staff_id: int):
    """Đánh dấu phòng đã được dọn dẹp, chuyển từ Dirty → Available."""
    execute("CALL housekeeping_complete(%s, %s)", (room_id, staff_id))
    return {"success": True}
