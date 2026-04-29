from fastapi import APIRouter, HTTPException
from models.schemas import LoginRequest
from utils.db import execute

router = APIRouter(prefix="/api/auth", tags=["Auth"])

@router.post("/login")
def login(body: LoginRequest):
    """
    Xác thực tài khoản staff.
    Trả về: { staff_id, name, role }
    """
    result = execute(
        "SELECT id AS staff_id, name, role FROM staff WHERE username = %s AND password_hash = %s",
        (body.username, body.password),
        fetch="one"
    )
    if not result:
        raise HTTPException(status_code=401, detail="Sai tài khoản hoặc mật khẩu.")
    return result

@router.post("/logout")
def logout():
    """Frontend tự xóa sessionStorage. Endpoint này chỉ để log hoặc invalidate token sau này."""
    return {"success": True}
