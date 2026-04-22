# KẾ HOẠCH HỌC & TRIỂN KHAI — Hotel Booking DBMS
*Trạng thái hiện tại → Có thể review và build được thiết kế*

---

## Chẩn đoán vấn đề thực sự

Bạn đang bị mắc kẹt ở **vùng mù giữa "nghe hay" và "hiểu bản chất"**. Nguyên nhân: các tài liệu bạn đang có là lời khuyên kiến trúc cấp hệ thống lớn, nhưng nền tảng DBMS cấp phòng học chưa được kết nối với chúng. Khoảng cách đó là hoàn toàn bình thường — nhưng phải đóng nó đúng thứ tự.

**Quy tắc số 1:** Đừng cố học hết tất cả từ khóa trước khi build. Build trước, gặp vấn đề thực, rồi mới học từ khóa có nghĩa.

---

## Bản đồ từ khóa theo tầng (Hierarchy)

Trước khi làm gì, cần biết từ khóa nào thuộc tầng nào để không học sai thứ tự:

```
Tầng 4 — System Architecture (Học SAU khi đã dùng DB thành thạo)
    Redis, CDC/Debezium, Replication, Sharding, PgBouncer, Idempotency Key
    → Những thứ này dùng khi system có hàng triệu user. Đồ án KHÔNG cần implement.
    → Chỉ cần HIỂU ĐỂ VIẾT vào báo cáo lý do chọn/không chọn.

Tầng 3 — Advanced SQL Features (Học SONG SONG khi build)
    EXCLUDE CONSTRAINT, GiST Index, Row-Level Security, Materialized View,
    Partitioning, Stored Procedure, Isolation Level
    → Đây là core của đồ án DBMS. Phải implement được ít nhất 3-4 cái.

Tầng 2 — SQL & Relational Model (Học TRƯỚC khi build)
    Normalization, Foreign Key, CHECK CONSTRAINT, TRIGGER, INDEX (B-Tree),
    Transaction (ACID), JOIN, VIEW
    → Đây là nền tảng. Nếu còn mơ hồ ở tầng này → block hết tầng trên.

Tầng 1 — Storage Engine (Đã học trong môn DBMS lý thuyết)
    Heap File, Slotted Page, B-Tree structure, Buffer Pool
    → Hiểu tại sao INDEX nhanh, FULL SCAN chậm. Nền tảng tư duy.
```

---

## Giai đoạn 0 — Kết nối lý thuyết đã học với thiết kế (3-5 ngày)

**Mục tiêu:** Biến kiến thức Heap File/Slotted Page thành lý do để viết INDEX.

### Câu hỏi cần tự trả lời được (không tra):

1. Tại sao `SELECT * FROM Bookings WHERE customer_id = 5` chậm nếu không có INDEX?
   → Gợi ý: nhớ lại cơ chế Heap File scan từng slot.

2. B-Tree Index lưu gì? Tìm kiếm theo range (`check_in BETWEEN ... AND ...`) dùng B-Tree hay Hash tốt hơn?

3. ACID: khi 2 người đặt cùng 1 phòng cùng lúc, cơ chế nào ngăn cả 2 đều thành công?
   → Đây chính là vấn đề mà EXCLUDE CONSTRAINT và Isolation Level giải quyết.

### Xem:
- **CMU 15-445 (Andy Pavlo) — Lecture 7: Tree Indexes** (YouTube, ~60 phút)
  → Xem phần B-Tree insert/search. Cực kỳ rõ ràng, có hình minh họa.
- **CMU 15-445 — Lecture 15: Concurrency Control Theory** (Transaction + ACID)

---

## Giai đoạn 1 — Build schema tối thiểu chạy được (1 tuần)

**Mục tiêu:** Có PostgreSQL chạy local với 6 bảng core, insert được dữ liệu test.

### Thứ tự build (quan trọng — đừng build song song):

```
Bước 1: Room_Types → Rooms
        (Chưa có gì liên quan đến booking, chỉ tạo kho phòng)

Bước 2: Customers
        (Thêm CHECK constraint: tuổi >= 18, email UNIQUE)

Bước 3: Bookings + Booking_Details
        (Chỉ dùng CHECK constraint cơ bản trước — check_out > check_in)
        → Test: INSERT 2-3 booking thủ công, xem data có hợp lý không

Bước 4: Thêm TRIGGER snapshot giá vào Booking_Details
        (Tự động copy giá từ Room_Types.base_price vào Booking_Details.agreed_price)
        → Test: Sửa giá trong Room_Types, kiểm tra booking cũ có bị đổi không

Bước 5: Thêm EXCLUDE CONSTRAINT chống double booking
        → Test quan trọng nhất: thử INSERT 2 booking cùng phòng, cùng ngày → phải báo lỗi

Bước 6: Services + Service_Usage + Invoices
```

### Công cụ:
- PostgreSQL local (Docker image `postgres:16-alpine` — nhẹ nhất)
- pgAdmin hoặc DBeaver để xem data bằng GUI
- Viết SQL trong file `.sql`, không gõ tay từng lần

---

## Giai đoạn 2 — Hiểu 3 tính năng cốt lõi (song song với build)

### A. EXCLUDE CONSTRAINT + GiST (Chống double booking)

**Bản chất:** GiST (Generalized Search Tree) là một loại index có thể index *khoảng* (`[check_in, check_out)`), không chỉ giá trị đơn. EXCLUDE constraint dùng GiST để đảm bảo: không có 2 dòng nào trong bảng mà `room_id` bằng nhau VÀ khoảng thời gian chồng lấn nhau.

**Tại sao GiST mà không phải B-Tree?** B-Tree chỉ so sánh `=`, `<`, `>` trên giá trị đơn. Khoảng `[ngày1, ngày2)` cần phép so sánh *overlap* (`&&`) — đó là việc của GiST.

**Đọc:** PostgreSQL docs, phần "Exclusion Constraints" — 10 phút, rất ngắn.

**Code mẫu để hiểu:**
```sql
-- Cần extension này trước
CREATE EXTENSION btree_gist;

-- Constraint này đọc là:
-- "Không tồn tại 2 dòng mà room_id bằng nhau VÀ khoảng ngày overlap nhau"
ALTER TABLE booking_details ADD CONSTRAINT no_overlap
EXCLUDE USING gist (
    room_id WITH =,
    daterange(check_in, check_out, '[)') WITH &&
)
WHERE (status = 'Active');
```

### B. TRIGGER (Snapshot giá)

**Bản chất:** Trigger là đoạn code tự động chạy khi có INSERT/UPDATE/DELETE. BEFORE INSERT nghĩa là chạy trước khi dữ liệu được ghi — cho phép sửa giá trị `NEW.*` trước khi lưu.

**Tại sao không để Frontend tự gửi giá?** Frontend có thể bị hack hoặc lỗi mạng. DB phải là nguồn sự thật duy nhất.

**Code mẫu:**
```sql
CREATE OR REPLACE FUNCTION snapshot_price()
RETURNS TRIGGER AS $$
BEGIN
    -- Tự động lấy giá từ Room_Types, ghi đè bất kể frontend gửi gì
    NEW.agreed_price := (
        SELECT base_price FROM room_types
        WHERE id = (SELECT room_type_id FROM rooms WHERE id = NEW.room_id)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_insert_booking_detail
BEFORE INSERT ON booking_details
FOR EACH ROW EXECUTE FUNCTION snapshot_price();
```

### C. Stored Procedure (Giao dịch đặt phòng)

**Bản chất:** Gom nhiều câu SQL vào 1 khối, toàn bộ chạy trong 1 transaction. Nếu bước nào lỗi → rollback hết. Đây là cách đảm bảo ACID cho luồng đặt phòng.

**Xem:** Search YouTube "PostgreSQL stored procedure vs function" — 15 phút. Hiểu sự khác nhau giữa PROCEDURE (dùng CALL, có COMMIT/ROLLBACK) và FUNCTION (dùng SELECT, không có).

---

## Giai đoạn 3 — Hiểu kiến trúc tầng cao để viết báo cáo (không cần implement)

Mục tiêu của giai đoạn này: **Viết được 1 đoạn trong báo cáo lý giải lý do thiết kế**, không phải code được.

### Từ khóa cần hiểu ở mức "giải thích được":

| Từ khóa | Mức cần hiểu | Nguồn tốt nhất |
|---|---|---|
| Partitioning (Range) | Bảng Bookings chia theo tháng, tại sao | ByteByteGo "Database Partitioning" (YouTube, 8 phút) |
| Master-Slave Replication | Read replica để tách search và write | ByteByteGo "Database Replication" (YouTube, 6 phút) |
| Row-Level Security | Khách sạn A không đọc được data khách sạn B | PostgreSQL docs "Row Security Policies" |
| Optimistic vs Pessimistic Locking | Tại sao không dùng SELECT FOR UPDATE | Search "optimistic locking explained simply" |
| Soft Lock + TTL (Redis) | Chỉ cần biết pattern, không cần implement | Ghi chú từ file lời khuyên là đủ |

**Nguồn học tổng hợp tốt nhất:**
- **ByteByteGo** (YouTube + newsletter) — mỗi video 5-10 phút, visual rất rõ
- **Hussain Nasser** (YouTube) — deeper technical, hay cho Postgres specifics
- **CMU 15-445** (YouTube) — nếu muốn hiểu tận gốc storage engine

---

## Giai đoạn 4 — Review thiết kế (sau khi đã build được)

Đây là lúc quay lại file `lời khuyên db hotel.md` và tự đặt các câu hỏi:

### Checklist review:

**Schema:**
- [ ] Bảng `Booking_Details` có cột `agreed_price` chưa?
- [ ] Có trigger tự động fill `agreed_price` khi INSERT chưa?
- [ ] EXCLUDE CONSTRAINT có `WHERE (status = 'Active')` để loại booking đã hủy chưa?
- [ ] FK có `ON DELETE RESTRICT` hay `CASCADE` cho đúng nghiệp vụ chưa?

**Business Logic:**
- [ ] Khi hủy booking, status đổi sang 'Cancelled' hay DELETE luôn? (Đừng DELETE — mất lịch sử)
- [ ] Phòng đang 'Maintenance' có bị phép đặt không? (Trigger check chưa?)
- [ ] Test case: đặt 2 booking cùng phòng, ngày chồng nhau → DB có reject không?

**Kiến trúc:**
- [ ] Đã viết vào báo cáo lý do chọn Partitioning cho bảng Bookings chưa?
- [ ] Đã viết lý do chọn RLS nếu hệ thống multi-hotel chưa?

### Cách review thiết kế của người khác (skill quan trọng):
1. Đọc schema → vẽ lại ERD trên giấy → tìm bảng nào thiếu FK
2. Đặt câu hỏi "điều gì xảy ra nếu...": nếu giá phòng đổi? nếu khách đặt 2 lần? nếu nhân viên xóa nhầm booking?
3. Viết INSERT test case cho từng edge case → chạy → xem DB phản ứng thế nào

---

## Tóm tắt thứ tự ưu tiên

```
Tuần 1: Xem CMU lecture 7 + 15 → Build bảng 1-4 (Room_Types → Customers)
Tuần 2: Build Bookings + Booking_Details + TRIGGER snapshot giá
Tuần 3: Thêm EXCLUDE CONSTRAINT → test double booking
Tuần 4: Xem ByteByteGo Partitioning/Replication → viết phần kiến trúc báo cáo
Tuần 5: Review toàn bộ checklist → fix + polish
```

**Nguyên tắc tránh bẫy:**
- Đừng học Redis/CDC/Debezium bây giờ — đó là Tầng 4, không thuộc scope đồ án
- Đừng đọc thêm tài liệu mới nếu chưa viết được 1 dòng SQL
- Mỗi từ khóa chỉ cần hiểu đủ để *sử dụng được*, không cần hiểu để *implement lại từ đầu*
