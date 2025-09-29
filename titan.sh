#!/usr/bin/env bash
# Titan Agent multi-node (native) per project guide — WITH UNIQUE PORTS
# - Reads KEY from ./key.txt
# - Asks how many nodes to run
# - Creates /opt/titanagent-1..N
# - Sets unique ListenAddress ports (START_PORT, START_PORT+1, ...)
# - Spawns N screen sessions: titan-1..titan-N
# - Installs Snap+Multipass per guide (skip with --no-multipass)

set -euo pipefail

AGENT_ZIP_URL="https://pcdn.titannet.io/test4/bin/agent-linux.zip"
SERVER_URL="https://test4-api.titannet.io"
BASE_DIR="/opt"
WORKDIR_PREFIX="${BASE_DIR}/titanagent"
TMP_ZIP="/tmp/agent-linux.zip"

# Config
START_PORT="${START_PORT:-1234}"   # cổng đầu tiên cho node #1
STORAGE_GB="${STORAGE_GB:-50}"     # (tùy chọn) nếu agent đọc từ config.toml

# Colors
G='\033[1;32m'; B='\033[1;34m'; Y='\033[1;33m'; R='\033[1;31m'; N='\033[0m'
info(){ echo -e "${B}[INFO]${N} $*"; }
ok(){   echo -e "${G}[ OK ]${N} $*"; }
warn(){ echo -e "${Y}[WARN]${N} $*"; }
err(){  echo -e "${R}[ERR ]${N} $*" >&2; }

require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { err "Please run as root (sudo)."; exit 1; }; }

detect_pmgr(){
  if command -v apt >/dev/null 2>&1; then echo apt
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v yum >/dev/null 2>&1; then echo yum
  else err "Unsupported distro (need apt/dnf/yum)."; exit 1; fi
}

ensure_prereqs(){
  local pmgr; pmgr=$(detect_pmgr)
  info "Installing prerequisites (wget unzip ca-certificates screen lsof)..."
  case "$pmgr" in
    apt)
      apt update -y
      DEBIAN_FRONTEND=noninteractive apt install -y wget unzip ca-certificates screen lsof
      update-ca-certificates || true
      ;;
    dnf)
      dnf install -y wget unzip ca-certificates screen lsof || true
      update-ca-trust || true
      ;;
    yum)
      yum install -y wget unzip ca-certificates screen lsof || true
      update-ca-trust || true
      ;;
  esac
  ok "Prerequisites ready."
}

ensure_snap_multipass(){
  if ! command -v snap >/dev/null 2>&1; then
    info "snap not found → installing snapd (per guide)..."
    local pmgr; pmgr=$(detect_pmgr)
    case "$pmgr" in
      apt) apt update -y; apt install -y snapd ;;
      dnf) dnf install -y snapd ;;
      yum) yum install -y snapd ;;
    esac
    ok "snapd installed."
  else
    ok "snap is present."
  fi
  info "Enabling snapd.socket..."
  systemctl enable --now snapd.socket || true
  ok "snapd.socket enabled."

  if ! command -v multipass >/dev/null 2>&1; then
    info "Installing Multipass via snap (per guide)..."
    snap install multipass
    ok "Multipass installed."
  else
    ok "Multipass is already installed."
  fi

  info "Multipass version:"
  multipass --version || warn "Could not run 'multipass --version'; continuing."
}

read_key_from_file(){
  local key_file="./key.txt"
  if [[ ! -f "$key_file" ]]; then
    err "Missing key.txt next to the script. Create it with your KEY (single line)."
    exit 1
  fi
  TITAN_KEY="$(grep -m1 -E '.+' "$key_file" | tr -d '[:space:]' || true)"
  if [[ -z "${TITAN_KEY:-}" ]]; then
    err "key.txt is empty. Put your KEY in it."
    exit 1
  fi
  ok "Loaded KEY from key.txt"
}

assert_int(){ [[ "$2" =~ ^[0-9]+$ ]] || { err "$1 phải là số nguyên."; exit 1; }; }

ask_nodes(){
  local n="${NODES:-}"
  if [[ -z "$n" ]]; then
    read -r -p "Bạn muốn tạo bao nhiêu node? (ví dụ 5): " n
  fi
  assert_int "Số node" "$n"
  [[ "$n" -ge 1 ]] || { err "Số node phải ≥ 1."; exit 1; }
  NODES="$n"
  assert_int "START_PORT" "$START_PORT"
  ok "Will create $NODES node(s), starting port at $START_PORT."
}

free_port_or_exit(){
  local port="$1"
  if lsof -i :"$port" -sTCP:LISTEN &>/dev/null; then
    err "Cổng $port đang bị chiếm. Đổi START_PORT hoặc giải phóng cổng."
    exit 1
  fi
}

download_agent_once(){
  info "Downloading agent package..."
  rm -f "$TMP_ZIP"
  if ! wget -q -O "$TMP_ZIP" "$AGENT_ZIP_URL"; then
    err "Failed to download agent zip. Check network and retry."
    exit 1
  fi
  ok "Downloaded to $TMP_ZIP"
}

prepare_node_dir(){
  local idx="$1"
  local dir="${WORKDIR_PREFIX}-${idx}"
  mkdir -p "$dir"
  unzip -o "$TMP_ZIP" -d "$dir" >/dev/null
  chmod +x "$dir/agent" || true
  echo "$dir"
}

write_port_config(){
  # Tạo/ghi config.toml trong WORKDIR để set ListenAddress và (tuỳ chọn) StorageGB
  local dir="$1" port="$2"
  local cfg="${dir}/config.toml"
  touch "$cfg"
  # Ghi/replace ListenAddress
  if grep -q '^[[:space:]]*ListenAddress' "$cfg"; then
    sed -i "s#^[[:space:]]*ListenAddress.*#ListenAddress = \"0.0.0.0:${port}\"#g" "$cfg"
  else
    echo "ListenAddress = \"0.0.0.0:${port}\"" >> "$cfg"
  fi
  # (tuỳ chọn) ghi StorageGB nếu muốn giữ cấu hình tập trung
  if ! grep -q '^[[:space:]]*StorageGB' "$cfg"; then
    echo "StorageGB = ${STORAGE_GB}" >> "$cfg"
  fi
  ok "Port set: ${cfg} ⇒ 0.0.0.0:${port}"
}

start_node_in_screen(){
  local idx="$1" dir="$2"
  local sname="titan-${idx}"
  if screen -ls | grep -wq "$sname"; then
    warn "Screen ${sname} đã tồn tại → bỏ qua start trùng."
    return 0
  fi
  info "Starting node #$idx in screen '${sname}'..."
  # Chạy agent; agent sẽ đọc config.toml trong WORKDIR
  screen -S "$sname" -dm bash -lc "cd '$dir'; ./agent --working-dir='$dir' --server-url='${SERVER_URL}' --key='${TITAN_KEY}' 2>&1 | tee -a agent.log"
  ok "Node #$idx started. Attach: screen -r ${sname}"
}

main(){
  require_root

  # flags
  local DO_MULTIPASS="true"
  while (( "$#" )); do
    case "$1" in
      --no-multipass) DO_MULTIPASS="false" ;;
      *) err "Unknown option: $1"; exit 1 ;;
    esac
    shift
  done

  ensure_prereqs
  [[ "$DO_MULTIPASS" == "true" ]] && ensure_snap_multipass || warn "Skipping Multipass install (--no-multipass)."

  read_key_from_file
  ask_nodes
  download_agent_once

  # check trước các cổng
  for ((i=0; i<NODES; i++)); do
    free_port_or_exit "$((START_PORT+i))"
  done

  for ((i=1; i<=NODES; i++)); do
    local_port="$((START_PORT + i - 1))"
    node_dir="$(prepare_node_dir "$i")"
    write_port_config "$node_dir" "$local_port"
    start_node_in_screen "$i" "$node_dir"
  done

  echo
  echo -e "${G}All done!${N} Screens created:"
  screen -ls || true
  echo -e "Attach a node log: ${Y}screen -r titan-1${N} (hoặc titan-2, titan-3, ...)"
  echo -e "Detach (keep running): ${Y}Ctrl+A rồi D${N}"
  echo -e "Workdirs: ${Y}${WORKDIR_PREFIX}-1 .. ${WORKDIR_PREFIX}-${NODES}${N}"
  echo -e "Logs: ${Y}/opt/titanagent-<i>/agent.log${N}"
}

main "$@"
