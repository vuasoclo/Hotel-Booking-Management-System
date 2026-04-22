# Hotel Booking Management System — System Map
_last updated: 2026-04-22_

---

## Cấu trúc thư mục

- `outputs/Kiến trúc DBMS.md`: Phân tích về lý do và sự thiết yếu của kiến trúc DBMS.
- `outputs/TÀI LIỆU ĐẶC TẢ NGHIỆP VỤ & RÀNG BUỘC DỮ LIỆU.md`: Đặc tả chi tiết entity, ràng buộc dữ liệu.
- `outputs/tính năng dbms.md`: Bảng mô tả các chức năng chuẩn bị triển khai trên PostgreSQL.
- `projects/HBMS_design_delta.md`: Danh sách chỉnh sửa thiết kế cần thực hiện (action items/todo).
- `projects/HBMS_learning_plan.md`: Kế hoạch học và triển khai dự án Hotel Booking DBMS.

## Luồng đọc

inputs/ (raw data)
    ↓  được nén qua conversation với AI
outputs/ (knowledge đã nén)
    ↓  _index.md tổng hợp tất cả
projects/ (hành động cụ thể — bài toán thật)

## Quan hệ giữa các file

| Output | Ý nghĩa / Ghi chú |
|---|---|
| Kiến trúc DBMS.md | Kiến thức cốt lõi và tư duy thiết kế dbps |
| TÀI LIỆU ĐẶC TẢ NGHIỆP VỤ & RÀNG BUỘC DỮ LIỆU.md | Định nghĩa thực thể, chuẩn hóa dữ liệu |
| tính năng dbms.md | Map tính năng sang các object tương ứng trong PostgreSQL |
| Đặc tả_Physical_Schema.md | Script DDL tạo bảng vật lý, Enum, và khoá ngoại (Hybrid 2-Phase) |
| Đặc tả_Database_Programmability.md | Logic nghiệp vụ xử lý bằng Stored Procedure và Trigger (Fix 3 Anti-patterns) |
| Đặc tả_Database_Test_Plan.md | 11 Kịch bản Database Test (Constraints, Inventory, Trigger) |

## Nguyên tắc sử dụng

1. File mới ghi chép → bỏ vào inputs/
2. Sau khi nén với AI → output vào outputs/, cập nhật file tổng hợp
3. Bài toán cụ thể → tạo/cập nhật file trong projects/