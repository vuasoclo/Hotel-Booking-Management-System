# Hotel Booking Management System (HBMS)

Dự án này là hệ thống Quản lý Đặt phòng Khách sạn (HBMS), bao gồm 3 thành phần chính được quản lý và chạy thông qua Docker:
- **Frontend**: Nginx phục vụ các giao diện web ở cổng `3000`.
- **Backend**: FastAPI (Python) cung cấp RESTful API ở cổng `9000`.
- **Database**: PostgreSQL lưu trữ cơ sở dữ liệu ở cổng `5432`.

## Yêu cầu hệ thống
- [Docker](https://www.docker.com/get-started) đã được cài đặt và đang chạy trên máy của bạn.
- [Docker Compose](https://docs.docker.com/compose/install/) (thường đi kèm với cài đặt Docker Desktop).

## Cách chạy dự án

1. **Mở terminal (hoặc Command Prompt / PowerShell)** tại thư mục gốc của dự án (nơi có chứa file `docker-compose.yml`).

2. **Khởi chạy hệ thống**:
   Chạy lệnh sau để build hình ảnh và khởi động tất cả các container ở chế độ nền (detached mode):
   ```bash
   docker-compose up -d --build
   ```

3. **Quá trình khởi tạo**:
   - **Database** sẽ được khởi tạo tự động. Các file SQL trong thư mục `database/` (bao gồm schema `HBMS_full_deployment.sql` và dữ liệu mẫu `HBMS_mock_data.sql`) sẽ được nạp tự động vào lần chạy đầu tiên.
   - **Backend** sẽ tự động đợi cho đến khi Database sẵn sàng (healthy) rồi mới bắt đầu chạy để tránh lỗi kết nối.

4. **Truy cập các dịch vụ**:
   Sau khi lệnh chạy hoàn tất, bạn có thể truy cập dự án qua trình duyệt:
   - **Frontend (Giao diện người dùng)**: [http://localhost:3000](http://localhost:3000)
   - **Backend API (Swagger UI Docs)**: [http://localhost:9000/docs](http://localhost:9000/docs)
   - **Database (PostgreSQL)**:
     - **Host**: `localhost`
     - **Port**: `5432`
     - **User**: `postgres`
     - **Password**: `postgres`
     - **Database**: `hbms`

## Cách dừng dự án

Để dừng hệ thống mà vẫn giữ lại dữ liệu trong database:
```bash
docker-compose down
```

## Làm mới dữ liệu Database
Nếu bạn muốn **xóa sạch toàn bộ dữ liệu hiện tại** và nạp lại dữ liệu mẫu từ đầu, hãy thêm flag `-v` để xóa volume dữ liệu (sau đó hãy chạy lại `docker-compose up -d --build`):
```bash
docker-compose down -v
```

## 📝 Lưu ý phát triển (Development)
- Mã nguồn của `backend/` và `frontend/` được liên kết trực tiếp vào trong container qua Docker Volumes. Nghĩa là khi bạn chỉnh sửa file bên ngoài, code bên trong container cũng cập nhật:
  - **Backend**: FastAPI chạy ở chế độ `--reload` nên sẽ tự động khởi động lại mỗi khi có thay đổi code.
  - **Frontend**: Bạn chỉ cần f5 / làm mới trình duyệt để thấy thay đổi mới nhất.
- Cấu hình môi trường cho Backend nằm tại file `backend/.env`.
