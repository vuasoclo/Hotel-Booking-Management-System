Dưới đây là chiến lược chia nhỏ task và bộ prompt được thiết kế chuyên biệt để đưa cho AI (Codex/Copilot) thực thi việc code file DDL HBMS_full_deployment.sql cũng như seed data và chạy Test Cases. 

Việc chia làm **5 Phase (5 câu prompt)** sẽ giúp AI duy trì được dải ngữ cảnh (context window) chuẩn xác nhất, không bị bỏ sót các Trigger hay Constraint phức tạp. Bạn copy từng prompt dưới đây và gửi lần lượt cho AI nhé:

---

### PHẦN 1: TẠO SCHEMA & CẤU TRÚC BẢNG CỐT LÕI (DDL)
**Mục tiêu:** Xây dựng móng Database, Enum, các bảng danh mục và bảng giao dịch với đầy đủ Constraint.

**Prompt 1:**
```text
Bạn là PostgreSQL Database Architect. Nhiệm vụ của bạn là khởi tạo file `src/HBMS_full_deployment.sql`. 
Hãy đọc 2 file `Đặc tả_Physical_Schema.md` và phần 1 của `Đặc tả_Reporting_Views.md`.
Thực hiện viết code SQL DDL tạo bảng theo đúng thứ tự logic (tránh lỗi khóa ngoại) cho các đối tượng sau:
1. Tạo toàn bộ ENUM (booking_status, room_status, surcharge_type, invoice_status).
2. Tạo extension `btree_gist` nếu chưa có.
3. Tạo các bảng theo thứ tự: hotels, customers, staff, surcharge_policies, room_types, rooms, room_type_inventory.
4. Tạo các bảng giao dịch: bookings, booking_details, booking_surcharges, room_assignments.
5. Tạo các bảng module Reporting: services, service_usage, invoices.
Yêu cầu:
- Bao gồm đầy đủ CHECK constraints (vd: tuổi >= 18 trong customers, check_out > check_in).
- Bao gồm EXCLUDE constraint chống trùng thời gian trong bảng `room_assignments`.
- Chú ý thêm ràng buộc `UNIQUE` và quy tắc `ON DELETE CASCADE/RESTRICT` như trong đặc tả.
- Không viết code của Trigger hay SP ở bước này, chỉ bảng và cấu trúc.
```

### PHẦN 2: CÁC TRIGGER TỰ ĐỘNG HÓA & AUDIT
**Mục tiêu:** Thiết lập các Automations chìm của database như lưu lịch sử giá, tự update tiền, nhả tồn kho.

**Prompt 2:**
```text
Tiếp tục xử lý file `src/HBMS_full_deployment.sql`. Hãy đọc `Đặc tả_Physical_Schema.md` (phần 6), `Đặc tả_Database_Programmability.md` (phần 1 & phần trigger nhả inventory) và `Đặc tả_Reporting_Views.md` (phần 2).
Hãy viết code SQL PL/pgSQL để append vào cuối file các hàm và trigger sau:
1. Hàm và Trigger `touch_updated_at()` gán cho bảng `rooms` và `bookings` chạy BEFORE UPDATE.
2. Hàm và Trigger `set_agreed_price()` (Snapshot giá) gán cho bảng `booking_details` chạy BEFORE INSERT.
3. Hàm và Trigger `release_inventory_on_cancel()` gán cho bảng `bookings` chạy BEFORE UPDATE khi status chuyển thành 'Cancelled'.
4. Hàm và Trigger `sync_total_amount()` gán cho bảng `service_usage` chạy AFTER INSERT/UPDATE/DELETE để cập nhật tổng tiền về `bookings.total_amount`.
Yêu cầu: Code phải xử lý chặt chẽ logic vòng lặp trừ tồn kho và cover các edge-cases khi tính tổng giá.
```

### PHẦN 3: STORED PROCEDURES - ĐẶT PHÒNG & TÍNH PHỤ THU
**Mục tiêu:** Cài đặt logic pha 1 (Reserve) và tự động tính các loại phí.

**Prompt 3:**
```text
Tiếp tục xử lý file `src/HBMS_full_deployment.sql`. Hãy đọc kỹ `Đặc tả_Database_Programmability.md` (các phần còn lại).
Hãy viết code SQL PL/pgSQL để tạo 2 functions/procedures cốt lõi sau:
1. Function `apply_time_surcharges(p_booking_id INT)`: Xóa các khoản phụ thu Early/Late cũ (chống trùng lặp); sau đó quét time check_in/check_out để join với `surcharge_policies` rồi lưu vào `booking_surcharges`.
2. Procedure `create_reservation(...)`: Insert Idempotency, cập nhật tồn kho `room_type_inventory` qua vòng lặp SELECT FOR UPDATE, và kích hoạt hàm `apply_time_surcharges()` ở dòng cuối. 
Yêu cầu: 
- Quản lý mã lỗi bằng `RAISE EXCEPTION ... USING ERRCODE`.
- Không sử dụng lệnh COMMIT bên trong Procedure (đã bỏ theo yêu cầu thiết kế).
```

### PHẦN 4: VÒNG ĐỜI PHÒNG, CHECK-IN, CHECK-OUT & VIEWS BÁO CÁO
**Mục tiêu:** Hoàn thiện Phase 2 (Gán phòng) và tầng đọc dữ liệu tổng hợp.

**Prompt 4:**
```text
Tiếp tục xử lý file `src/HBMS_full_deployment.sql`. Đọc file `Đặc tả_Room_Operations.md` và phần 3 của `Đặc tả_Reporting_Views.md`.
Cập nhật file với các tính năng sau:
1. Tạo 2 index trạng thái cho bảng `bookings` và `rooms`.
2. Tạo 3 Stored Procedures: `check_in_booking`, `check_out_booking`, `housekeeping_complete`. Tuân thủ chặt State Machine (Active -> Checked-in, Available -> Occupied -> Dirty -> Available) và throw đúng mã lỗi P0010, P0011, P0012, P0013.
3. Cập nhật calculation logic trả về `total_amount` ở bước check_out.
4. Khởi tạo 4 Views báo cáo: `v_daily_occupancy`, `v_monthly_revenue`, `v_booking_summary`, `v_room_status_now`.
Yêu cầu: Dùng chuẩn JOIN và CTE để tránh lỗi Duplicate value ở view `v_monthly_revenue`.
```

### PHẦN 5: SEED DATA & KIỂM THỬ (TEST PLAN SCRIPT)
**Mục tiêu:** Sinh kịch bản dữ liệu mẫu và Script Test (có chặn Try/Catch) mô phỏng chính xác hành vi của Application gọi xuống db.

**Prompt 5:**
```text
Hãy tạo một file TÁCH BIỆT là `src/HBMS_test_execution.sql`.
Đọc file `Đặc tả_Database_Test_Plan.md` chứa danh sách 14 Test Cases (TC-01 đến TC-14) và 11 TC operations/views (TC-20->25, TC-30->35).
Thực hiện viết code:
1. SEED DATA block: Tạo 1 hotel, 1 customer (cùng 1 customer dưới 18 tuổi để test TC-14), 1 staff. Tạo chính sách Surcharge 'EarlyCheckIn' từ 06:00 tới 14:00 mức 0.5. Tạo phòng 'Deluxe' (base_price 100) và 3 phòng vật lý D101, D102, D103. Mở tồn kho cho ngày `2026-05-01` tới `2026-05-05` với total 3 phòng.
2. TEST EXECUTION block: Thay vì chỉ viết câu query mù, hãy viết code trong `DO $$ BLOCK` có chứa các câu lệnh `CALL` và `INSERT`. Sử dụng khối `EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Test X passed: %', SQLERRM` để database không bị gãy khi cố tình test các ca báo lỗi (Overbooking, Invalid check-in state, duplicate UID, constraints age).
Yêu cầu: Khối lệnh test phải phản ánh việc DBMS tự động bắt lỗi và báo thành công trên PostgreSQL output Console.
```

---

**Cách làm việc hiệu quả với AI:**
Mở luồng chat mới hoặc gửi lần lượt. Sau mỗi lệnh, hãy yêu cầu AI *không in full code ra chat* mà **viết thẳng bằng tool/edit file HBMS_full_deployment.sql** để tiết kiệm độ dài token text sinh ra.