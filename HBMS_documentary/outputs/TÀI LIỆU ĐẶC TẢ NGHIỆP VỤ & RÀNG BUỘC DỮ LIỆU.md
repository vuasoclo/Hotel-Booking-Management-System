**Dự án:** Hotel Booking Management System (HBMS)  
**Phiên bản:** 1.0 (Database Centric)

---

## 1. Xác định Thực thể (Entities)

Dựa trên nguyên lý chuẩn hóa (Normalization), hệ thống cần các thực thể cốt lõi sau:

1. **Customers (Khách hàng):** Người thực hiện đặt phòng.
    
2. **Room_Types (Loại phòng):** Định nghĩa thông số tĩnh (Ví dụ: Deluxe, Standard, Suite, giá gốc, sức chứa).
    
3. **Rooms (Phòng vật lý):** Các phòng cụ thể (Ví dụ: Phòng 101, 102).
    
4. **Price_Policies (Chính sách giá):** Quản lý giá theo mùa/ngày lễ (tách riêng để tránh sửa bảng Room_Types liên tục).
    
5. **Bookings (Đơn đặt phòng):** Thông tin chung của giao dịch (Ngày tạo, Khách hàng, Trạng thái đơn).
    
6. **Booking_Details (Chi tiết đặt phòng):** Liên kết Đơn đặt với Phòng cụ thể và Thời gian ở (Tách ra để 1 đơn có thể đặt nhiều phòng).
    
7. **Services (Dịch vụ):** Các dịch vụ đi kèm (Spa, Ăn uống, Giặt ủi).
    
8. **Service_Usage (Sử dụng dịch vụ):** Ghi nhận việc khách sử dụng dịch vụ nào, số lượng bao nhiêu.
    
9. **Invoices (Hóa đơn):** Chứng từ thanh toán cuối cùng.
    
10. **Staff (Nhân viên):** Người thực hiện Check-in/Check-out và dọn phòng.
    

---

## 2. Quy trình nghiệp vụ cốt lõi (Data Flow)

Dòng chảy dữ liệu đi qua các bảng theo trình tự sau:

1. **Search (Tìm kiếm):** Hệ thống lọc bảng Rooms loại bỏ các phòng có ID nằm trong bảng Booking_Details có thời gian chồng lấn với thời gian khách chọn.
    
2. **Reservation (Đặt giữ chỗ):** INSERT vào Bookings và Booking_Details. Lúc này giá phòng được "chụp ảnh" (Snapshot) lưu vào Booking_Details. Trạng thái phòng chưa đổi, nhưng logic tìm kiếm sẽ tự loại phòng này ra.
    
3. **Check-in (Nhận phòng):** Nhân viên xác thực. Cập nhật trạng thái Bookings sang "Checked-in". Cập nhật trạng thái Rooms sang "Occupied".
    
4. **Use Service (Dùng dịch vụ):** INSERT vào Service_Usage khi khách gọi đồ.
    
5. **Check-out (Trả phòng):**
    
    - Hệ thống tính tổng tiền (Tiền phòng + Dịch vụ).
        
    - Cập nhật trạng thái Bookings sang "Completed".
        
    - Cập nhật trạng thái Rooms sang "Dirty" (Chờ dọn).
        
6. **Housekeeping (Dọn dẹp):** Nhân viên dọn xong -> Cập nhật trạng thái Rooms sang "Available".
    

---

## 3. Danh sách Ràng buộc Nghiệp vụ (Business Rules)

### A. Ràng buộc Cơ bản (Basic Integrity)

Đảm bảo dữ liệu nhập vào hợp lệ về mặt cú pháp và logic đơn giản.

1. **Quy tắc: Thời gian hợp lệ**
    
    - **Mô tả:** Ngày CheckOutDate phải luôn lớn hơn CheckInDate. Ngày đặt (BookingDate) phải nhỏ hơn hoặc bằng CheckInDate.
        
    - **Giải pháp:** Sử dụng CHECK CONSTRAINT cấp bảng.
        
    - CHECK (CheckOutDate > CheckInDate AND BookingDate <= CheckInDate)
        
2. **Quy tắc: Miền giá trị dương**
    
    - **Mô tả:** Giá tiền (Price), Số lượng người (Guests), Số lượng dịch vụ (Quantity) không được là số âm.
        
    - **Giải pháp:** Sử dụng CHECK CONSTRAINT.
        
    - CHECK (Price >= 0), CHECK (Guests > 0)
        
3. **Quy tắc: Định danh duy nhất**
    
    - **Mô tả:** Số CCCD/Passport, Email, Số điện thoại của khách hàng phải là duy nhất trong hệ thống.
        
    - **Giải pháp:** Sử dụng UNIQUE INDEX hoặc UNIQUE CONSTRAINT.
        
4. **Quy tắc: Độ tuổi pháp lý**
    
    - **Mô tả:** Khách hàng đứng tên đặt phòng phải đủ 18 tuổi tính đến ngày hiện tại.
        
    - **Giải pháp:** Sử dụng CHECK CONSTRAINT hoặc TRIGGER (vì một số DB không hỗ trợ hàm thời gian thực trong Check).
        
    - CHECK (DATEDIFF(YEAR, DateOfBirth, GETDATE()) >= 18)
        

---

### B. Ràng buộc Nâng cao (Advanced Business Logic) - Trọng tâm đồ án

Đảm bảo tính nhất quán của quy trình nghiệp vụ phức tạp.

#### 1. Temporal Logic (Logic Thời gian - Chống Double Booking)

- **Tên quy tắc:** Không trùng lặp lịch đặt (Non-overlapping Intervals).
    
- **Mô tả:** Tại cùng một thời điểm, một phòng (RoomID) không thể tồn tại trong hai dòng dữ liệu Booking_Details khác nhau có trạng thái 'Active'.
    
- **Logic toán học:** Khoảng thời gian [A_Start, A_End] giao nhau với [B_Start, B_End] khi: A_Start < B_End AND A_End > B_Start.
    
- **Giải pháp kỹ thuật:**
    
    - **Cách 1 (Tốt nhất - PostgreSQL):** Sử dụng EXCLUDE CONSTRAINT với kiểu dữ liệu RANGE.
        
    - **Cách 2 (Phổ thông - SQL Server/MySQL):** Sử dụng TRIGGER BEFORE INSERT/UPDATE. Trong Trigger, thực hiện câu lệnh IF EXISTS (SELECT 1 FROM Booking_Details WHERE RoomID = New.RoomID AND ...) -> Nếu có thì ROLLBACK.
        

#### 2. State Machine (Máy trạng thái - Vòng đời phòng)

- **Tên quy tắc:** Chặn Check-in phòng không sẵn sàng.
    
- **Mô tả:** Không thể tạo một Booking mới hoặc Check-in vào một phòng có trạng thái hiện tại (CurrentStatus) là 'Occupied' (Đang có khách), 'Dirty' (Chưa dọn) hoặc 'Maintenance' (Bảo trì).
    
- **Giải pháp kỹ thuật:**
    
    - Sử dụng TRIGGER BEFORE INSERT trên bảng Bookings. Trigger sẽ JOIN với bảng Rooms để kiểm tra cột Status. Nếu khác 'Available' -> Báo lỗi.
        

#### 3. Historical Data (Dữ liệu lịch sử - Snapshot Giá)

- **Tên quy tắc:** Bất biến giá giao dịch.
    
- **Mô tả:** Khi đơn đặt phòng được tạo, giá phòng (UnitPrice) phải được lấy từ bảng Room_Types (hoặc Price_Policies) và lưu cứng vào bảng Booking_Details. Nếu sau này bảng giá gốc thay đổi, giá trong đơn hàng cũ KHÔNG được thay đổi.
    
- **Giải pháp kỹ thuật:**
    
    - Tuyệt đối không dùng JOIN để lấy giá khi tính tiền.
        
    - Phải có cột AgreedPrice trong bảng Booking_Details.
        
    - Sử dụng TRIGGER BEFORE INSERT: Tự động lấy giá hiện tại gán vào cột AgreedPrice.
        

#### 4. Operational Logic (Sức chứa tối đa)

- **Tên quy tắc:** Kiểm soát sức chứa (Max Occupancy Enforcement).
    
- **Mô tả:** Tổng số người (Người lớn + Trẻ em) trong một Booking không được vượt quá MaxCapacity được định nghĩa trong bảng Room_Types.
    
- **Giải pháp kỹ thuật:**
    
    - Sử dụng TRIGGER hoặc CHECK CONSTRAINT (nếu DB hỗ trợ Check liên bảng qua UDF). Trigger sẽ so sánh Booking.Guests <= Room_Type.MaxCapacity.
        

#### 5. Derived Data (Dữ liệu tính toán tự động)

- **Tên quy tắc:** Tự động tính tổng tiền (Auto-Calculate Total Amount).
    
- **Mô tả:** Tổng tiền hóa đơn (TotalAmount) = (Giá phòng * Số đêm) + Tổng tiền dịch vụ. Giá trị này phải luôn đúng, không phụ thuộc vào việc tính toán ở Frontend.
    
- **Giải pháp kỹ thuật:**
    
    - Cách 1: Sử dụng **Computed Column** (Cột tính toán ảo).
        
    - Cách 2: Sử dụng **View** để hiển thị báo cáo.
        
    - Cách 3: Sử dụng TRIGGER AFTER INSERT/UPDATE/DELETE trên bảng Service_Usage để cập nhật lại cột TotalAmount trong bảng Bookings (Denormalization để tối ưu tốc độ đọc).
        

---

**Lời khuyên từ Architect:**  
Để đồ án đạt điểm tối đa, bạn hãy tập trung triển khai thật tốt mục **B.1 (Double Booking)** và **B.3 (Snapshot Giá)**. Đây là hai tử huyệt mà các hệ thống nghiệp dư thường bỏ qua.