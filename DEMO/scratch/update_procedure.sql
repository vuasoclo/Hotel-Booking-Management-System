DROP PROCEDURE IF EXISTS pre_assign_room(int, int, int); 
CREATE OR REPLACE PROCEDURE pre_assign_room(
    p_booking_id   INT,
    p_from_room_id INT,
    p_to_room_id   INT,
    p_staff_id     INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status            booking_status;
    v_check_in          TIMESTAMP;
    v_check_out         TIMESTAMP;
    v_room_type_id      INT;
BEGIN
    SELECT status, check_in, check_out
    INTO v_status, v_check_in, v_check_out
    FROM bookings WHERE id = p_booking_id FOR UPDATE;

    IF v_status IS DISTINCT FROM 'Active' THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: pre_assign_room chỉ áp dụng cho booking Active (hiện tại: %)', v_status
        USING ERRCODE = 'P0014';
    END IF;

    SELECT r.room_type_id INTO v_room_type_id
    FROM rooms r
    WHERE r.id = p_to_room_id;

    IF NOT EXISTS (
        SELECT 1 FROM booking_details
        WHERE booking_id = p_booking_id AND room_type_id = v_room_type_id
    ) THEN
        RAISE EXCEPTION 'ROOM_TYPE_MISMATCH: Phòng % không thuộc loại phòng nào trong booking %', p_to_room_id, p_booking_id
        USING ERRCODE = 'P0015';
    END IF;

    -- Hủy assignment cũ của phòng cụ thể này trước khi gán phòng mới
    UPDATE room_assignments
    SET is_cancelled = TRUE
    WHERE booking_id   = p_booking_id
      AND room_id      = p_from_room_id
      AND is_cancelled = FALSE;

    INSERT INTO room_assignments (booking_id, room_id, check_in, check_out, is_cancelled)
    VALUES (p_booking_id, p_to_room_id, v_check_in, v_check_out, FALSE);
END;
$$;
