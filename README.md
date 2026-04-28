# Hotel-Booking-Management-System

Dự án **đã sẵn sàng để chạy**, tôi đã cài đặt xong các thư viện và khởi động server chạy ngầm cho bạn.

Dưới đây là 3 bước để bạn vận hành và kiểm tra kết quả ngay lập tức:

### Bước 1: Cấu hình Database (Quan trọng nhất)
Vì tôi không biết mật khẩu PostgreSQL của bạn, bạn cần mở file này và sửa lại thông tin:
*   **File:** `DEMO/backend/.env`
*   **Sửa:** Thay `yourpassword` bằng mật khẩu thực tế của bạn và kiểm tra `DB_NAME` xem có đúng tên database bạn đã tạo trong SQL không.

### Bước 2: Truy cập giao diện và API
Mở trình duyệt và truy cập các địa chỉ sau:

1.  **Giao diện chính:** [http://127.0.0.1:8000](http://127.0.0.1:8000)
    *   Hệ thống sẽ mở trang `index.html`. Bạn có thể dùng tài khoản demo đã tạo để đăng nhập.
2.  **Trang quản lý API (Swagger):** [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)
    *   Đây là nơi "thần thánh" nhất cho đồ án DBMS. Bạn sẽ thấy danh sách 21 endpoints. Thử bấm vào một cái (ví dụ: `GET /api/rooms/status`), chọn **Try it out** -> **Execute**. Nếu thông tin database ở Bước 1 đúng, bạn sẽ thấy dữ liệu từ các bảng SQL hiện ra ngay tại đây.

### Bước 3: Cách khởi động lại (Nếu bạn tắt máy hoặc tắt terminal)
Sau này, mỗi khi muốn chạy lại dự án, bạn chỉ cần làm 2 việc:

1.  Mở Terminal tại thư mục `DEMO/backend/`.
2.  Gõ lệnh sau:
    ```bash
    uvicorn main:app --reload
    ```

---

### Lưu ý nhỏ:
*   **Database:** Hãy đảm bảo bạn đã chạy file `HBMS_full_deployment.sql` trong PostgreSQL để có đủ các Procedure và View mà Backend đang gọi.
*   **Frontend:** Hiện tại các file HTML vẫn đang dùng dữ liệu Mock (giả lập). Để dự án chạy hoàn toàn bằng dữ liệu thật, bạn chỉ cần thay phần code Javascript từ `const data = [...]` sang `const res = await fetch('/api/...')`.

**Bạn có muốn tôi hỗ trợ thay code "Dữ liệu thật" cho một trang cụ thể (ví dụ: `rooms.html`) để bạn làm mẫu không?**