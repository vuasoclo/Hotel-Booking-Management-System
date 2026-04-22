---
description: Setup cấu trúc workspace mới trong Quota. Gọi bằng /setup [tên workspace] hoặc /setup cho workspace hiện tại.
---

# Setup Workspace

Quy trình thiết lập cấu trúc chuẩn cho một workspace trong `d:\Quota\`.

## Bước 1: Xác định workspace

- Nếu user chỉ định tên → workspace = `d:\Quota\[tên]`
- Nếu không chỉ định → dùng workspace hiện tại của user

// turbo
## Bước 2: Tạo cấu trúc thư mục

Tạo 3 folder nếu chưa có:
```
[workspace]/
├── inputs/
├── outputs/
└── projects/
```

Command: `New-Item -ItemType Directory -Path "[workspace]\inputs","[workspace]\outputs","[workspace]\projects" -Force`

## Bước 3: Phân loại file có sẵn

Đọc tất cả file `.md` đang nằm ở root của workspace (không nằm trong subfolder). Với mỗi file, đọc nội dung và phân loại:

### inputs/ — File nguồn gốc
- Raw journal, ghi chép cá nhân
- Ghi chép buổi gặp, cuộc hội thoại
- Quan sát thô chưa qua xử lý
- File có tiền tố "raw"
- File có nội dung dạng tường thuật, chưa cấu trúc

### outputs/ — Knowledge đã nén
- File có tiền tố "output"
- File theo format chuẩn (có Core Principles, Key Distinctions, Action Triggers, ...)
- File tổng hợp, phân tích đã qua xử lý
- Knowledge đã rút gọn từ conversation với AI

### projects/ — Bài toán đang theo đuổi
- File mô tả project cụ thể với bước tiếp theo
- File có checklist/TODO

### Không di chuyển
- File `.agents/` và config files → giữ nguyên
- File đã nằm trong subfolder → giữ nguyên

## Bước 4: Di chuyển file

Di chuyển từng file vào folder tương ứng. Use `Move-Item`.

## Bước 5: Tạo `outputs/_index.md`

Tạo file `_index.md` trong `outputs/` với nội dung:

```markdown
# [Tên workspace] — System Map
_last updated: [ngày hôm nay]_

---

## Cấu trúc thư mục

[Liệt kê cây thư mục với mô tả ngắn cho mỗi file]

## Luồng đọc

inputs/ (raw data)
    ↓  được nén qua conversation với AI
outputs/ (knowledge đã nén)
    ↓  [file tổng hợp chính] tổng hợp tất cả
projects/ (hành động cụ thể — bài toán thật)

## Quan hệ giữa các file

[Bảng: Output ← Input]

## Nguyên tắc sử dụng

1. File mới ghi chép → bỏ vào inputs/
2. Sau khi nén với AI → output vào outputs/, cập nhật file tổng hợp
3. Bài toán cụ thể → tạo/cập nhật file trong projects/
```

## Bước 6: Tạo `.agents/workflows/session.md`

Tạo file workflow cho workspace với nội dung session workflow chuẩn:

```markdown
---
description: Quy trình bắt đầu và kết thúc mỗi session làm việc với "[tên workspace]" workspace
---

# Session Workflow

## BẮT ĐẦU SESSION

// turbo
1. Đọc `outputs/_index.md` để biết hệ thống hiện tại có những output nào

2. Xác định chủ đề hôm nay → load output liên quan
   - Nếu chủ đề đã có output → đọc file đó trước
   - Nếu chủ đề mới → ghi nhận, sẽ tạo output mới cuối session

3. Nếu có project liên quan → đọc file trong `projects/`

## TRONG SESSION

4. Làm việc bình thường — theo nguyên tắc:
   - Tiếp xúc trước, hiểu sau
   - Kết quả thật > cảm giác hiểu
   - Chỉ trả nợ chặn
   - Đưa phản ví dụ trước khi xác nhận
   - Phân biệt [ĐÃ KIỂM CHỨNG] vs [GIẢ THUYẾT] vs [CẦN NEO]
   - Neo trước, đào sau

## KẾT THÚC SESSION

5. Compress knowledge → cập nhật/tạo output file theo format chuẩn:

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

6. Nếu có file output mới → cập nhật `outputs/_index.md`
7. Nếu có project mới → cập nhật file trong `projects/`
```

## Bước 7: Báo cáo

Tóm tắt cho user:
- Đã tạo bao nhiêu folder
- Đã di chuyển bao nhiêu file vào đâu
- Đã tạo những file mới nào (_index.md, session.md)
- Có file nào không chắc cách phân loại → hỏi user
