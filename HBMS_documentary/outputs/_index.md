# Hotel Booking Management System — System Map
_last updated: 2026-05-03_

---

## Cấu trúc thư mục

- `inputs/Kiến trúc DBMS.md`: Phân tích về lý do và sự thiết yếu của kiến trúc DBMS.
- `outputs/TÀI LIỆU ĐẶC TẢ NGHIỆP VỤ & RÀNG BUỘC DỮ LIỆU.md`: Đặc tả chi tiết entity, ràng buộc dữ liệu.
- `outputs/tính năng dbms.md`: Bảng mô tả các chức năng chuẩn bị triển khai trên PostgreSQL.
- `outputs/Đặc tả_Physical_Schema.md`: Script DDL tạo bảng vật lý, Enum, và khoá ngoại.
- `outputs/Đặc tả_Database_Programmability.md`: Logic nghiệp vụ xử lý bằng Stored Procedure và Trigger.
- `outputs/Đặc tả_Database_Test_Plan.md`: Kịch bản Database Test.
- `outputs/Đặc tả_Reporting_Views.md`: Đặc tả các View báo cáo và thống kê.
- `outputs/Đặc tả_Room_Operations.md`: Đặc tả các nghiệp vụ liên quan đến vận hành phòng.
- `outputs/hbms_scenario_and_endpoint.md`: Scenario nghiệp vụ và cấu trúc endpoint API.
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
| TÀI LIỆU ĐẶC TẢ NGHIỆP VỤ & RÀNG BUỘC DỮ LIỆU.md | Định nghĩa thực thể, chuẩn hóa dữ liệu |
| tính năng dbms.md | Map tính năng sang các object tương ứng trong PostgreSQL |
| Đặc tả_Physical_Schema.md | Script DDL tạo bảng vật lý, Enum, và khoá ngoại (Hybrid 2-Phase) |
| Đặc tả_Database_Programmability.md | Logic nghiệp vụ xử lý bằng Stored Procedure và Trigger (Fix 3 Anti-patterns) |
| Đặc tả_Database_Test_Plan.md | 11 Kịch bản Database Test (Constraints, Inventory, Trigger) |
| Đặc tả_Reporting_Views.md | Phân tích dữ liệu và các báo cáo thống kê |
| Đặc tả_Room_Operations.md | Quản lý trạng thái phòng và vận hành hàng ngày |
| hbms_scenario_and_endpoint.md | Bản đồ mapping giữa nghiệp vụ database và API endpoint |
| summary_changes_v2.md | Tổng hợp các thay đổi quan trọng trong phiên bản mới nhất |

## Nguyên tắc sử dụng

1. File mới ghi chép → bỏ vào inputs/
2. Sau khi nén với AI → output vào outputs/, cập nhật file tổng hợp
3. Bài toán cụ thể → tạo/cập nhật file trong projects/