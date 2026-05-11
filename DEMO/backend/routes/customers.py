from fastapi import APIRouter
from models.schemas import CustomerLookupRequest, CustomerCreateRequest
from utils.db import execute

router = APIRouter(prefix="/api/customers", tags=["Customers"])

@router.post("/lookup")
def lookup_customer(body: CustomerLookupRequest):
    """Tìm kiếm khách hàng theo số điện thoại."""
    result = execute(
        "SELECT id AS customer_id, full_name, phone_number, identity_card, email, date_of_birth FROM customers WHERE phone_number = %s",
        (body.phone_number,),
        fetch="one"
    )
    return result

@router.post("")
def create_customer(body: CustomerCreateRequest):
    """Tạo khách hàng mới."""
    result = execute(
        """
        INSERT INTO customers (full_name, phone_number, identity_card, email, date_of_birth)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id AS customer_id
        """,
        (body.full_name, body.phone_number, body.identity_card, body.email, body.date_of_birth),
        fetch="one"
    )
    return result
