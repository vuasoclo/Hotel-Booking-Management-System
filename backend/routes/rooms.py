from fastapi import APIRouter
from utils.db import execute

router = APIRouter(prefix="/api/rooms", tags=["Rooms"])

@router.get("/available")
def get_available_rooms(checkin: str, checkout: str):
    result = execute(
        "SELECT * FROM search_available_rooms(%s::DATE, %s::DATE)",
        (checkin, checkout),
        fetch="all"
    )
    return result or []

@router.get("/status")
def get_rooms_status():
    result = execute("""
        SELECT
            r.hotel_id,
            r.id AS room_id,
            r.room_number,
            rt.type_name,
            r.status AS physical_status,
            c.full_name AS current_guest,
            b.check_out AS expected_check_out,
            b.id AS booking_id
        FROM rooms r
        JOIN room_types rt ON rt.id = r.room_type_id
        LEFT JOIN room_assignments ra
               ON ra.room_id = r.id
              AND ra.is_cancelled = FALSE
              AND NOW() >= ra.check_in
              AND NOW() < ra.check_out
        LEFT JOIN bookings b
               ON b.id = ra.booking_id
              AND b.status = 'Checked-in'
        LEFT JOIN customers c ON c.id = b.customer_id
    """, fetch="all")
    return result or []

@router.post("/{room_id}/housekeeping")
def complete_housekeeping(room_id: int, staff_id: int):
    execute("CALL housekeeping_complete(%s, %s)", (room_id, staff_id))
    return {"success": True}
