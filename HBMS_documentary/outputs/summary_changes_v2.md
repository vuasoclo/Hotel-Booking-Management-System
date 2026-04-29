# Tóm tắt thay đổi: Tối ưu hóa & Sửa lỗi hệ thống HBMS (V2)

Tài liệu này tóm tắt các cải tiến quan trọng đã thực hiện để hoàn thiện quy trình Đặt phòng và quản lý Dịch vụ.

## 1. Sửa lỗi Quy trình Đặt phòng (Backend)

- **Xử lý Gộp phòng (Fix Duplicate Key):** 
    - Khắc phục lỗi `uq_booking_room_type` khi khách hàng đặt nhiều phòng cùng loại (ví dụ: 1 phòng có bữa sáng và 1 phòng không).
    - Hệ thống tự động gộp số lượng theo loại phòng để lưu vào database nhưng vẫn giữ nguyên tùy chọn bữa sáng cho từng phòng lẻ.
- **Tính toán Phụ phí Bữa sáng:**
    - Tự động tính tiền bữa sáng dựa trên số lượng phòng có đăng ký và số đêm ở (150.000 VND/phòng/đêm).
    - Lưu thông tin vào bảng `booking_surcharges` để đảm bảo hóa đơn hiển thị minh bạch.
- **Tự động Gán phòng (Auto-assignment):** 
    - Tích hợp logic tìm và gán số phòng vật lý ngay khi tạo booking để booking hiển thị ngay lập tức trên Calendar.

## 2. Quản lý Dịch vụ (Services)

- **Mock Data:** Thêm 5 loại dịch vụ phổ biến (Laundry, Airport Transfer, Spa, Mini-bar, Extra Bed) để chạy thử nghiệm.
- **Thêm Dịch vụ cho Booking hiện có:**
    - Bổ sung endpoint `POST /api/bookings/{id}/services`.
    - Cho phép lễ tân thêm dịch vụ phát sinh khi khách đang lưu trú thông qua trang Chi tiết đặt phòng.
- **Đồng bộ hóa dữ liệu:** 
    - Chỉnh sửa API tìm kiếm dịch vụ để hỗ trợ cả hai giao diện (Trang đặt phòng mới và Trang chi tiết).
    - Đảm bảo các trường thông tin như `service_id`, `service_name`, `price`, `category` luôn nhất quán.

## 3. Cải tiến Giao diện (Frontend)

- **Trang New Reservation:**
    - Sửa lỗi giới hạn số lượng phòng: Hệ thống hiện tại kiểm tra tổng số phòng đã chọn của một loại thay vì kiểm tra riêng lẻ.
    - Hiển thị giá Preview chính xác: Giá hiển thị bao gồm cả tiền phòng gốc và phụ phí bữa sáng nếu người dùng tích chọn.
- **Trang Booking Detail:**
    - Kích hoạt nút "Add Service" và tích hợp modal tìm kiếm dịch vụ thực tế từ database.
    - Tự động cập nhật Tổng tiền và Số dư nợ ngay sau khi thêm dịch vụ thành công.

## 4. Ổn định Hệ thống

- **Fix Missing Import:** Sửa lỗi crash backend do thiếu khai báo `AddServiceRequest`.
- **Reset Database:** Tối ưu hóa script nạp dữ liệu mẫu, đảm bảo các bộ đếm ID (Sequence) luôn đồng bộ để không xảy ra lỗi khi tạo bản ghi mới.

---
**Trạng thái:** Hệ thống đã hoạt động ổn định cho các kịch bản đặt phòng phức tạp và quản lý dịch vụ phát sinh.
