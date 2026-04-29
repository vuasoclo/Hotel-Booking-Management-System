from pydantic import BaseModel
from typing import Optional

class LoginRequest(BaseModel):
    username: str
    password: str

class CustomerLookupRequest(BaseModel):
    phone_number: str

class BeginBookingRequest(BaseModel):
    hotel_id: int
    customer_id: int
    check_in_date: str
    check_out_date: str
    idempotency_key: str

class AddRoomDetailRequest(BaseModel):
    room_type_id: int
    quantity: int
    is_breakfast_included: bool

class FinalizeBookingRequest(BaseModel):
    staff_id: Optional[int] = None

class AddServiceRequest(BaseModel):
    service_id: int
    quantity: int
    staff_id: int

class CheckInRequest(BaseModel):
    room_id: int
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
    booking_id: int
    room_id: int
    staff_id: int
