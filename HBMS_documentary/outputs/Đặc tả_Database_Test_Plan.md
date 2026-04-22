# DATABASE TEST PLAN
_Giai đoạn: Thiết kế & Kiểm thử DBMS Backend_

## Mục đích
Tài liệu này xác định các kịch bản kiểm thử (Test Cases/Test Scenarios) nhằm đảm bảo cấu trúc Database, các Ràng buộc (Constraints) và Trigger hoạt động đúng logic nghiệp vụ của mô hình Đặt phòng 2 pha (Hybrid).

---

## Môi trường & Test Data
1. Khởi tạo `room_types`:
   - 1 `Deluxe`, tổng 3 phòng, giá 100$.
2. Khởi tạo `rooms`:
   - D101, D102, D103 (thuộc `Deluxe`).
3. Dữ liệu Inventory `room_type_inventory`:
   - Ngày `2026-05-01`: 3 phòng `Deluxe`, `total_reserved=0`.

---

## Kịch bản Kiểm thử

### STT | Tên Kịch bản | Phương pháp Kiểm thử | Kết quả Mong đợi |
| --- | --- | --- | --- |
| **TC-01** | Tạo Reservation hợp lệ | `INSERT` đơn cho loại `Deluxe` ngày `2026-05-01` số lượng 1 phòng. | Thành công. Inventory update `total_reserved` lên 1. |
| **TC-02** | Chống Overbooking Loại phòng | Tính từ **TC-01**, liên tục `INSERT` 3 đơn nữa cho ngày `2026-05-01`. | Lỗi CHECK `no_overbook` xảy ra ở `room_type_inventory` khi tổng `reserved` chạm 4 (Limit là 3). |
| **TC-03** | Auto giá Snapshot pha 1 | `INSERT` booking, test kiểm tra Trigger có lấy đúng giá 100$ từ bang `room_types` vào `agreed_price` hay không. Sửa giá gốc thành 120$ và kiểm tra lại `agreed_price`. | Thành công ở booking 1. Booking sau 120$. Đơn cũ không thay giá. |
| **TC-04** | Check-in Gán phòng | Mở màn Check-in cho đơn **TC-01**. Gán `Room=D101`. | `INSERT` vào `room_assignments` thành công. Trạng thái Booking -> `Checked-in`. |
| **TC-05** | Chặn Duplicate Check-in (EXCLUDE) | Từ **TC-04**, mở màn định Check-in thêm 1 Booking khác vào `Room=D101` trùng ngày. | Lỗi EXCLUDE `exclude_overlapping_assignments` báo vi phạm khoảng thời gian. |
| **TC-06** | Hủy Booking (Soft Delete) | `UPDATE status = 'Cancelled'` cho Booking **TC-01**. | `cancelled_at` không bị NULL. Record trong báo cáo inventory nhả ra lại số phòng. |
| **TC-07** | EXCLUDE cho phép Booking Hủy | Thử xếp 1 khách vào lại `Room=D101` (ngay ngày của Booking cũ đã bị Cancelled ở **TC-06**). | `INSERT` thành công, do EXCLUDE có mệnh đề `WHERE` bỏ qua Booking bị `Cancelled`. |
| **TC-08** | Idempotency Key chống rác | Front-end gửi 2 lượt API tạo Booking mã UID `ABCD-1234`. | Lần 2 báo lỗi `UNIQUE` do Database phát hiện `idempotency_key` đã tồn tại. |
| **TC-09** | Xóa phòng khi còn Booking FK RESTRICT | Cố tình gọi `DELETE FROM room_types WHERE type_name = 'Deluxe'`. | Lỗi do khóa ngoại `ON DELETE RESTRICT`. |
| **TC-10** | Xóa Bookings Parent FK CASCADE | Gọi lệnh `DELETE FROM bookings WHERE id = 1` (Theo logic nên chặn). Nếu xóa, `Booking_Details` và `Room_Assignments` phải mất theo. | Bị chặn từ đầu (Application Rule: Soft Delete). Tuy nhiên DBMS constraint sẽ chạy `CASCADE` nếu force chạy qua CLI. |
| **TC-11** | Audit Field Trigger | Sửa thông báo mô tả của `Rooms` bằng lệnh `UPDATE`. | Trigger `touch_updated_at` nhảy, thay đổi thời gian `updated_at`. |