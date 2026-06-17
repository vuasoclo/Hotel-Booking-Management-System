CREATE OR REPLACE VIEW v_daily_occupancy AS
SELECT
    rt.hotel_id,
    rti.room_type_id,
    rti.date,
    rti.total_inventory,
    rti.total_reserved,
    CASE
        WHEN rti.total_inventory = 0 THEN 0
        ELSE ROUND((rti.total_reserved * 100.0) / rti.total_inventory, 2)
    END AS occupancy_rate
FROM room_type_inventory rti
JOIN room_types rt ON rt.id = rti.room_type_id;
CREATE OR REPLACE VIEW v_monthly_revenue AS
WITH booking_base AS (
    SELECT
        b.id,
        b.hotel_id,
        DATE_TRUNC('month', b.check_out) AS report_month,
        b.amount_paid,
        GREATEST((b.check_out::DATE - b.check_in::DATE), 1) AS nights
    FROM bookings b
    WHERE b.status IN ('Completed', 'Checked-in')
),
room_sum AS (
    SELECT
        bb.id AS booking_id,
        COALESCE(SUM(bd.agreed_price * bd.quantity * bb.nights), 0) AS total_room_cost
    FROM booking_base bb
    LEFT JOIN booking_details bd ON bd.booking_id = bb.id
    GROUP BY bb.id
),
surcharge_sum AS (
    SELECT
        bs.booking_id,
        COALESCE(SUM(bs.amount), 0) AS total_surcharges
    FROM booking_surcharges bs
    GROUP BY bs.booking_id
),
service_sum AS (
    SELECT
        su.booking_id,
        COALESCE(SUM(su.quantity * s.unit_price), 0) AS total_services
    FROM service_usage su
    JOIN services s ON s.id = su.service_id
    GROUP BY su.booking_id
)
SELECT
    bb.hotel_id,
    bb.report_month,
    SUM(COALESCE(rs.total_room_cost, 0)) AS total_room_cost,
    SUM(COALESCE(ss.total_surcharges, 0)) AS total_surcharges,
    SUM(COALESCE(svs.total_services, 0)) AS total_services,
    SUM(COALESCE(rs.total_room_cost, 0) + COALESCE(ss.total_surcharges, 0) + COALESCE(svs.total_services, 0)) AS total_revenue,
    SUM(bb.amount_paid) AS actual_collected
FROM booking_base bb
LEFT JOIN room_sum rs ON rs.booking_id = bb.id
LEFT JOIN surcharge_sum ss ON ss.booking_id = bb.id
LEFT JOIN service_sum svs ON svs.booking_id = bb.id
GROUP BY bb.hotel_id, bb.report_month;
CREATE OR REPLACE VIEW v_booking_summary AS
SELECT
    b.id AS booking_id,
    c.full_name AS customer_name,
    STRING_AGG(DISTINCT rt.type_name, ', ') AS room_types,
    GREATEST((b.check_out::DATE - b.check_in::DATE), 1) AS nights,
    b.total_amount,
    b.amount_paid,
    (b.total_amount - b.amount_paid) AS balance
FROM bookings b
JOIN customers c ON c.id = b.customer_id
JOIN booking_details bd ON bd.booking_id = b.id
JOIN room_types rt ON rt.id = bd.room_type_id
GROUP BY b.id, c.full_name, b.check_in, b.check_out, b.total_amount, b.amount_paid;
CREATE OR REPLACE VIEW v_room_status_now AS
SELECT
    r.hotel_id,
    r.id AS room_id,
    r.room_number,
    rt.type_name,
    r.status AS physical_status,
    c.full_name AS current_guest,
    b.check_out AS expected_check_out
FROM rooms r
JOIN room_types rt ON rt.id = r.room_type_id
LEFT JOIN room_assignments ra
       ON ra.room_id = r.id
      AND ra.is_cancelled = FALSE
      AND NOW() >= ra.check_in
      AND NOW() < ra.check_out
LEFT JOIN bookings b
       ON b.id = ra.booking_id
      AND b.status = 'Checked-in'
LEFT JOIN customers c ON c.id = b.customer_id;

CREATE OR REPLACE VIEW v_calendar AS
SELECT
    ra.id                   AS assignment_id,
    r.hotel_id,
    rt.id                   AS room_type_id,
    rt.type_name,
    r.id                    AS room_id,
    r.room_number,
    r.status                AS room_status,
    b.id                    AS booking_id,
    b.status                AS booking_status,
    c.full_name             AS customer_name,
    c.phone_number          AS customer_phone,
    ra.check_in,
    ra.check_out,
    b.total_amount,
    b.amount_paid,
    (b.total_amount - b.amount_paid)    AS balance,
    b.updated_at            AS booking_updated_at
FROM rooms r
JOIN room_types rt ON rt.id = r.room_type_id
LEFT JOIN room_assignments ra ON ra.room_id = r.id AND ra.is_cancelled = FALSE
LEFT JOIN bookings b ON b.id = ra.booking_id AND b.status IN ('Active', 'Checked-in')
LEFT JOIN customers c ON c.id = b.customer_id;
