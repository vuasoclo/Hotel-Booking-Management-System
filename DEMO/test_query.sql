BEGIN;
TRUNCATE TABLE
    invoices,
    service_usage,
    services,
    room_assignments,
    booking_surcharges,
    booking_details,
    bookings,
    room_type_inventory,
    rooms,
    room_types,
    surcharge_policies,
    staff,
    customers,
    hotels
RESTART IDENTITY CASCADE;
COMMIT;

INSERT INTO hotels (name, address, hotline) VALUES ('E2E Marina', '99 Test Street', '0909888777');
INSERT INTO customers (full_name, phone_number, email, identity_card, date_of_birth) VALUES ('E2E Guest', '0909000100', 'guest.e2e@hbms.local', 'E2E-ID-0001', DATE '1990-01-01');
INSERT INTO staff (hotel_id, name, role) SELECT id, 'E2E Reception', 'Receptionist' FROM hotels WHERE name = 'E2E Marina';
INSERT INTO surcharge_policies (policy_type, description, multiplier, start_time, end_time, is_active) VALUES ('EarlyCheckIn', 'Early check-in policy', 0.50, TIME '06:00', TIME '14:00', TRUE), ('LateCheckOut', 'Late check-out policy', 0.30, TIME '12:00', TIME '18:00', TRUE);
INSERT INTO room_types (hotel_id, type_name, base_price, max_capacity) SELECT id, x.type_name, x.base_price, x.max_capacity FROM hotels h JOIN (VALUES ('Deluxe', 120.00::DECIMAL(10, 2), 2), ('Suite', 220.00::DECIMAL(10, 2), 3)) AS x(type_name, base_price, max_capacity) ON TRUE WHERE h.name = 'E2E Marina';
INSERT INTO rooms (hotel_id, room_number, room_type_id) SELECT h.id, x.room_number, rt.id FROM hotels h JOIN room_types rt ON rt.hotel_id = h.id JOIN (VALUES ('D101', 'Deluxe'), ('D102', 'Deluxe'), ('S201', 'Suite')) AS x(room_number, type_name) ON x.type_name = rt.type_name WHERE h.name = 'E2E Marina';
INSERT INTO room_type_inventory (room_type_id, date, total_inventory, total_reserved) SELECT rt.id, d::DATE, CASE WHEN rt.type_name = 'Deluxe' THEN 2 ELSE 1 END AS total_inventory, 0 AS total_reserved FROM room_types rt CROSS JOIN generate_series(DATE '2026-07-10', DATE '2026-07-13', INTERVAL '1 day') d WHERE rt.hotel_id = (SELECT id FROM hotels WHERE name = 'E2E Marina');
INSERT INTO services (hotel_id, name, unit_price, category) SELECT id, 'Minibar', 25.00, 'F&B' FROM hotels WHERE name = 'E2E Marina';

DO $$
DECLARE
    v_hotel_id INT; v_customer_id INT; v_staff_id INT; v_rt_deluxe INT; v_rt_suite INT;
    v_room_d101 INT; v_room_d102 INT; v_room_s201 INT;
    v_booking_main INT; v_booking_second INT;
BEGIN
    SELECT id INTO v_hotel_id FROM hotels WHERE name = 'E2E Marina';
    SELECT id INTO v_customer_id FROM customers WHERE phone_number = '0909000100';
    SELECT id INTO v_staff_id FROM staff WHERE name = 'E2E Reception';
    SELECT id INTO v_rt_deluxe FROM room_types WHERE hotel_id = v_hotel_id AND type_name = 'Deluxe';
    SELECT id INTO v_rt_suite FROM room_types WHERE hotel_id = v_hotel_id AND type_name = 'Suite';
    SELECT id INTO v_room_d101 FROM rooms WHERE hotel_id = v_hotel_id AND room_number = 'D101';
    SELECT id INTO v_room_d102 FROM rooms WHERE hotel_id = v_hotel_id AND room_number = 'D102';
    SELECT id INTO v_room_s201 FROM rooms WHERE hotel_id = v_hotel_id AND room_number = 'S201';

    v_booking_main := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-07-10 07:00', TIMESTAMP '2026-07-12 13:00', '22222222-2222-2222-2222-222222222201');
    CALL add_room_detail_to_booking(v_booking_main, v_rt_deluxe, 1, FALSE);
    CALL add_room_detail_to_booking(v_booking_main, v_rt_suite, 1, TRUE);
    CALL finalize_booking(v_booking_main);
    CALL pre_assign_room(v_booking_main, NULL, v_room_d101, v_staff_id);
    CALL pre_assign_room(v_booking_main, NULL, v_room_s201, v_staff_id);

    v_booking_second := begin_booking(v_hotel_id, v_customer_id, TIMESTAMP '2026-07-11 08:00', TIMESTAMP '2026-07-13 11:00', '22222222-2222-2222-2222-222222222202');
    CALL add_room_detail_to_booking(v_booking_second, v_rt_deluxe, 1, FALSE);
    CALL finalize_booking(v_booking_second);
    CALL pre_assign_room(v_booking_second, NULL, v_room_d102, v_staff_id);

    CALL tetrisroom_defrag(v_hotel_id, v_staff_id);
END $$;
