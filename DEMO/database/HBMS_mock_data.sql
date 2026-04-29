-- =============================================================
-- HBMS Mock Data — Siêu Phân Mảnh (Extreme Fragmentation Scenario)
-- =============================================================

-- 1. Hotel
INSERT INTO hotels (name, address, hotline) VALUES
  ('The Grand HBMS', '123 Lê Lợi, Q1, TP.HCM', '028-1234-5678');

-- 2. Staff
INSERT INTO staff (hotel_id, name, role, username, password_hash) VALUES
  (1, 'Nguyễn Admin', 'Admin', 'admin', 'admin123'),
  (1, 'Trần Lễ Tân',  'Staff', 'staff', 'staff123');

-- 3. Customers
INSERT INTO customers (full_name, phone_number, email, identity_card, date_of_birth) VALUES
  ('Khách Cố Định 1', '0901111111', 'c1@email.com', '07901', '1990-01-01'),
  ('Khách Cố Định 2', '0902222222', 'c2@email.com', '07902', '1990-01-01'),
  ('Khách Vãng Lai A', '0903333333', 'ca@email.com', '07903', '1990-01-01'),
  ('Khách Vãng Lai B', '0904444444', 'cb@email.com', '07904', '1990-01-01'),
  ('Khách Vãng Lai C', '0905555555', 'cc@email.com', '07905', '1990-01-01');

-- 5. Room Types
INSERT INTO room_types (hotel_id, type_name, base_price, max_capacity) VALUES
  (1, 'Standard',  800000, 2),
  (1, 'Deluxe',   1200000, 2),
  (1, 'Suite',    2500000, 4);

-- 6. Rooms (Standard: 101, 102, 104 | Deluxe: 201, 202 | Suite: 301, 302)
INSERT INTO rooms (hotel_id, room_number, room_type_id, status) VALUES
  (1, '101', 1, 'Available'), (1, '102', 1, 'Available'), (1, '104', 1, 'Available'),
  (1, '201', 2, 'Available'), (1, '202', 2, 'Available'),
  (1, '301', 3, 'Available'), (1, '302', 3, 'Available');

-- 8. Inventory (30 ngày)
INSERT INTO room_type_inventory (room_type_id, date, total_inventory, total_reserved)
SELECT rt.id, d::DATE, 3, 0 FROM room_types rt CROSS JOIN generate_series(CURRENT_DATE - 5, CURRENT_DATE + 25, '1 day') d;

-- =============================================================================
-- KỊCH BẢN PHÂN MẢNH TRÊN PHÒNG STANDARD (101, 102, 104)
-- =============================================================================

-- A. CÁC KHỐI CỐ ĐỊNH (CHECKED-IN) - Thuật toán KHÔNG ĐƯỢC di chuyển
-- -----------------------------------------------------------------------------
-- Booking 1: Phòng 101 (Đang ở: Hôm qua -> Mốt)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key)
VALUES (1, 1, 1, 'Checked-in', CURRENT_DATE - 1 + time '14:00', CURRENT_DATE + 2 + time '12:00', 2400000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (1, 1, 1, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (1, 1, CURRENT_DATE - 1 + time '14:00', CURRENT_DATE + 2 + time '12:00');
UPDATE rooms SET status = 'Occupied' WHERE room_number = '101';

-- Booking 2: Phòng 104 (Đang ở: 2 ngày trước -> Mai)
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key)
VALUES (2, 1, 2, 'Checked-in', CURRENT_DATE - 2 + time '14:00', CURRENT_DATE + 1 + time '12:00', 2400000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (2, 1, 1, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (2, 3, CURRENT_DATE - 2 + time '14:00', CURRENT_DATE + 1 + time '12:00');
UPDATE rooms SET status = 'Occupied' WHERE room_number = '104';

-- B. CÁC KHỐI PHÂN MẢNH (ACTIVE) - Thuật toán SẼ di chuyển dồn lại
-- -----------------------------------------------------------------------------
-- Booking 3: Phòng 102 (Ngày 1 -> Ngày 2) - Nằm giữa 2 khối cố định
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key)
VALUES (3, 1, 3, 'Active', CURRENT_DATE + 1 + time '14:00', CURRENT_DATE + 2 + time '12:00', 800000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (3, 1, 1, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (3, 2, CURRENT_DATE + 1 + time '14:00', CURRENT_DATE + 2 + time '12:00');

-- Booking 4: Phòng 104 (Ngày 2 -> Ngày 4) - Nối đuôi Booking 2 cố định
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key)
VALUES (4, 1, 4, 'Active', CURRENT_DATE + 2 + time '14:00', CURRENT_DATE + 4 + time '12:00', 1600000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (4, 1, 1, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (4, 3, CURRENT_DATE + 2 + time '14:00', CURRENT_DATE + 4 + time '12:00');

-- Booking 5: Phòng 101 (Ngày 3 -> Ngày 6) - Nối đuôi Booking 1 cố định
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key)
VALUES (5, 1, 5, 'Active', CURRENT_DATE + 3 + time '14:00', CURRENT_DATE + 6 + time '12:00', 2400000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (5, 1, 1, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (5, 1, CURRENT_DATE + 3 + time '14:00', CURRENT_DATE + 6 + time '12:00');

-- Booking 6: Phòng 102 (Ngày 4 -> Ngày 5) - Tạo thêm 1 mảnh lẻ
INSERT INTO bookings (id, hotel_id, customer_id, status, check_in, check_out, total_amount, idempotency_key)
VALUES (6, 1, 1, 'Active', CURRENT_DATE + 4 + time '14:00', CURRENT_DATE + 5 + time '12:00', 800000, gen_random_uuid());
INSERT INTO booking_details (booking_id, room_type_id, quantity, agreed_price) VALUES (6, 1, 1, 800000);
INSERT INTO room_assignments (booking_id, room_id, check_in, check_out) VALUES (6, 2, CURRENT_DATE + 4 + time '14:00', CURRENT_DATE + 5 + time '12:00');

-- C. ĐỒNG BỘ INVENTORY
UPDATE room_type_inventory SET total_reserved = total_reserved + 1 WHERE room_type_id = 1 AND date BETWEEN CURRENT_DATE - 2 AND CURRENT_DATE + 6;
