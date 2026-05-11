-- =============================================================
-- HBMS Mock Data — Siêu Phân Mảnh V2 (Advanced Fragmentation)
-- =============================================================

-- 1. Hotels (Đã thêm 2 khách sạn mới)
INSERT INTO hotels (name, address, hotline) VALUES
  ('The Grand HBMS', '123 Lê Lợi, Q1, TP.HCM', '028-1234-5678'),
  ('Ocean View Hotel', '456 Trần Phú, Nha Trang', '0258-333-4444'),
  ('Mountain Retreat', '789 Nguyễn Chí Thanh, Đà Lạt', '0263-555-6666');

-- 2. Staff (Giữ 2 tài khoản, gán cho khách sạn chính)
INSERT INTO staff (hotel_id, name, role, username, password_hash) VALUES
  (1, 'Nguyễn Admin', 'Admin', 'admin', 'adminpassword'),
  (1, 'Trần Lễ Tân',  'Staff', 'staff', 'staffpassword');

-- 3. Customers (5 hồ sơ khách hàng với tên tự nhiên)
INSERT INTO customers (full_name, phone_number, email, identity_card, date_of_birth) VALUES
  ('Trần Văn Hùng', '0901111111', 'hung.tran@email.com', '07901', '1985-05-12'), -- Cố định 1
  ('Lê Thị Mai', '0902222222', 'mai.le@email.com', '07902', '1992-08-24'),    -- Cố định 2
  ('Phạm Tuấn Anh', '0903333333', 'anh.pt@email.com', '07903', '1995-11-03'),  -- Vãng lai A
  ('Nguyễn Hoàng Yến', '0904444444', 'yen.nh@email.com', '07904', '1998-02-15'), -- Vãng lai B
  ('Vũ Đức Trí', '0905555555', 'tri.vu@email.com', '07905', '1990-12-09');     -- Vãng lai C

-- 4. Room Types
INSERT INTO room_types (hotel_id, type_name, base_price, max_capacity) VALUES
  (1, 'Standard',  800000, 2),
  (1, 'Deluxe',   1200000, 2),
  (1, 'Suite',    2500000, 4);

-- 5. Rooms (Tổng 14 phòng vật lý: 5 Standard, 5 Deluxe, 4 Suite)
-- Standard: ID từ 1 -> 5 | Deluxe: ID từ 6 -> 10 | Suite: ID từ 11 -> 14
INSERT INTO rooms (hotel_id, room_number, room_type_id, status) VALUES
  (1, '101', 1, 'Available'), (1, '102', 1, 'Available'), (1, '103', 1, 'Available'), (1, '104', 1, 'Available'), (1, '105', 1, 'Available'),
  (1, '201', 2, 'Available'), (1, '202', 2, 'Available'), (1, '203', 2, 'Available'), (1, '204', 2, 'Available'), (1, '205', 2, 'Available'),
  (1, '301', 3, 'Available'), (1, '302', 3, 'Available'), (1, '303', 3, 'Available'), (1, '304', 3, 'Available');

-- 6. Services (10 Dịch vụ được phân loại rõ ràng)
INSERT INTO services (hotel_id, name, unit_price, category) VALUES
  (1, 'Laundry Service', 50000, 'Housekeeping'),
  (1, 'Airport Transfer', 350000, 'Transportation'),
  (1, 'Spa Massage 60p', 500000, 'Wellness'),
  (1, 'Mini-bar Snack', 25000, 'F&B'),
  (1, 'Extra Bed', 200000, 'Room'),
  (1, 'Morning Buffet', 150000, 'F&B'),
  (1, 'Room Cleaning Extra', 100000, 'Housekeeping'),
  (1, 'Motorbike Rental', 150000, 'Transportation'),
  (1, 'Sauna Access', 250000, 'Wellness'),
  (1, 'Late Check-out', 300000, 'Room');

-- 7. Inventory (30 ngày: Từ quá khứ 5 ngày đến tương lai 25 ngày)
INSERT INTO room_type_inventory (room_type_id, date, total_inventory, total_reserved)
SELECT
    rt.id,
    d::DATE,
    COUNT(r.id)::INT AS total_inventory, 
    0               AS total_reserved
FROM room_types rt
CROSS JOIN generate_series(CURRENT_DATE - 5, CURRENT_DATE + 25, '1 day') d
LEFT  JOIN rooms r ON r.room_type_id = rt.id
GROUP BY rt.id, d::DATE;

-- =============================================================================
-- 8. KỊCH BẢN ĐẶT PHÒNG SIÊU PHÂN MẢNH (13 BOOKINGS)
-- Focus: Standard (101-105) & Deluxe (201-205).
-- Data test thời gian lẻ tới từng phút (14:15, 11:45...)
-- =============================================================================

-- [B1] Khối Cố Định (Checked-in): 1 Standard. (Hôm qua -> Ngày mai)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (1, 1, 1, 'Checked-in', CURRENT_DATE - 1 + time '14:15', CURRENT_DATE + 2 + time '12:00', 2400000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (1, 1, 1, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (1, 1, CURRENT_DATE - 1 + time '14:15', CURRENT_DATE + 2 + time '12:00'); -- Phòng 101
UPDATE rooms SET status = 'Occupied' WHERE id = 1;

-- [B2] Khối Cố Định (Checked-in): 1 Deluxe. (2 Hôm trước -> Mai)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (2, 1, 2, 'Checked-in', CURRENT_DATE - 2 + time '15:30', CURRENT_DATE + 1 + time '11:00', 3600000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (2, 2, 1, 1200000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (2, 6, CURRENT_DATE - 2 + time '15:30', CURRENT_DATE + 1 + time '11:00'); -- Phòng 201
UPDATE rooms SET status = 'Occupied' WHERE id = 6;

-- [B3] 2 Phòng cùng loại (Standard): Tạo khoảng kẹp giữa. (Mai -> Ngày 3)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (3, 1, 3, 'Active', CURRENT_DATE + 1 + time '14:00', CURRENT_DATE + 3 + time '12:00', 3200000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (3, 1, 2, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES 
  (3, 2, CURRENT_DATE + 1 + time '14:00', CURRENT_DATE + 3 + time '12:00'), -- Phòng 102
  (3, 3, CURRENT_DATE + 1 + time '14:00', CURRENT_DATE + 3 + time '12:00'); -- Phòng 103

-- [B4] 2 Phòng cùng loại (Deluxe): Đặt ngắn ngày tạo mảng vụn. (Mai -> Ngày mốt)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (4, 1, 4, 'Active', CURRENT_DATE + 1 + time '14:30', CURRENT_DATE + 2 + time '12:00', 2400000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (4, 2, 2, 1200000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES 
  (4, 7, CURRENT_DATE + 1 + time '14:30', CURRENT_DATE + 2 + time '12:00'), -- Phòng 202
  (4, 8, CURRENT_DATE + 1 + time '14:30', CURRENT_DATE + 2 + time '12:00'); -- Phòng 203

-- [B5] 2 Phòng KHÁC loại (1 Standard, 1 Deluxe): Gây khó cho việc xếp lịch. (Ngày 2 -> Ngày 4)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (5, 1, 5, 'Active', CURRENT_DATE + 2 + time '13:15', CURRENT_DATE + 4 + time '12:45', 4000000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES 
  (5, 1, 1, 800000), (5, 2, 1, 1200000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES 
  (5, 4, CURRENT_DATE + 2 + time '13:15', CURRENT_DATE + 4 + time '12:45'), -- Phòng 104 (Std)
  (5, 9, CURRENT_DATE + 2 + time '13:15', CURRENT_DATE + 4 + time '12:45'); -- Phòng 204 (Dlx)

-- [B6] Nối đuôi B1: 1 Standard. (Ngày 2 -> Ngày 5)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (6, 1, 1, 'Active', CURRENT_DATE + 2 + time '14:00', CURRENT_DATE + 5 + time '11:45', 2400000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (6, 1, 1, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (6, 1, CURRENT_DATE + 2 + time '14:00', CURRENT_DATE + 5 + time '11:45'); -- Phòng 101

-- [B7] Nối đuôi B2: 1 Deluxe. (Mai -> Ngày 3)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (7, 1, 2, 'Active', CURRENT_DATE + 1 + time '13:00', CURRENT_DATE + 3 + time '12:30', 2400000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (7, 2, 1, 1200000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (7, 6, CURRENT_DATE + 1 + time '13:00', CURRENT_DATE + 3 + time '12:30'); -- Phòng 201

-- [B8] 2 Phòng cùng loại (Standard). (Ngày 3 -> Ngày 6)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (8, 1, 3, 'Active', CURRENT_DATE + 3 + time '14:15', CURRENT_DATE + 6 + time '12:00', 4800000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (8, 1, 2, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES 
  (8, 2, CURRENT_DATE + 3 + time '14:15', CURRENT_DATE + 6 + time '12:00'), -- Phòng 102
  (8, 5, CURRENT_DATE + 3 + time '14:15', CURRENT_DATE + 6 + time '12:00'); -- Phòng 105

-- [B9] Booking chèn giữa hiện tại (Checked-in): 1 Deluxe. (Nay -> Ngày 2)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (9, 1, 4, 'Checked-in', CURRENT_DATE + time '12:00', CURRENT_DATE + 2 + time '11:00', 2400000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (9, 2, 1, 1200000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (9, 10, CURRENT_DATE + time '12:00', CURRENT_DATE + 2 + time '11:00'); -- Phòng 205
UPDATE rooms SET status = 'Occupied' WHERE id = 10;

-- [B10] 2 Phòng KHÁC loại (1 Standard, 1 Deluxe): Khớp với khe trống sau B3 & B4. (Ngày 4 -> Ngày 7)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (10, 1, 5, 'Active', CURRENT_DATE + 4 + time '14:30', CURRENT_DATE + 7 + time '12:00', 6000000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES 
  (10, 1, 1, 800000), (10, 2, 1, 1200000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES 
  (10, 3, CURRENT_DATE + 4 + time '14:30', CURRENT_DATE + 7 + time '12:00'), -- Phòng 103 (Std)
  (10, 7, CURRENT_DATE + 4 + time '14:30', CURRENT_DATE + 7 + time '12:00'); -- Phòng 202 (Dlx)

-- [B11] 1 Standard ngắn ngày mảng vụn. (Ngày 5 -> Ngày 6)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (11, 1, 1, 'Active', CURRENT_DATE + 5 + time '14:00', CURRENT_DATE + 6 + time '12:00', 800000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (11, 1, 1, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (11, 4, CURRENT_DATE + 5 + time '14:00', CURRENT_DATE + 6 + time '12:00'); -- Phòng 104

-- [B12] 2 Phòng cùng loại (Deluxe). (Ngày 5 -> Ngày 8)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (12, 1, 2, 'Active', CURRENT_DATE + 5 + time '15:00', CURRENT_DATE + 8 + time '11:30', 7200000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (12, 2, 2, 1200000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES 
  (12, 8, CURRENT_DATE + 5 + time '15:00', CURRENT_DATE + 8 + time '11:30'), -- Phòng 203
  (12, 9, CURRENT_DATE + 5 + time '15:00', CURRENT_DATE + 8 + time '11:30'); -- Phòng 204

-- [B13] Nối đuôi B6: 1 Standard. (Ngày 6 -> Ngày 9)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key) VALUES (13, 1, 3, 'Active', CURRENT_DATE + 6 + time '13:30', CURRENT_DATE + 9 + time '12:00', 2400000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (13, 1, 1, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (13, 1, CURRENT_DATE + 6 + time '13:30', CURRENT_DATE + 9 + time '12:00'); -- Phòng 101


-- =============================================================================
-- 9. ĐỒNG BỘ INVENTORY
-- =============================================================================
UPDATE room_type_inventory rti
SET total_reserved = (
    SELECT COALESCE(SUM(bd.quantity), 0)
    FROM booking_details bd
    JOIN bookings b ON b.id = bd.booking_id
    WHERE bd.room_type_id = rti.room_type_id
      AND b.status IN ('Pending', 'Active', 'Checked-in')
      AND b.check_in::DATE  <= rti.date
      AND b.check_out::DATE >  rti.date
);

-- =============================================================================
-- 10. RESET SEQUENCES
-- =============================================================================
SELECT setval(pg_get_serial_sequence('bookings',         'id'), MAX(id)) FROM bookings;
SELECT setval(pg_get_serial_sequence('booking_details',  'id'), MAX(id)) FROM booking_details;
SELECT setval(pg_get_serial_sequence('room_assignments', 'id'), MAX(id)) FROM room_assignments;
SELECT setval(pg_get_serial_sequence('hotels',           'id'), MAX(id)) FROM hotels;
SELECT setval(pg_get_serial_sequence('customers',        'id'), MAX(id)) FROM customers;
SELECT setval(pg_get_serial_sequence('staff',            'id'), MAX(id)) FROM staff;
SELECT setval(pg_get_serial_sequence('room_types',       'id'), MAX(id)) FROM room_types;
SELECT setval(pg_get_serial_sequence('rooms',            'id'), MAX(id)) FROM rooms;
SELECT setval(pg_get_serial_sequence('services',         'id'), MAX(id)) FROM services WHERE id IS NOT NULL;