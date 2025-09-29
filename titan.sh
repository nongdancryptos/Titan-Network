#!/usr/bin/env bash
# Titan multi-node launcher with Docker + screen (one screen per node)
# - Creates N containers: titan_1 ... titan_N
# - Each has its own data dir: ~/.titanedge-<i> and storage ~/titan_storage_<i>
# - Assigns unique ports: START_PORT, START_PORT+1, ...
# - Binds all nodes with the SAME HASH (your choice; may violate platform policy)
# - Spawns screen sessions: titan-1 ... titan-N, each tailing the node's logs

set -euo pipefail

IMAGE="nezha123/titan-edge"
BIND_URL="https://api-test1.container1.titannet.io/api/v2/device/binding"

# Defaults (you can override by exporting env vars before running)
HASH="${HASH:-}"
NODES="${NODES:-}"
START_PORT="${START_PORT:-1234}"
STORAGE_GB="${STORAGE_GB:-50}"
SLEEP_AFTER_RUN="${SLEEP_AFTER_RUN:-10}"   # seconds to wait after first start
RECREATE="${RECREATE:-false}"               # "true" to recreate containers if exist

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

need_root_pkgs() {
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y curl wget jq lsof unzip ca-certificates screen docker.io
    sudo systemctl enable --now docker || true
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y curl wget jq lsof unzip ca-certificates screen docker
    sudo systemctl enable --now docker || true
  elif command -v yum &>/dev/null; then
    sudo yum install -y curl wget jq lsof unzip ca-certificates screen docker
    sudo systemctl enable --now docker || true
  else
    echo -e "${RED}Không xác định được distro (cần apt/dnf/yum).${NC}"
    exit 1
  fi
}

check_deps() {
  echo -e "${BLUE}Kiểm tra & cài đặt phụ thuộc...${NC}"
  need_root_pkgs

  if ! command -v docker &>/dev/null; then
    echo -e "${RED}Docker chưa cài đặt được. Thoát.${NC}"; exit 1
  fi
  if ! command -v screen &>/dev/null; then
    echo -e "${RED}screen chưa cài đặt được. Thoát.${NC}"; exit 1
  fi

  echo -e "${BLUE}Kéo image Docker: ${IMAGE}...${NC}"
  sudo docker pull "${IMAGE}"
  echo -e "${GREEN}OK.${NC}"
}

ask_if_empty() {
  local varname="$1" prompt="$2"
  local v="${!varname:-}"
  if [[ -z "$v" ]]; then
    read -r -p "$prompt" v
    if [[ -z "$v" ]]; then
      echo -e "${RED}Thiếu thông tin bắt buộc. Thoát.${NC}"
      exit 1
    fi
    eval "$varname=\"\$v\""
  fi
}

assert_int() {
  local name="$1" val="$2"
  if ! [[ "$val" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}${name} phải là số nguyên.${NC}"
    exit 1
  fi
}

free_port_or_exit() {
  local port="$1"
  if lsof -i :"$port" -sTCP:LISTEN &>/dev/null; then
    echo -e "${RED}Cổng $port đang bị chiếm. Hãy đổi START_PORT hoặc tắt dịch vụ đang dùng cổng này.${NC}"
    exit 1
  fi
}

stop_rm_if_exists() {
  local name="$1"
  if sudo docker ps -a --format '{{.Names}}' | grep -wq "$name"; then
    if [[ "$RECREATE" == "true" ]]; then
      echo -e "${YELLOW}Container $name đã tồn tại → dừng & xóa để tạo lại.${NC}"
      sudo docker stop "$name" || true
      sudo docker rm "$name" || true
    else
      echo -e "${YELLOW}Container $name đã tồn tại. Bỏ qua tạo mới (RECREATE=false).${NC}"
      return 1
    fi
  fi
  return 0
}

ensure_config_port_and_storage() {
  local name="$1" port="$2" storage_gb="$3"

  # Thử chờ file config xuất hiện
  local retries=15
  local ok=0
  while (( retries > 0 )); do
    if sudo docker exec "$name" bash -lc 'test -f $HOME/.titanedge/config.toml' ; then
      ok=1; break
    fi
    sleep 2; ((retries--))
  done

  if [[ "$ok" -ne 1 ]]; then
    echo -e "${YELLOW}Chưa thấy config.toml; vẫn tiếp tục chỉnh bằng sed (có thể lần đầu agent sẽ tự tạo sau).${NC}"
  fi

  # Chỉnh StorageGB & ListenAddress
  sudo docker exec "$name" bash -lc "\
    CFG=\$HOME/.titanedge/config.toml; \
    mkdir -p \$HOME/.titanedge/storage; \
    touch \$CFG; \
    if grep -q '^[[:space:]]*StorageGB' \$CFG; then \
      sed -i 's/^[[:space:]]*StorageGB.*/StorageGB = ${storage_gb}/' \$CFG; \
    else \
      echo 'StorageGB = ${storage_gb}' >> \$CFG; \
    fi; \
    if grep -q '^[[:space:]]*ListenAddress' \$CFG; then \
      sed -i 's#^[[:space:]]*ListenAddress.*#ListenAddress = \"0.0.0.0:${port}\"#' \$CFG; \
    else \
      echo 'ListenAddress = \"0.0.0.0:${port}\"' >> \$CFG; \
    fi; \
    echo OK"

  sudo docker restart "$name" >/dev/null
}

bind_node() {
  local name="$1" hash="$2"
  echo -e "${BLUE}Bind node $name ...${NC}"
  # Một số image có binary tên titan-edge; tên entrypoint là "titan-edge" trong PATH
  sudo docker exec "$name" bash -lc "titan-edge bind --hash=${hash} ${BIND_URL}" || {
    echo -e "${YELLOW}Bind cách 1 thất bại, thử qua wrapper 'titan-edge' nếu khác PATH...${NC}"
    sudo docker exec "$name" bash -lc "/usr/local/bin/titan-edge bind --hash=${hash} ${BIND_URL}" || true
  }
}

create_screen_tail() {
  local name="$1" screen_name="$2"
  # Nếu screen tồn tại, bỏ qua
  if screen -ls | grep -wq "$screen_name"; then
    echo -e "${YELLOW}Screen ${screen_name} đã tồn tại. Bỏ qua tạo mới.${NC}"
    return 0
  fi
  # Tạo screen chạy docker logs -f cho container
  screen -S "$screen_name" -dm bash -lc "echo -e '${CYAN}Attaching logs for ${name}...${NC}'; sudo docker logs -f $name"
}

main() {
  echo -e "${CYAN}=== Titan multi-node with Docker + screen ===${NC}"
  check_deps

  ask_if_empty HASH         "Nhập HASH/KEY của bạn: "
  ask_if_empty NODES        "Muốn tạo bao nhiêu node? (ví dụ 5): "
  assert_int "NODES" "$NODES"
  assert_int "START_PORT" "$START_PORT"
  assert_int "STORAGE_GB" "$STORAGE_GB"

  # Kiểm tra tranh chấp cổng trước
  for ((i=0; i<NODES; i++)); do
    free_port_or_exit "$((START_PORT+i))"
  done

  # Dừng & xóa các container cũ thuộc image này nếu RECREATE=true-all
  echo -e "${BLUE}Chuẩn bị tạo ${NODES} node...${NC}"

  for ((i=1; i<=NODES; i++)); do
    name="titan_${i}"
    data_dir="$HOME/.titanedge-${i}"
    storage_dir="$HOME/titan_storage_${i}"
    port="$((START_PORT + i - 1))"
    screen_name="titan-${i}"

    echo -e "${BLUE}# Node ${i}: container=${name}, port=${port}, data=${data_dir}${NC}"

    mkdir -p "$data_dir" "$storage_dir"
    chmod 700 "$data_dir"
    chmod 777 "$storage_dir" || true

    if stop_rm_if_exists "$name"; then
      # Tạo container mới chạy nền (host network để tối ưu)
      sudo docker run -d \
        --restart always \
        --name "$name" \
        --net=host \
        -v "${data_dir}:/root/.titanedge" \
        -v "${storage_dir}:/root/.titanedge/storage" \
        "${IMAGE}" >/dev/null

      echo -e "${GREEN}Container ${name} đã tạo.${NC}"
      sleep "$SLEEP_AFTER_RUN"

      ensure_config_port_and_storage "$name" "$port" "$STORAGE_GB"
      bind_node "$name" "$HASH"
    else
      echo -e "${YELLOW}Bỏ qua tạo mới ${name}.${NC}"
    fi

    create_screen_tail "$name" "$screen_name"
    echo -e "${GREEN}Screen ${screen_name} đang theo dõi logs của ${name}.${NC}\n"
  done

  echo -e "${CYAN}Hoàn tất!${NC}"
  echo -e "Attach xem log một node bất kỳ: ${YELLOW}screen -r titan-1${NC} (hoặc titan-2, titan-3, ...)"
  echo -e "Thoát screen nhưng để chạy nền: nhấn ${YELLOW}Ctrl+A rồi D${NC}"
  echo -e "Xem nhanh trạng thái containers: ${YELLOW}sudo docker ps --format 'table {{.Names}}\t{{.Status}}'${NC}"
  echo -e "Gỡ tất cả (thận trọng): đặt ${YELLOW}RECREATE=true${NC} và xóa containers theo tên titan_* nếu cần."
  echo -e "\n${YELLOW}Note:${NC} Dùng cùng một HASH cho nhiều node có thể vi phạm chính sách nền tảng."
}

main "$@"
