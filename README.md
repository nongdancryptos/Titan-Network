# Titan Network — Hướng dẫn chạy `titan.sh` (ngắn gọn)

Script gốc: `titan.sh` từ repo **nongdancryptos/Titan-Network**. Dùng để cài và chạy Titan Agent theo hướng dẫn của dự án.

## Yêu cầu
- Linux (Ubuntu/Debian/Fedora/CentOS/RHEL), quyền `sudo`.
- Kết nối Internet ổn định.

## Cách chạy nhanh (không cần clone)
```bash
curl -fsSL https://raw.githubusercontent.com/nongdancryptos/Titan-Network/main/titan.sh -o titan.sh
chmod +x titan.sh
sudo ./titan.sh
```
> Script sẽ hiện menu (cài đặt/chạy node, gỡ cài đặt, v.v.). Làm theo hướng dẫn trên màn hình.

## Cách chạy khi clone repo
```bash
git clone https://github.com/nongdancryptos/Titan-Network.git
cd Titan-Network
chmod +x titan.sh
sudo ./titan.sh
```

## Ghi chú
- Khi được yêu cầu, chuẩn bị **KEY**/mã đăng ký của tài khoản Titan để bind node.
- Nếu script hỏi cài **Snap/Multipass** hoặc các gói phụ thuộc, hãy đồng ý để đi đúng hướng dẫn của dự án.
- Muốn dừng/gỡ node: chạy lại `./titan.sh` và chọn mục **Uninstall/Remove** (nếu menu có).
