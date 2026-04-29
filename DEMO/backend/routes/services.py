from fastapi import APIRouter
from models.schemas import AddServiceRequest
from utils.db import execute

router = APIRouter(prefix="/api/services", tags=["Services"])

@router.get("/search")
def search_services(q: str = ""):
    """Tìm kiếm dịch vụ theo tên."""
    result = execute(
        "SELECT id, id AS service_id, name, name AS service_name, unit_price as price, category FROM services WHERE name ILIKE %s",
        (f"%{q}%",), fetch="all"
    )
    return result or []

@router.post("/bookings/{booking_id}")
def add_service(booking_id: int, body: AddServiceRequest):
    """Thêm dịch vụ sử dụng trong booking."""
    execute(
        "INSERT INTO service_usage (booking_id, service_id, quantity, used_at, staff_id) VALUES (%s, %s, %s, NOW(), %s)",
        (booking_id, body.service_id, body.quantity, body.staff_id)
    )
    return {"success": True}
