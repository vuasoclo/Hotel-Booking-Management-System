from fastapi import APIRouter
from models.schemas import CustomerLookupRequest
from utils.db import execute

router = APIRouter(prefix="/api/customers", tags=["Customers"])

@router.post("/lookup")
def lookup_customer(body: CustomerLookupRequest):
    """Tìm kiếm khách hàng theo số điện thoại."""
    result = execute(
        "SELECT id AS customer_id, full_name, phone_number, identity_card, date_of_birth FROM customers WHERE phone_number = %s",
        (body.phone_number,),
        fetch="one"
    )
    return result
