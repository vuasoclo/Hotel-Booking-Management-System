---
description: Quy trình bắt đầu và kết thúc mỗi session làm việc với "Hotel Booking Management System" workspace
---

# Session Workflow

## BẮT ĐẦU SESSION

1. Đọc `outputs/_index.md` để biết hệ thống hiện tại có những output nào.

2. Xác định chủ đề hôm nay → load output liên quan:
   - Nếu chủ đề đã có output → đọc file đó trước.
   - Nếu chủ đề mới → ghi nhận, sẽ tạo output mới cuối session.

3. Nếu có project liên quan → đọc file trong `projects/`.

## TRONG SESSION

4. Làm việc bình thường — theo nguyên tắc:
   - Tiếp xúc trước, hiểu sau.
   - Kết quả thật > cảm giác hiểu.
   - Chỉ trả nợ chặn.
   - Đưa phản ví dụ trước khi xác nhận.
   - Phân biệt [ĐÃ KIỂM CHỨNG] vs [GIẢ THUYẾT] vs [CẦN NEO].
   - Neo trước, đào sau.

## KẾT THÚC SESSION

5. Compress knowledge → cập nhật/tạo output file theo format chuẩn:

```markdown
# [Tên chủ đề]
_last updated: [ngày]_
_inputs: [[link1]], [[link2]]_
_related: [[output_khác]]_

## Core Principles
> 1. ...

## Key Distinctions
- X ≠ Y vì: ...

## Unresolved Questions
- ?

## Action Triggers
- Khi [X] xảy ra → làm [Y]

## Backtrack
- [Chi tiết về Z] → inputs/file.md#section
```

6. Nếu có file output mới → cập nhật `outputs/_index.md`.
7. Nếu có project mới → cập nhật file trong `projects/`.