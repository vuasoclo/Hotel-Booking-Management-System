CREATE OR REPLACE FUNCTION recalculate_booking_total(p_booking_id INT)
RETURNS VOID AS $$
DECLARE
    v_nights INT;
    v_room_cost DECIMAL(10, 2) := 0;
    v_surcharge_cost DECIMAL(10, 2) := 0;
    v_service_cost DECIMAL(10, 2) := 0;
BEGIN
    IF p_booking_id IS NULL THEN
        RETURN;
    END IF;
    SELECT GREATEST((check_out::DATE - check_in::DATE), 1)
    INTO v_nights
    FROM bookings
    WHERE id = p_booking_id;
    IF v_nights IS NULL THEN
        RETURN;
    END IF;
    SELECT COALESCE(SUM(agreed_price * quantity * v_nights), 0)
    INTO v_room_cost
    FROM booking_details
    WHERE booking_id = p_booking_id;
    SELECT COALESCE(SUM(amount), 0)
    INTO v_surcharge_cost
    FROM booking_surcharges
    WHERE booking_id = p_booking_id;
    SELECT COALESCE(SUM(su.quantity * s.unit_price), 0)
    INTO v_service_cost
    FROM service_usage su
    JOIN services s ON s.id = su.service_id
    WHERE su.booking_id = p_booking_id;
    UPDATE bookings
    SET total_amount = v_room_cost + v_surcharge_cost + v_service_cost
    WHERE id = p_booking_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION apply_time_surcharges(p_booking_id INT)
RETURNS VOID AS $$
DECLARE
    v_check_in TIMESTAMP;
    v_check_out TIMESTAMP;
BEGIN
    SELECT check_in, check_out
    INTO v_check_in, v_check_out
    FROM bookings
    WHERE id = p_booking_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'BOOKING_NOT_FOUND: booking_id % không tồn tại', p_booking_id
        USING ERRCODE = 'P0004';
    END IF;
    DELETE FROM booking_surcharges
    WHERE booking_id = p_booking_id
      AND surcharge_type IN ('EarlyCheckIn', 'LateCheckOut');
    INSERT INTO booking_surcharges (booking_id, surcharge_type, amount, description)
    SELECT
        p_booking_id,
        sp.policy_type,
        (bd.agreed_price * sp.multiplier * bd.quantity)::DECIMAL(10, 2) AS amount,
        COALESCE(sp.description, 'Auto time surcharge')
    FROM booking_details bd
    JOIN surcharge_policies sp
      ON sp.is_active = TRUE
     AND (
            (sp.policy_type = 'EarlyCheckIn' AND v_check_in::TIME BETWEEN sp.start_time AND sp.end_time)
         OR (sp.policy_type = 'LateCheckOut' AND v_check_out::TIME BETWEEN sp.start_time AND sp.end_time)
     )
    WHERE bd.booking_id = p_booking_id;
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION search_available_rooms(
    p_start_date DATE,
    p_end_date   DATE
)
RETURNS TABLE (
    room_type_id      INT,
    type_name         VARCHAR,
    min_available     INT,
    base_price        DECIMAL,
    has_missing_dates BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        rt.id,
        rt.type_name,
        CASE
            WHEN BOOL_OR(rti.date IS NULL)
            THEN 0
            ELSE MIN(rti.total_inventory - rti.total_reserved)::INT
        END                                AS min_available,
        rt.base_price,
        BOOL_OR(rti.date IS NULL)          AS has_missing_dates
    FROM room_types rt
    CROSS JOIN generate_series(
        p_start_date,
        p_end_date - 1,
        '1 day'::interval
    ) AS d(dt)
    LEFT JOIN room_type_inventory rti
           ON rti.room_type_id = rt.id
          AND rti.date         = d.dt::DATE
    GROUP BY rt.id, rt.type_name, rt.base_price;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION search_services(
    p_hotel_id INT,
    p_keyword  VARCHAR DEFAULT ''
)
RETURNS TABLE (
    service_id   INT,
    service_name VARCHAR,
    unit_price   DECIMAL,
    category     VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, s.name, s.unit_price, s.category
    FROM services s
    WHERE s.hotel_id = p_hotel_id
      AND (p_keyword = '' OR s.name ILIKE '%' || p_keyword || '%')
    ORDER BY s.category, s.name;
END;
$$ LANGUAGE plpgsql;
