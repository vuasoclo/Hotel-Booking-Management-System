# ROOM OPERATIONS & STATE MACHINE
_Đặc tả Logic Xử Lý - Quản lý Vòng Đời Phòng_

Tài liệu này định nghĩa chi tiết các thủ tục (Stored Procedures) quản lý trạng thái vật lý của phòng, từ lúc Check-in, Check-out cho đến khi làm buồng (Housekeeping), bảo đảm State Machine theo quy định (Available -> Occupied -> Dirty -> Available).

## 1. DDL Bổ sung (Constraints & Index)

*Lưu ý: Schema hiện tại đã khá đầy đủ. Chỉ cần thêm Index để tăng tốc độ truy vấn trạng thái phòng và booking.*

```sql
-- Index hỗ trợ tìm kiếm nhanh booking đang active
CREATE INDEX idx_bookings_status ON bookings(status);

-- Index hỗ trợ truy xuất trạng thái phòng nhanh chóng
CREATE INDEX idx_rooms_status ON rooms(status);
```

## 2. Stored Procedure: Check-in Nhận Phòng (Pha 2)
**Quy tắc:**
1. Booking phải ở trạng thái `Active`.
2. Phòng vật lý phải ở trạng thái `Available`.
3. Gán phòng vào thời gian `check_in` và `check_out` của booking gốc (đã được denormalize trong `room_assignments`).
4. Validate các trường hợp vi phạm trạng thái.

```sql
/*
 * Mục đích: Thực hiện thủ tục nhận phòng cho khách hàng.
 * Input: p_booking_id, p_room_id, p_staff_id
 * Output/Side effects: Thêm record vào room_assignments, đổi trạng thái booking và room.
 * Error codes: 
 *   - P0011: Booking không hợp lệ (không phải Active).
 *   - P0010: Phòng không sẵn sàng (không phải Available).
 */
CREATE OR REPLACE PROCEDURE check_in_booking(
    p_booking_id INT,
    p_room_id INT,
    p_staff_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_booking_status booking_status;
    v_room_status room_status;
    v_check_in TIMESTAMP;
    v_check_out TIMESTAMP;
BEGIN
    -- Lấy thông tin booking
    SELECT status, check_in, check_out INTO v_booking_status, v_check_in, v_check_out
    FROM bookings
    WHERE id = p_booking_id
    FOR UPDATE;

    IF v_booking_status != 'Active' THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Booking % không ở trạng thái Active', p_booking_id
        USING ERRCODE = 'P0011';
    END IF;

    -- Lấy thông tin phòng
    SELECT status INTO v_room_status
    FROM rooms
    WHERE id = p_room_id
    FOR UPDATE;

    IF v_room_status != 'Available' THEN
        RAISE EXCEPTION 'ROOM_NOT_AVAILABLE: Phòng % đang không sẵn sàng. Trạng thái hiện tại: %', p_room_id, v_room_status
        USING ERRCODE = 'P0010';
    END IF;

    -- Insert vào phân công phòng
    INSERT INTO room_assignments (booking_id, room_id, check_in, check_out)
    VALUES (p_booking_id, p_room_id, v_check_in, v_check_out);

    -- Cập nhật trạng thái
    UPDATE rooms 
    SET status = 'Occupied', updated_at = NOW(), updated_by = p_staff_id 
    WHERE id = p_room_id;

    UPDATE bookings 
    SET status = 'Checked-in', updated_at = NOW(), updated_by = p_staff_id 
    WHERE id = p_booking_id;
END;
$$;
```

## 3. Stored Procedure: Check-out Trả Phòng
**Quy tắc:**
1. Booking phải ở trạng thái `Checked-in`.
2. Tính lại `total_amount` bao gồm Tiền phòng + Phụ thu + Tiền dịch vụ.
3. Chuyển phòng sang trạng thái `Dirty`.
4. Không tạo invoice tại đây (Invoice sinh ở tầng App sau khi thanh toán).

```sql
/*
 * Mục đích: Thực hiện trả phòng và chốt tổng công nợ.
 * Input: p_booking_id, p_staff_id
 * Output/Side effects: Đổi trạng thái phòng thành Dirty, booking thành Completed, chốt total_amount.
 * Error codes: 
 *   - P0012: Booking không ở trạng thái Checked-in.
 */
CREATE OR REPLACE PROCEDURE check_out_booking(
    p_booking_id INT,
    p_staff_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_booking_status booking_status;
    v_room_cost DECIMAL := 0;
    v_surcharge_cost DECIMAL := 0;
    v_service_cost DECIMAL := 0;
    v_total DECIMAL := 0;
    v_nights INT;
BEGIN
    -- Lấy thông tin booking
    SELECT status, DATE_PART('day', check_out - check_in) INTO v_booking_status, v_nights
    FROM bookings
    WHERE id = p_booking_id
    FOR UPDATE;

    IF v_booking_status != 'Checked-in' THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Chỉ có thể check-out trên đơn đã Checked-in'
        USING ERRCODE = 'P0012';
    END IF;
    
    IF v_nights = 0 THEN v_nights := 1; END IF;

    -- Tính tiền phòng gốc
    SELECT COALESCE(SUM(agreed_price * quantity * v_nights), 0) INTO v_room_cost
    FROM booking_details 
    WHERE booking_id = p_booking_id;

    -- Tính tiền phụ thu
    SELECT COALESCE(SUM(amount), 0) INTO v_surcharge_cost
    FROM booking_surcharges
    WHERE booking_id = p_booking_id;

    -- Tính tiền dịch vụ (Bảng này khai báo ở module Reporting/Services)
    SELECT COALESCE(SUM(su.quantity * s.unit_price), 0) INTO v_service_cost
    FROM service_usage su JOIN services s ON su.service_id = s.id
    WHERE su.booking_id = p_booking_id;

    v_total := v_room_cost + v_surcharge_cost + v_service_cost;

    -- Cập nhật Booking
    UPDATE bookings 
    SET status = 'Completed', total_amount = v_total, updated_at = NOW(), updated_by = p_staff_id
    WHERE id = p_booking_id;

    -- Cập nhật Rooms: đổi sang Dirty cho toàn bộ phòng của booking này
    UPDATE rooms 
    SET status = 'Dirty', updated_at = NOW(), updated_by = p_staff_id
    WHERE id IN (
        SELECT room_id FROM room_assignments WHERE booking_id = p_booking_id
    );
END;
$$;
```

## 4. Stored Procedure: Hoàn thành Dọn dẹp (Housekeeping)
**Quy tắc:**
1. Chỉ được dọn dẹp khi phòng có trạng thái `Dirty`.
2. Đổi trạng thái từ `Dirty` sang `Available`.

```sql
/*
 * Mục đích: Ghi nhận nhân viên buồng phòng đã dọn dẹp xong.
 * Input: p_room_id, p_staff_id
 * Output/Side effects: Trạng thái phòng đổi thành Available.
 * Error codes: 
 *   - P0013: Phòng không ở trạng thái Dirty.
 */
CREATE OR REPLACE PROCEDURE housekeeping_complete(
    p_room_id INT,
    p_staff_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_status room_status;
BEGIN
    SELECT status INTO v_room_status 
    FROM rooms 
    WHERE id = p_room_id 
    FOR UPDATE;

    IF v_room_status != 'Dirty' THEN
        RAISE EXCEPTION 'HOUSEKEEPING_INVALID: Chỉ có thể dọn phòng ở trạng thái Dirty'
        USING ERRCODE = 'P0013';
    END IF;

    UPDATE rooms
    SET status = 'Available', updated_at = NOW(), updated_by = p_staff_id
    WHERE id = p_room_id;
END;
$$;
```

## 5. Kịch bản Kiểm thử Vòng đời phòng (Test Plan)

### STT | Tên Kịch bản | Phương pháp Kiểm thử | Kết quả Mong đợi |
| --- | --- | --- | --- |
| **TC-20** | Check-in hợp lệ | `CALL check_in_booking(B_ID, R_ID, S_ID)` với phòng `Available` và đơn `Active`. | Trạng thái booking -> `Checked-in`. Trạng thái phòng -> `Occupied`. |
| **TC-21** | Chặn Check-in phòng Dirty | `CALL check_in_booking` vào phòng đang `Dirty`. | Lỗi ERRCODE `P0010` ngăn cản nghiệp vụ. |
| **TC-22** | Chặn Check-in đơn Pending | `CALL check_in_booking` cho đơn chưa `Active` (chưa duyệt đặt chỗ). | Lỗi ERRCODE `P0011`. |
| **TC-23** | Check-out hợp lệ | `CALL check_out_booking(B_ID, S_ID)`. | `total_amount` tính chuẩn xác, trạng thái booking -> `Completed`. Trạng thái phòng -> `Dirty`. |
| **TC-24** | Housekeeping phòng bẩn | `CALL housekeeping_complete(R_ID, S_ID)` với phòng `Dirty`. | Trạng thái phòng chuyển sang `Available`. |
| **TC-25** | Chặn Dọn dẹp phòng trống | Cố tình `CALL housekeeping_complete` cho phòng đang `Available` hoặc `Occupied`. | Báo lỗi `P0013` nhằm tránh làm rối record. |
