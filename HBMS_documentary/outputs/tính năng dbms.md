**Bảng 1: Mô tả các chức năng triển khai trên PostgreSQL**

| Tên Chức năng                        | Đối tượng DBMS (Object)      |
| :----------------------------------- | :--------------------------- |
| **Đảm bảo toàn vẹn dữ liệu cơ bản**  | `CHECK CONSTRAINT`           |
| **Ngăn chặn đặt trùng phòng (Core)** | `EXCLUDE CONSTRAINT`         |
| **Cơ chế Idempotency chống đơn rác** | `UNIQUE CONSTRAINT`          |
| **Lưu vết giá (Snapshot Pricing)**   | `TRIGGER (BEFORE INSERT)`    |
| **Tự động đồng bộ trạng thái**       | `TRIGGER (AFTER UPDATE)`     |
| **Theo dõi lịch sử cập nhật (Audit)**| `TRIGGER (BEFORE UPDATE)`    |
| **Giao dịch đặt phòng 2 pha**        | `STORED PROCEDURE`           |
| **Tính toán hóa đơn cuối kỳ**        | `USER DEFINED FUNCTION`      |
| **Báo cáo & Tra cứu nhanh**          | `VIEW` / `MATERIALIZED VIEW` |

---

**Bảng 2: Cấu hình dự kiến DBMS & Phân chia Module**

| Hạng mục | Tham số / Tên Module | Mô tả chi tiết / Giá trị thiết lập |
| :--- | :--- | :--- |
| **1. Cấu hình Server (PostgreSQL Config)** | **Isolation Level** | `SERIALIZABLE` (cho các Procedure đặt phòng) hoặc `READ COMMITTED` (mặc định cho tra cứu). |
| | **Timezone** | `Asia/Ho_Chi_Minh` (Để đảm bảo hàm `NOW()` và `CURRENT_DATE` đúng giờ Việt Nam). |
| | **Encoding/Collation** | `UTF8` (Hỗ trợ Tiếng Việt đầy đủ). |
| | **Extensions** | `btree_gist` (Hỗ trợ tạo Exclusion Constraint kết hợp giữa khóa thường và khóa khoảng). |
| | **Backup Strategy** | `pg_dump` định kỳ hàng ngày (Logical backup). |
| **2. Phân chia Module (Schema Design)** | **Module Identity (Định danh)** | - **Bảng:** `Users`, `Roles`, `Profiles`.<br>- **Chức năng:** Quản lý thông tin đăng nhập, phân quyền (Guest, Receptionist, Manager). |
| | **Module Inventory (Kho phòng)** | - **Bảng:** `Rooms`, `Room_Types`, `room_type_inventory`, `Price_Policies`, `Facilities`.<br>- **Chức năng:** Quản lý danh sách phòng, kiểm soát tồn kho theo ngày, định nghĩa giá theo loại, trang thiết bị. |
| | **Module Reservation (Đặt phòng - Core)** | - **Bảng:** `Bookings`, `Booking_Details`, `Room_Assignments`.<br>- **Chức năng:** Xử lý luồng đặt phòng 2 pha (Giữ chỗ -> Gán phòng vật lý), chống trùng phòng (Exclusion), Soft Delete hóa đơn. |
| | **Module Operations (Vận hành)** | - **Bảng:** `Services`, `Service_Usage`, `Invoices`, `Staff`, `Staff_Assignments`.<br>- **Chức năng:** Quản lý dọn phòng, gọi dịch vụ thêm, tính tiền, gán nhân viên. |
 **Client (Web/Mobile/Swagger UI) $\Longleftrightarrow$ Application Server (Backend API) $\Longleftrightarrow$ Database Server (PostgreSQL)**