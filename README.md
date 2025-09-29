# Titan Network — Hướng dẫn chạy `titan.sh`

### Link: https://test4.titannet.io/Invitelogin?code=2zNL3u

README này hướng dẫn cách **tải, cấp quyền và chạy** script `titan.sh` từ repo:
`https://github.com/nongdancryptos/Titan-Network` (file `titan.sh`).

> Script dùng để cài và chạy **Titan Agent** theo hướng dẫn của Titan Network (testnet).

---

## Yêu cầu hệ thống

- Linux: **Ubuntu / Debian / Fedora / CentOS/RHEL** (x86/x64)
- Quyền **sudo**
- Tài nguyên khuyến nghị _mỗi node_: **2 vCPU, 4 GB RAM, 50 GB disk**
- Kết nối Internet ổn định
- Có **KEY** (đăng nhập và lấy tại trang Titan testnet)

> Lưu ý chính sách: chạy quá nhiều node trên cùng mạng có thể khiến **kém hiệu quả/không sinh lợi** cho tất cả node của bạn. Xem cảnh báo trên trang Node Details của Titan.  

---

## Cách chạy nhanh (không cần clone)

```bash
# Tải script trực tiếp từ GitHub
curl -fsSL https://raw.githubusercontent.com/nongdancryptos/Titan-Network/main/titan.sh -o titan.sh

# Cấp quyền thực thi
chmod +x titan.sh

# Chạy (nên dùng sudo)
sudo ./titan.sh
```
- Script có thể hiển thị **menu** (cài đặt, xem log, khởi động lại, gỡ cài đặt…). Hãy làm theo hướng dẫn trên màn hình.
- Nếu script yêu cầu, chuẩn bị **KEY** của tài khoản Titan để bind khi chạy agent.

---

## Cách chạy khi clone repo

```bash
git clone https://github.com/nongdancryptos/Titan-Network.git
cd Titan-Network
chmod +x titan.sh
sudo ./titan.sh
```

---

## Những việc script thường thực hiện

Tùy bản cập nhật, `titan.sh` thường sẽ:
- Kiểm tra/cài đặt các phụ thuộc cần thiết (vd. `wget`, `unzip`, …).  
- (Theo khuyến nghị từ guide) Kiểm tra **Snap** và cài **Multipass** nếu cần.  
- Tải **Titan Agent** (`agent-linux.zip`) và giải nén vào thư mục làm việc (ví dụ `/opt/titanagent`).  
- Yêu cầu bạn **nhập KEY** để bind node, rồi chạy:
  ```bash
  ./agent --working-dir=<thư-mục> --server-url=https://test4-api.titannet.io --key=<KEY>
  ```
- (Tùy chọn) Thiết lập chạy nền (service/screen) hoặc hiển thị menu quản lý (log, restart, uninstall).

> Vì `titan.sh` có thể thay đổi theo thời gian, hãy đọc thông báo ngay trong terminal khi chạy để biết chính xác các bước thực hiện.

---

## Quản lý sau khi cài

- **Xem log (ví dụ nếu chạy foreground):**
  ```bash
  tail -f /opt/titanagent/agent.log   # đường dẫn thực tế có thể khác
  ```
- **Nếu script tạo service (ví dụ `titan-agent`):**
  ```bash
  systemctl status titan-agent --no-pager
  journalctl -u titan-agent -f
  systemctl restart titan-agent
  systemctl stop titan-agent
  ```
- **Gỡ cài đặt:** chạy lại `./titan.sh` và chọn mục **Uninstall/Remove** (nếu có), hoặc dừng service và xóa thư mục làm việc theo hướng dẫn trên màn hình.

---

## Sự cố thường gặp

- **Không tải được agent** → kiểm tra mạng/DNS rồi chạy lại.  
- **Thiếu quyền thực thi** → `chmod +x titan.sh` (và `chmod +x agent`).  
- **Thiếu KEY / KEY sai** → đăng nhập testnet và lấy KEY đúng, chạy lại.  
- **Cổng bị chiếm** → nếu script cho phép cấu hình cổng, đổi cổng khác (hoặc dừng dịch vụ đang chiếm cổng).

---

## Ghi chú an toàn & chính sách

- Tránh chạy quá nhiều node trên cùng một mạng nếu **băng thông upstream** không đủ lớn; điều này có thể làm **giảm hiệu quả** của toàn bộ node bạn.
- Giữ máy **online ổn định**, ưu tiên khung **18:00–24:00 (UTC+8)** để tối ưu sản lượng theo gợi ý cộng đồng.

---

## Tham khảo

- Titan Testnet: https://test4.titannet.io  
- Mã nguồn Titan Agent / Node (official org): https://github.com/Titannet-dao
