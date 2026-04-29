from fastapi import APIRouter, HTTPException
from models.schemas import (
    BeginBookingRequest, AddRoomDetailRequest, FinalizeBookingRequest,
    CheckInRequest, CheckOutRequest, IssueInvoiceRequest, RecordPaymentRequest,
    CreateBookingRequest, AddServiceRequest
)
from utils.db import execute, execute_in_transaction

router = APIRouter(prefix="/api/bookings", tags=["Bookings"])

@router.post("/create", status_code=201)
def create_booking(body: CreateBookingRequest):
    """
    Tạo booking đầy đủ trong 1 atomic transaction:
      1. begin_booking()
      2. add_room_detail_to_booking() x rooms
      3. finalize_booking()
      4. auto_assign_rooms() — tìm phòng vật lý & INSERT room_assignments
         → Nếu không đủ phòng thực tế: ROLLBACK toàn bộ + 409
      5. INSERT service_usage x services
    """
    def _transaction(cur):
        # ── 1. Begin Booking — dùng INSERT ON CONFLICT thay vì begin_booking()
        #    để tránh psycopg2 transaction-abort state khi gặp DUPLICATE
        if body.check_out <= body.check_in:
            raise HTTPException(status_code=400, detail="INVALID_PERIOD: check_out phải lớn hơn check_in")

        cur.execute("""
            INSERT INTO bookings (hotel_id, customer_id, idempotency_key, check_in, check_out, status)
            VALUES (%s, %s, %s::UUID, %s::TIMESTAMP, %s::TIMESTAMP, 'Pending')
            ON CONFLICT (idempotency_key) DO NOTHING
            RETURNING id AS booking_id
        """, (body.hotel_id, body.customer_id, body.idempotency_key,
              body.check_in, body.check_out))
        row = cur.fetchone()

        if row is None:
            # Key đã tồn tại → tìm booking cũ (không có transaction abort)
            cur.execute(
                "SELECT id AS booking_id, status FROM bookings WHERE idempotency_key = %s::UUID",
                (body.idempotency_key,)
            )
            existing = cur.fetchone()
            if not existing:
                raise HTTPException(status_code=409, detail="Idempotency key conflict nhưng không tìm thấy booking. Thử lại.")
            if existing["status"] != "Pending":
                raise HTTPException(
                    status_code=409,
                    detail=f"Booking với key này đã ở trạng thái '{existing['status']}'. Vui lòng refresh trang."
                )
            booking_id = existing["booking_id"]
        else:
            booking_id = row["booking_id"]

        # ── 2. Add Room Details + Breakfast Surcharge ──────────────────────
        # Tính số đêm để tính breakfast surcharge
        cur.execute(
            "SELECT GREATEST((check_out::DATE - check_in::DATE), 1) AS nights "
            "FROM bookings WHERE id = %s",
            (booking_id,)
        )
        nights = cur.fetchone()["nights"]

        BREAKFAST_PRICE_PER_ROOM_PER_NIGHT = 150000  # VND

        # Gộp các phòng cùng room_type_id để tránh lỗi uq_booking_room_type
        aggregated_rooms = {}
        for room in body.rooms:
            tid = room.room_type_id
            if tid not in aggregated_rooms:
                aggregated_rooms[tid] = {
                    "quantity": 0,
                    "is_breakfast_included": False # Sẽ là True nếu có bất kỳ phòng nào có breakfast
                }
            aggregated_rooms[tid]["quantity"] += room.quantity
            if room.is_breakfast_included:
                aggregated_rooms[tid]["is_breakfast_included"] = True
            
            # Phụ phí bữa sáng tính ngay cho từng item lẻ
            if room.is_breakfast_included:
                cur.execute("SELECT type_name FROM room_types WHERE id = %s", (room.room_type_id,))
                rt_row = cur.fetchone()
                type_name_bf = rt_row["type_name"] if rt_row else f"TypeID {room.room_type_id}"

                surcharge_amount = BREAKFAST_PRICE_PER_ROOM_PER_NIGHT * room.quantity * nights
                cur.execute(
                    "INSERT INTO booking_surcharges (booking_id, surcharge_type, amount, description) "
                    "VALUES (%s, 'Other', %s, %s)",
                    (
                        booking_id,
                        surcharge_amount,
                        f"Breakfast — {type_name_bf} × {room.quantity} phòng × {nights} đêm"
                    )
                )

        # Gọi DB Procedure cho mỗi loại phòng đã gộp
        for tid, data in aggregated_rooms.items():
            cur.execute(
                "CALL add_room_detail_to_booking(%s, %s, %s, %s)",
                (booking_id, tid, data["quantity"], data["is_breakfast_included"])
            )

        # ── 3. Finalize (Pending → Active, apply time surcharges) ───────────
        cur.execute("CALL finalize_booking(%s)", (booking_id,))

        # ── 3b. Recalculate total_amount ────────────────────────────────────
        # sync_total_amount trigger chỉ watch service_usage, không watch booking_details
        # → phải gọi thủ công sau finalize để total_amount != 0
        cur.execute("SELECT recalculate_booking_total(%s)", (booking_id,))


        # ── 4. Auto-assign physical rooms (per booking_detail) ──────────────
        cur.execute(
            "SELECT bd.room_type_id, bd.quantity, rt.type_name "
            "FROM booking_details bd "
            "JOIN room_types rt ON rt.id = bd.room_type_id "
            "WHERE bd.booking_id = %s",
            (booking_id,)
        )
        details = cur.fetchall()

        already_assigned = []  # room_id đã assign trong vòng lặp này

        for detail in details:
            room_type_id = detail["room_type_id"]
            qty          = detail["quantity"]
            type_name    = detail["type_name"]

            for _ in range(qty):
                # Tìm phòng trống: cùng loại, không bị conflict thời gian, chưa assign trong loop này
                exclude_clause = ""
                params = [room_type_id, body.hotel_id]

                if already_assigned:
                    placeholders = ",".join(["%s"] * len(already_assigned))
                    exclude_clause = f"AND r.id NOT IN ({placeholders})"
                    params += already_assigned
                
                # Thêm check_in, check_out vào cuối để khớp với NOT EXISTS block
                params += [body.check_in, body.check_out]

                cur.execute(
                    f"""
                    SELECT r.id AS room_id
                    FROM rooms r
                    WHERE r.room_type_id = %s
                      AND r.hotel_id = %s
                      {exclude_clause}
                      AND NOT EXISTS (
                          SELECT 1 FROM room_assignments ra
                          WHERE ra.room_id = r.id
                            AND ra.is_cancelled = FALSE
                            AND tsrange(ra.check_in, ra.check_out, '[)')
                             && tsrange(%s::TIMESTAMP, %s::TIMESTAMP, '[)')
                      )
                    ORDER BY r.room_number
                    LIMIT 1
                    """,
                    params
                )
                room_row = cur.fetchone()

                if not room_row:
                    raise HTTPException(
                        status_code=409,
                        detail=f"ROOM_ASSIGN_FAILED: Không đủ phòng '{type_name}' để phân bổ (cần {qty}). Vui lòng chọn ngày khác hoặc loại phòng khác."
                    )

                room_id = room_row["room_id"]
                already_assigned.append(room_id)

                cur.execute(
                    "INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled) "
                    "VALUES (%s, %s, %s::TIMESTAMP, %s::TIMESTAMP, FALSE)",
                    (booking_id, room_id, body.check_in, body.check_out)
                )

        # ── 5. Add Services ─────────────────────────────────────────────────
        staff_id = body.staff_id or 1
        for svc in (body.services or []):
            cur.execute(
                "INSERT INTO service_usage (booking_id, service_id, quantity, staff_id) "
                "VALUES (%s, %s, %s, %s)",
                (booking_id, svc.service_id, svc.quantity, staff_id)
            )

        return {"booking_id": booking_id}

    return execute_in_transaction(_transaction)


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
    # Lấy base_price từ DB
    room_type = execute("SELECT base_price FROM room_types WHERE id = %s", (body.room_type_id,), fetch="one")
    if not room_type:
        raise HTTPException(status_code=404, detail="Loại phòng không tồn tại.")
    
    agreed_price = float(room_type["base_price"])
    if body.is_breakfast_included:
        agreed_price += 150000 # Breakfast fee

    execute(
        "CALL add_room_detail_to_booking(%s, %s, %s, %s)",
        (booking_id, body.room_type_id, body.quantity, body.is_breakfast_included)
    )
    
    # Cập nhật lại agreed_price sau khi trigger set_agreed_price đã chạy
    execute(
        "UPDATE booking_details SET agreed_price = %s WHERE booking_id = %s AND room_type_id = %s",
        (agreed_price, booking_id, body.room_type_id)
    )
    
    return {"success": True}

@router.post("/{booking_id}/finalize")
def finalize_booking(booking_id: int, body: FinalizeBookingRequest):
    """Bước 3/3 tạo booking: Kiểm tra inventory, tính giá, apply surcharges, chuyển Active, và gán phòng."""
    # 1. Finalize (status -> Active)
    execute("CALL finalize_booking(%s)", (booking_id,))
    
    # 2. Tự động gán phòng (Defragmentation)
    booking = execute("SELECT hotel_id FROM bookings WHERE id = %s", (booking_id,), fetch="one")
    if not booking:
        raise HTTPException(status_code=404, detail="Booking không tồn tại.")
    
    hotel_id = booking["hotel_id"]
    staff_id = body.staff_id or 1
    execute("CALL tetrisroom_defrag(%s, %s)", (hotel_id, staff_id))
    
    # 3. Kiểm tra xem đã gán đủ phòng chưa
    expected_rooms = execute("SELECT SUM(quantity) as total FROM booking_details WHERE booking_id = %s", (booking_id,), fetch="one")["total"]
    actual_rooms = execute("SELECT COUNT(*) as total FROM room_assignments WHERE booking_id = %s AND is_cancelled = FALSE", (booking_id,), fetch="one")["total"]
    
    if actual_rooms < expected_rooms:
        # Nếu không gán đủ, quay ngược lại trạng thái Cancelled và báo lỗi
        execute("UPDATE bookings SET status = 'Cancelled', cancel_reason = 'Không tìm thấy vị trí trống phù hợp trên calendar' WHERE id = %s", (booking_id,))
        raise HTTPException(status_code=400, detail="Không thể sắp xếp phòng phù hợp trên lịch. Vui lòng thử lại hoặc chọn phòng khác.")

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

@router.post("/{booking_id}/services")
def add_service_to_existing_booking(booking_id: int, body: AddServiceRequest):
    """Thêm dịch vụ cho một booking đã tồn tại."""
    execute(
        "INSERT INTO service_usage (booking_id, service_id, quantity, used_at, staff_id) VALUES (%s, %s, %s, NOW(), %s)",
        (booking_id, body.service_id, body.quantity, body.staff_id)
    )
    # Tổng tiền sẽ tự động cập nhật nhờ trigger trg_sync_total_amount trên bảng service_usage
    return {"success": True}


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
