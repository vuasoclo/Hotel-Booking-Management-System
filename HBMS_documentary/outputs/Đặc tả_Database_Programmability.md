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
2. Xử lý Exception để map Error Code trả về cho Application (OVERBOOKING, DUPLICATE_IDEMPOTENCY).

```sql
CREATE OR REPLACE PROCEDURE create_reservation(
    p_customer_id INT,
    p_room_type_id INT,
    p_quantity INT,
    p_check_in DATE,
    p_check_out DATE,
    p_idempotency_key UUID
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_booking_id INT;
    v_cur_date DATE := p_check_in;
    v_available INT;
BEGIN
    -- 1. Insert Bookings với Idempotency
    BEGIN
        INSERT INTO bookings (customer_id, idempotency_key, check_in, check_out, status)
        VALUES (p_customer_id, p_idempotency_key, p_check_in, p_check_out, 'Pending')
        RETURNING id INTO v_booking_id;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'DUPLICATE: idempotency_key % đã tồn tại', p_idempotency_key
            USING ERRCODE = 'P0002';
    END;

    -- 2. Insert Booking_Details (agreed_price truyền 0, để Trigger trg_snapshot_price tự lo lấy giá thực tế)
    INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price)
    VALUES (v_booking_id, p_room_type_id, p_quantity, 0);

    -- 3. Cập nhật Tồn kho (Duyệt qua từng ngày của kỳ nghỉ)
    WHILE v_cur_date < p_check_out LOOP
        
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

    COMMIT;
END;
$$;
```