# DATABASE PROGRAMMABILITY & BUSINESS LOGIC
_Đặc tả Logic Xử Lý - Stored Procedures & Triggers_

Tài liệu này định nghĩa mã SQL để xử lý các nghiệp vụ nâng cao, đã được tối ưu dựa trên các cảnh báo Anti-pattern (Lỗi update vòng lặp Inventory, Tranh chấp quyền update giá, và Thiếu Error Handling).

## 1. Trigger: Tự động lưu vết giá (Snapshot Pricing)
**Giải quyết Rule: Trách nhiệm SP và Trigger không chồng lấn.**
Trigger chịu trách nhiệm duy nhất cho việc lấy giá thời điểm hiện tại `base_price` ghi vào `agreed_price` nếu Application/SP không truyền vào (hoặc truyền bằng NULL/0).

```sql
CREATE OR REPLACE FUNCTION set_agreed_price()
RETURNS TRIGGER AS $$
BEGIN
    -- Nếu SP/Application không chỉ định giá cứng (hoặc để là 0/NULL), Trigger sẽ tự lấy giá gốc
    IF NEW.agreed_price IS NULL OR NEW.agreed_price = 0 THEN
        SELECT base_price INTO NEW.agreed_price
        FROM room_types
        WHERE id = NEW.room_type_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger chạy trước khi INSERT
CREATE TRIGGER trg_snapshot_price
BEFORE INSERT ON booking_details
FOR EACH ROW EXECUTE FUNCTION set_agreed_price();
```

## 2. Stored Procedure: Tạo Đơn Đặt Phòng Pha 1 (Reservation)
**Giải quyết Rule:**
1. Cập nhật tồn kho (Inventory) TẤT CẢ các ngày lưu trú (Bằng vòng lặp WHILE).
2. Xử lý Exception để map Error Code trả về cho Application.
3. Hỗ trợ trường `TIMESTAMP` cho Check-in/Check-out và bóc tách dữ liệu theo ngày để trừ tồn kho.
4. Xử lý tự động phụ thu nếu cần thiết thông qua Application code hoặc SP gọi kèm.

```sql
CREATE OR REPLACE PROCEDURE create_reservation(
    p_hotel_id INT,
    p_customer_id INT,
    p_room_type_id INT,
    p_quantity INT,
    p_check_in TIMESTAMP,
    p_check_out TIMESTAMP,
    p_is_breakfast_included BOOLEAN,
    p_idempotency_key UUID
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_booking_id INT;
    v_cur_date DATE := p_check_in::DATE;
    v_end_date DATE := p_check_out::DATE;
    v_available INT;
BEGIN
    -- 1. Insert Bookings với Idempotency
    BEGIN
        INSERT INTO bookings (hotel_id, customer_id, idempotency_key, check_in, check_out, status)
        VALUES (p_hotel_id, p_customer_id, p_idempotency_key, p_check_in, p_check_out, 'Pending')
        RETURNING id INTO v_booking_id;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'DUPLICATE: idempotency_key % đã tồn tại', p_idempotency_key
            USING ERRCODE = 'P0002';
    END;

    -- 2. Insert Booking_Details
    INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price, is_breakfast_included)
    VALUES (v_booking_id, p_room_type_id, p_quantity, 0, p_is_breakfast_included);

    -- 3. Cập nhật Tồn kho (Duyệt qua từng ngày của kỳ nghỉ)
    WHILE v_cur_date < v_end_date LOOP
        
        -- SELECT FOR UPDATE để chặn ghi đè đồng thời (race condition)
        SELECT (total_inventory - total_reserved)
        INTO v_available
        FROM room_type_inventory
        WHERE room_type_id = p_room_type_id AND date = v_cur_date
        FOR UPDATE;

        IF v_available IS NULL THEN
            RAISE EXCEPTION 'SYSTEM: Chưa thiết lập phòng loại % trong ngày %', p_room_type_id, v_cur_date
            USING ERRCODE = 'P0003';
        END IF;

        IF v_available < p_quantity THEN
            RAISE EXCEPTION 'OVERBOOKING: Không đủ phòng loại % trong ngày % (Còn: %)', 
                            p_room_type_id, v_cur_date, v_available
            USING ERRCODE = 'P0001';
        END IF;

        -- Update số lượng phòng đã dùng
        UPDATE room_type_inventory
        SET total_reserved = total_reserved + p_quantity
        WHERE room_type_id = p_room_type_id AND date = v_cur_date;

        v_cur_date := v_cur_date + 1;
    END LOOP;
    
    -- 4. Hoàn thành Đơn đặt
    UPDATE bookings SET status = 'Active' WHERE id = v_booking_id;

    -- [FIX-3] Gọi function apply_time_surcharges để tính phụ phí giờ sớm/muộn
    PERFORM apply_time_surcharges(v_booking_id);

    -- [FIX-5] Xóa lệnh COMMIT đi để transaction lifecycle do Application tầng trên quản lý, 
    -- SP này chỉ tập trung vào DML thuần túy

END;
$$;

-- [FIX-2] Bổ sung trigger nhả phòng về inventory khi Booking bị hủy
CREATE OR REPLACE FUNCTION release_inventory_on_cancel()
RETURNS TRIGGER AS $$
DECLARE
    r RECORD;
    v_cur_date DATE;
    v_end_date DATE;
BEGIN
    -- Lấy tất cả booking_details của booking đó
    FOR r IN SELECT * FROM booking_details WHERE booking_id = NEW.id LOOP
        v_cur_date := NEW.check_in::DATE;
        v_end_date := NEW.check_out::DATE;

        -- Giảm total_reserved với mỗi ngày trong khoảng check_in..check_out
        WHILE v_cur_date < v_end_date LOOP
            UPDATE room_type_inventory
            SET total_reserved = total_reserved - r.quantity
            WHERE room_type_id = r.room_type_id AND date = v_cur_date;

            v_cur_date := v_cur_date + 1;
        END LOOP;
    END LOOP;

    -- Cập nhật cancelled_at = NOW() nếu chưa có
    IF NEW.cancelled_at IS NULL THEN
        NEW.cancelled_at := NOW();
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_release_inventory_on_cancel
BEFORE UPDATE ON bookings
FOR EACH ROW 
WHEN (NEW.status = 'Cancelled' AND OLD.status != 'Cancelled')
EXECUTE FUNCTION release_inventory_on_cancel();

-- [FIX-3] Function áp dụng chính sách phụ thu check-in sớm, check-out muộn
CREATE OR REPLACE FUNCTION apply_time_surcharges(p_booking_id INT)
RETURNS VOID AS $$
DECLARE
    v_check_in TIMESTAMP;
    v_check_out TIMESTAMP;
    p RECORD;
    d RECORD;
    v_amount DECIMAL;
BEGIN
    SELECT check_in, check_out INTO v_check_in, v_check_out
    FROM bookings WHERE id = p_booking_id;

    FOR d IN SELECT * FROM booking_details WHERE booking_id = p_booking_id LOOP
        -- Tránh Insert duplicate nếu hàm bị gọi (retry) nhiều lần.
        DELETE FROM booking_surcharges 
        WHERE booking_id = p_booking_id AND surcharge_type IN ('EarlyCheckIn', 'LateCheckOut');

        -- Quét phụ thu check-in sớm
        FOR p IN SELECT * FROM surcharge_policies 
                 WHERE is_active = TRUE AND policy_type = 'EarlyCheckIn' AND 
                       v_check_in::TIME BETWEEN start_time AND end_time LOOP
            v_amount := d.agreed_price * p.multiplier * d.quantity;
            INSERT INTO booking_surcharges(booking_id, surcharge_type, amount, description)
            VALUES (p_booking_id, 'EarlyCheckIn', v_amount, p.description);
        END LOOP;

        -- Quét phụ thu check-out muộn
        FOR p IN SELECT * FROM surcharge_policies 
                 WHERE is_active = TRUE AND policy_type = 'LateCheckOut' AND 
                       v_check_out::TIME BETWEEN start_time AND end_time LOOP
            v_amount := d.agreed_price * p.multiplier * d.quantity;
            INSERT INTO booking_surcharges(booking_id, surcharge_type, amount, description)
            VALUES (p_booking_id, 'LateCheckOut', v_amount, p.description);
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```