# Titan Multi-Screen (Auto-Port)

Chạy **N Titan Agents** (native, không Docker) — mỗi node 1 thư mục, 1 cổng riêng, 1 screen riêng.

## Chuẩn bị
- Linux (Ubuntu/Debian/Fedora/CentOS/RHEL), quyền `sudo`.
- Tạo **key.txt** (cùng thư mục script) chứa **KEY** 1 dòng:
  ```bash
  echo "YOUR-TITAN-KEY" > key.txt
  ```

## Cách chạy
```bash
chmod +x titan-multiscreen-autopor t.sh
sudo ./titan-multiscreen-autopor t.sh        # hỏi số node, tự tìm cổng trống
# Bỏ qua cài Multipass (nếu muốn):
sudo ./titan-multiscreen-autopor t.sh --no-multipass
```

## Theo dõi & quản lý
- Liệt kê screen: `screen -ls`
- Vào log node #1: `screen -r titan-1`  (thoát: **Ctrl+A**, rồi **D**)
- Log file: `/opt/titanagent-<i>/agent.log`
- Thư mục node: `/opt/titanagent-1 .. /opt/titanagent-N`

## Ghi chú
- Script chạy đúng lệnh dự án:  
  `./agent --working-dir=<dir> --server-url=https://test4-api.titannet.io --key=<KEY>`
- Nhiều node cùng **1 KEY**: kỹ thuật chạy được nhưng có thể **không hợp lệ theo chính sách**. Cân nhắc rủi ro.
