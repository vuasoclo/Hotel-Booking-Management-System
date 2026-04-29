# Tóm tắt thay đổi: Tối ưu hóa quy trình Đặt phòng (HBMS)

Tài liệu này tóm tắt các cải tiến quan trọng được thực hiện để giải quyết lỗi đặt phòng, đảm bảo tính nhất quán dữ liệu và cải thiện trải nghiệm người dùng trong hệ thống HBMS.

## 1. Backend: Quy trình Đặt phòng Nguyên tử (Atomic Booking)

Thay vì thực hiện nhiều yêu cầu API riêng lẻ, chúng tôi đã hợp nhất toàn bộ quy trình vào một endpoint duy nhất: `POST /api/bookings/create`.

- **Tính nguyên tử (Atomicity):** Toàn bộ các bước (tạo booking, thêm chi tiết phòng, tính phụ phí, gán phòng vật lý, thêm dịch vụ) được bọc trong một transaction cơ sở dữ liệu duy nhất. Nếu bất kỳ bước nào thất bại, toàn bộ quá trình sẽ được rollback.
- **Xử lý Idempotency (Chống trùng lặp):** 
    - Sử dụng `idempotency_key` (UUID) để ngăn chặn việc tạo trùng booking khi người dùng nhấn nút nhiều lần.
    - Chuyển từ logic `SAVEPOINT` phức tạp sang `INSERT ... ON CONFLICT DO NOTHING`. Điều này cho phép hệ thống nhận diện booking đã tồn tại và trả về ID cũ mà không làm hỏng transaction hiện tại.
- **Gán phòng tự động (Auto-assignment):**
    - Tích hợp logic tìm kiếm phòng vật lý còn trống dựa trên loại phòng và khoảng thời gian (sử dụng `tsrange` và toán tử overlap `&&` của PostgreSQL).
    - Khắc phục lỗi sai thứ tự tham số SQL gây ra lỗi ép kiểu dữ liệu (integer vs timestamp).
- **Tính toán lại tổng tiền:**
    - Thêm lệnh gọi thủ công `recalculate_booking_total()` sau khi finalize booking. Điều này đảm bảo `total_amount` luôn được cập nhật chính xác bao gồm cả giá phòng và phụ phí thời gian, thay vì chỉ dựa vào trigger của bảng dịch vụ.

## 2. Frontend: Cải tiến giao diện "New Reservation"

- **Hợp nhất API:** Chuyển từ flow 3 bước fetch (`/begin` -> `/add_detail` -> `/finalize`) sang 1 bước gọi `/api/bookings/create`.
- **Ngày mặc định thông minh:**
    - Tự động điền ngày Check-in là **Hôm nay + 1** (14:00) và Check-out là **Hôm nay + 2** (12:00).
    - Điều này giúp các booking mới tạo luôn hiển thị ngay lập tức trên Calendar (vốn mặc định hiển thị từ ngày hiện tại).
- **Xử lý lỗi chi tiết:** Hiển thị thông báo cụ thể cho người dùng nếu hệ thống hết phòng vật lý (`ROOM_ASSIGN_FAILED`) hoặc có lỗi dữ liệu.

## 3. Database & Mock Data

- **Reset Sequence:** Thêm các lệnh `SELECT setval(...)` vào cuối file seed data. Việc này cực kỳ quan trọng để đồng bộ lại bộ đếm ID tự động (SERIAL) sau khi đã insert dữ liệu mẫu với ID cố định, tránh lỗi `unique_violation` khi ứng dụng tạo bản ghi mới.
- **Logic Inventory động:** 
    - Cập nhật `HBMS_mock_data.sql` để `total_inventory` được tính bằng `COUNT` thực tế từ bảng `rooms`, thay vì giá trị hardcode (trước đây Suite có 2 phòng nhưng inventory báo 3).
    - Cập nhật `total_reserved` bằng subquery quét toàn bộ booking thực tế để đảm bảo tính chính xác tuyệt đối của dữ liệu mẫu.

## 4. Các sửa lỗi nhỏ khác

- **Cấu hình Port:** Đồng bộ hóa tất cả các yêu cầu fetch ở frontend sang port `9000` (port mặc định của backend trong Docker).
- **Database Helper:** Thêm hàm `execute_in_transaction` trong `backend/utils/db.py` để quản lý kết nối và transaction tập trung.

---
**Trạng thái hiện tại:** Quy trình đặt phòng đã hoạt động ổn định, tính toán giá đúng, tự động gán phòng và hiển thị chính xác trên Calendar.
