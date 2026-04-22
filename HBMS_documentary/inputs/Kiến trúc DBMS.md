### Nguồn gốc của vấn đề và sự thiết yếu của kiến trúc DBMS
Dưới đây là quy trình suy luận First Principle để giải đáp hai câu hỏi cực kỳ cốt lõi của bạn.

---

### Câu 1: Tại sao không điền cấu hình "RAM/CPU vô tận" mà phải cần Kiến trúc?

#### 0. Nhận định
Tuyên bố: *"Có thể giả định phần cứng vô tận để bỏ qua kiến trúc"* là **SAI HOÀN TOÀN**.
Đây là tư duy của người "dùng tiền đè chết người" (Brute Force), không phải tư duy của Kỹ sư (Engineer).

#### 1. Phân rã (Boil down)
*   **Q: Tại sao RAM vô tận không giải quyết được vấn đề?**
    *   **A:** Hãy tưởng tượng bạn có một thư viện rộng vô tận (RAM vô tận) chứa 1 tỷ cuốn sách, nhưng **không có mục lục** (Thiếu Index/Kiến trúc). Bạn vẫn sẽ mất cả đời để tìm một cuốn sách, dù thư viện to đến đâu.
*   **Q: Vấn đề nằm ở đâu?**
    *   **A:** Nằm ở **Giải thuật** và **Cơ chế truy cập**.
        *   Nếu câu lệnh SQL của bạn bị khóa (Deadlock) vì thiết kế sai transaction -> CPU mạnh cỡ nào cũng đứng chơi.
        *   Nếu bạn quét toàn bộ bảng (Full Table Scan) 10 triệu dòng -> Ổ cứng nhanh nhất cũng bị nghẽn băng thông (IOPS).
*   **Q: Về mặt chi phí (Cloud) thì sao?**
    *   **A:** Cloud tính tiền theo giờ. Cấu hình "vô tận" sẽ tốn hàng triệu USD/tháng. Kỹ sư giỏi là người thiết kế hệ thống chạy nhanh nhất trên phần cứng rẻ nhất.

#### 2. Nguyên lý (First Principle)
> **"Phần cứng chỉ giải quyết được tốc độ xử lý thô (Raw Speed), còn Kiến trúc giải quyết được sự tắc nghẽn logic (Logical Bottlenecks) và khả năng mở rộng (Scalability)."**
> *(Xe Ferrari động cơ khủng [RAM mạnh] vẫn không thể đi nhanh nếu đường bị tắc [Kiến trúc tồi]. Bạn cần xây đường cao tốc [Partitioning/Indexing].)*

---

### Câu 2: Các thành phần của kiến trúc DBMS và cách lựa chọn

Để "điền vào chỗ trống" cấu hình dự kiến một cách thông minh, bạn cần hiểu thực đơn (Menu) các món kiến trúc sau đây và chọn món phù hợp với "khẩu vị" (bài toán) của mình.

#### 1. Chiến lược Phân mảnh Dữ liệu (Partitioning / Sharding)
*   **Là gì?** Chia bảng to thành nhiều bảng nhỏ.
*   **Khi nào dùng?**
    *   Khi dữ liệu **lớn theo thời gian** (Lịch sử đặt phòng, Log giao dịch).
    *   Khi bảng vượt quá 10 triệu dòng.
*   **Lựa chọn cho Hotel Booking:** Dùng **Declarative Partitioning** (chia theo tháng) cho bảng `Bookings` và `Invoices`.
    *   *Lý do:* Người ta thường chỉ tra cứu đơn tháng này, ít khi tra cứu đơn của 5 năm trước.

#### 2. Chiến lược Bộ nhớ đệm (Caching & Materialized Views)
*   **Là gì?** Lưu kết quả tính toán sẵn để không phải tính lại.
*   **Khi nào dùng?**
    *   Khi dữ liệu **ít thay đổi** nhưng được **đọc rất nhiều**.
    *   Khi câu truy vấn rất nặng (SUM, COUNT, GROUP BY).
*   **Lựa chọn cho Hotel Booking:** Dùng **Materialized Views** cho Báo cáo doanh thu. Dùng **Redis** (bên ngoài DB) cho danh sách phòng trống (nếu cần tốc độ cao).

#### 3. Chiến lược Sao chép & Sẵn sàng (Replication & High Availability)
*   **Là gì?** Tạo ra nhiều bản sao của Database (Master - Slave).
*   **Khi nào dùng?**
    *   Khi lượng người **Đọc (Read)** lớn hơn rất nhiều so với người **Ghi (Write)** (Tỷ lệ 80/20).
    *   Khi hệ thống không được phép sập (Chết con Master thì con Slave lên thay).
*   **Lựa chọn cho Hotel Booking:** Cấu hình **Master-Slave Replication**.
    *   Master: Để ghi đơn đặt phòng (Booking).
    *   Slave: Để cho khách tìm kiếm phòng (Search) và xem báo cáo. Giảm tải cho Master.

#### 4. Chiến lược Bảo mật (Security Architecture)
*   **Là gì?** Kiểm soát ai được thấy cái gì.
*   **Khi nào dùng?**
    *   Khi hệ thống là **Multi-tenant** (Nhiều khách sạn dùng chung 1 phần mềm).
    *   Khi dữ liệu nhạy cảm (Doanh thu, thông tin khách).
*   **Lựa chọn cho Hotel Booking:** Dùng **Row-Level Security (RLS)**.
    *   *Lý do:* Đảm bảo Khách sạn A không bao giờ `SELECT` trộm được khách của Khách sạn B.

#### 5. Chiến lược Kết nối (Connection Pooling)
*   **Là gì?** Giữ sẵn một tập hợp các kết nối mở thay vì đóng/mở liên tục.
*   **Khi nào dùng?**
    *   Khi có **hàng nghìn request nhỏ** liên tục (Ví dụ: App mobile ping server).
    *   PostgreSQL tạo kết nối mới rất tốn RAM.
*   **Lựa chọn cho Hotel Booking:** Dùng **PgBouncer**.

---

### TỔNG KẾT: Bảng hướng dẫn lựa chọn (Cheat Sheet)

Bạn hãy nhìn vào cột **"Dấu hiệu nhận biết"** để chọn kiến trúc cho bài của mình:

| Thành phần Kiến trúc | Dấu hiệu nhận biết (Bài toán của bạn có cái này không?) | Có nên chọn cho Hotel Booking? |
| :--- | :--- | :--- |
| **Partitioning** | Dữ liệu lịch sử tích tụ nhiều năm? Bảng > 5GB? | **CÓ** (Bảng Booking/Log). |
| **Sharding** | Dữ liệu quá lớn cho 1 máy chủ (Hàng tỷ dòng)? Facebook/Google? | **KHÔNG** (Quá phức tạp cho đồ án). |
| **Replication** | Lượng người xem (Search) áp đảo người mua? Cần uptime 99.9%? | **CÓ** (Tốt để chém gió về hiệu năng). |
| **Materialized View** | Sếp cần xem báo cáo tổng hợp? Dashboard load chậm? | **CÓ** (Rất nên dùng). |
| **Row-Level Security** | Nhiều công ty/chi nhánh dùng chung 1 DB? | **CÓ** (Tính năng "ăn điểm" bảo mật). |
| **Index (B-Tree, Hash)** | Tìm kiếm bị chậm? | **BẮT BUỘC** (Cơ bản nhất). |
| **Isolation Level (Serializable)** | Có nguy cơ tranh chấp (Race Condition) khi đặt hàng? | **BẮT BUỘC** (Cho Procedure Booking). |

**Lời khuyên:** Trong đồ án, bạn không cần cài đặt hết (vì không có server thật), nhưng bạn phải **VIẾT ĐƯỢC VÀO BÁO CÁO** rằng: *"Em chọn kiến trúc Partitioning vì bảng Booking sẽ lớn dần theo thời gian, và chọn RLS vì đây là hệ thống cho nhiều khách sạn thuê."* -> Đó là tư duy ăn điểm.