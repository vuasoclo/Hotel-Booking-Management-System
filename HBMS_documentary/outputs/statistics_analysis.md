# Phân tích tính năng Thống kê (Statistics) - HBMS

Dựa trên yêu cầu và thực tế mã nguồn, dưới đây là bản tổng hợp đánh giá về các tính năng thống kê hiện tại.

## 1. Các thành phần SQL hiện có
Hệ thống đã có sẵn 2 View nền tảng quan trọng trong file `HBMS_full_deployment.sql`:

*   **`v_daily_occupancy`**:
    *   **Nhiệm vụ:** Tính công suất phòng (`occupancy_rate`) theo từng loại phòng và từng ngày.
    *   **Dữ liệu:** `room_type_id`, `date`, `total_inventory`, `total_reserved`, `occupancy_rate`.
    *   **Đánh giá:** Rất tốt cho tính năng **Heatmap**. Tuy nhiên, để tính KPI chung cho toàn khách sạn, cần thêm bước cộng dồn tất cả các loại phòng trong cùng một ngày.

*   **`v_monthly_revenue`**:
    *   **Nhiệm vụ:** Tổng hợp doanh thu theo tháng (tính theo ngày check-out).
    *   **Dữ liệu:** `report_month`, `total_room_cost`, `total_surcharges`, `total_services`, `total_revenue`, `actual_collected`.
    *   **Đánh giá:** Đã bao quát đủ 3 nguồn thu (Phòng, Phụ thu, Dịch vụ). Đây là nguồn dữ liệu chính cho biểu đồ doanh thu và các thẻ KPI doanh thu.

## 2. Tình trạng Backend (`routes/statistics.py`)
Hiện tại Backend chỉ đóng vai trò "trung chuyển" dữ liệu từ View lên Frontend:
*   Lấy 30 bản ghi gần nhất từ `v_daily_occupancy`.
*   Lấy 12 bản ghi gần nhất từ `v_monthly_revenue`.

**Hạn chế:**
*   Chưa hỗ trợ tham số lọc (ví dụ: lọc theo khách sạn, theo khoảng thời gian, theo loại phòng).
*   Chưa tính toán các chỉ số KPI tập trung (Aggregate KPIs), để Frontend tự tính toán dễ dẫn đến sai sót logic.

## 3. Tình trạng Frontend (`statistics.html`)
Giao diện đã thiết kế đầy đủ các thành phần:
*   4 thẻ KPI (Occupancy, Revenue, Collected, Outstanding).
*   Heatmap công suất phòng.
*   Biểu đồ cột (Monthly Revenue).
*   Biểu đồ tròn (Revenue Breakdown).

**Lỗi logic phát hiện:**
*   **Avg Occupancy (7 days):** Frontend đang lấy 7 bản ghi đầu tiên của `v_daily_occupancy`. Nếu khách sạn có 3 loại phòng, nó sẽ chỉ lấy dữ liệu của ~2 ngày cho các loại phòng khác nhau, không phải trung bình 7 ngày của toàn khách sạn.

## 4. Đề xuất xử lý bổ sung (Cần hoàn thiện)

### A. Cải thiện SQL (Database)
Cần bổ sung một View hoặc Function để tính toán ADR và công suất tổng quát:
*   **`v_hotel_daily_stats`**: Cộng dồn `total_inventory` và `total_reserved` của tất cả loại phòng theo ngày để có con số Occupancy chuẩn xác cho toàn khách sạn.
*   **ADR (Average Daily Rate)**: Công thức `Tổng doanh thu phòng / Số phòng đã bán`.

### B. Nâng cấp Backend (API)
Nâng cấp endpoint `/api/statistics` để thực hiện các việc sau:
1.  **Tính toán KPI tập trung:** Trả về một object `summary` chứa các giá trị cuối cùng thay vì để Frontend tự `sum`.
2.  **Hỗ trợ Filters:** Thêm query parameters `?period=this_month`, `?room_type=...` để khớp với UI.
3.  **Tính toán ADR và Booking Count:** Bổ sung thêm 2 chỉ số này vào phản hồi API.

### C. Backend logic cần viết thêm:
*   Logic tính toán chênh lệch (Trend) so với tháng trước/kỳ trước (ví dụ: Doanh thu tăng 10% so với tháng trước).
*   Logic tổng hợp Occupancy chuẩn xác (nhóm theo ngày, không phân biệt loại phòng).

## 5. Kết luận
Các Procedure, Table và View hiện tại đã **đủ khoảng 70%** dữ liệu thô. Để hoàn thiện tính năng Statistics một cách chuyên nghiệp và chính xác, **CẦN viết thêm xử lý ở Backend** để tính toán các chỉ số aggregate và hỗ trợ bộ lọc trên UI, thay vì chỉ trả về dữ liệu thô từ View.

---
*Người thực hiện: Antigravity*
*Ngày: 2026-04-30*
