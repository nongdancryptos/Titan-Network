#!/usr/bin/env bash
# Titan Agent multi-node (native) — auto-pick ports, run each in its own screen
# - Reads KEY from ./key.txt (first non-empty line)
# - Asks how many nodes to create (N)
# - Downloads agent once, creates /opt/titanagent-1..N
# - For each node:
#     * find a free TCP port (start hint 1234, bump until free)
#     * write ListenAddress="0.0.0.0:<port>" to config.toml (+ StorageGB default)
#     * launch: ./agent --working-dir=<dir> --server-url=https://test4-api.titannet.io --key=<KEY>
#     * tail logs in screen: titan-<i>
# - (Optional) installs snap + multipass per guide; skip with --no-multipass

set -euo pipefail

AGENT_ZIP_URL="https://pcdn.titannet.io/test4/bin/agent-linux.zip"
SERVER_URL="https://test4-api.titannet.io"
BASE_DIR="/opt"
WORKDIR_PREFIX="${BASE_DIR}/titanagent"
TMP_ZIP="/tmp/agent-linux.zip"

# Defaults
STORAGE_GB="${STORAGE_GB:-50}"
PORT_HINT="${PORT_HINT:-1234}"   # điểm bắt đầu dò; có thể export PORT_HINT=15000 nếu thích

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
  info "Installing prerequisites (wget unzip ca-certificates screen lsof ss)..."
  case "$pmgr" in
    apt)
      apt update -y
      DEBIAN_FRONTEND=noninteractive apt install -y wget unzip ca-certificates screen lsof iproute2
      update-ca-certificates || true
      ;;
    dnf)
      dnf install -y wget unzip ca-certificates screen lsof iproute || true
      update-ca-trust || true
      ;;
    yum)
      yum install -y wget unzip ca-certificates screen lsof iproute || true
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
    err "Missing key.txt next to the script. Put your KEY (single line) in it."
    exit 1
  fi
  TITAN_KEY="$(grep -m1 -E '.+' "$key_file" | tr -d '[:space:]' || true)"
  if [[ -z "${TITAN_KEY:-}" ]]; then
    err "key.txt is empty. Put your KEY in it."
    exit 1
  fi
  ok "Loaded KEY from key.txt"
}

assert_int(){ [[ "$2" =~ ^[0-9]+$ ]] || { err "$1 must be an integer."; exit 1; }; }

ask_nodes(){
  local n="${NODES:-}"
  if [[ -z "$n" ]]; then
    read -r -p "Bạn muốn tạo bao nhiêu node? (ví dụ 5): " n
  fi
  assert_int "Node count" "$n"
  [[ "$n" -ge 1 ]] || { err "Số node phải ≥ 1."; exit 1; }
  NODES="$n"
  ok "Will create $NODES node(s)."
}

is_port_free(){
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$p )" 2>/dev/null | grep -q ":$p"
  else
    ! lsof -i :"$p" -sTCP:LISTEN >/dev/null 2>&1
  fi
}

pick_free_port(){
  local start="$1"
  local p="$start"
  # tránh trùng với các port đã cấp ở vòng lặp trước
  local used_list="$2"  # chuỗi cách nhau bởi dấu phẩy, ví dụ "1234,1235"
  while true; do
    if [[ -n "$used_list" && ",$used_list," == *",$p,"* ]]; then
      p=$((p+1)); continue
    fi
    if is_port_free "$p"; then
      echo "$p"; return 0
    fi
    p=$((p+1))
    if (( p > 65530 )); then
      err "Không tìm thấy cổng trống hợp lệ."
      return 1
    fi
  done
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

write_config(){
  local dir="$1" port="$2"
  local cfg="${dir}/config.toml"
  touch "$cfg"
  # ListenAddress
  if grep -q '^[[:space:]]*ListenAddress' "$cfg"; then
    sed -i "s#^[[:space:]]*ListenAddress.*#ListenAddress = \"0.0.0.0:${port}\"#g" "$cfg"
  else
    echo "ListenAddress = \"0.0.0.0:${port}\"" >> "$cfg"
  fi
  # Optional StorageGB (nếu chưa có)
  if ! grep -q '^[[:space:]]*StorageGB' "$cfg"; then
    echo "StorageGB = ${STORAGE_GB}" >> "$cfg"
  fi
  ok "Config set: ${cfg} ⇒ ListenAddress=0.0.0.0:${port}, StorageGB=${STORAGE_GB}"
}

start_node_in_screen(){
  local idx="$1" dir="$2"
  local sname="titan-${idx}"
  # Kill screen cũ nếu trùng tên (an toàn hơn)
  if screen -ls | grep -wq "$sname"; then
    warn "Screen ${sname} existed → killing it to restart..."
    screen -S "$sname" -X quit || true
    sleep 1
  fi
  info "Starting node #$idx in screen '${sname}'..."
  screen -S "$sname" -dm bash -lc "cd '$dir'; ./agent --working-dir='$dir' --server-url='${SERVER_URL}' --key='${TITAN_KEY}' 2>&1 | tee -a agent.log"
  ok "Node #$idx started. Attach: screen -r ${sname}"
}

main(){
  require_root

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

  local used_ports=""
  for ((i=1; i<=NODES; i++)); do
    # chọn cổng trống
    free_p="$(pick_free_port "$PORT_HINT" "$used_ports")"
    used_ports="${used_ports:+$used_ports,}$free_p"

    node_dir="$(prepare_node_dir "$i")"
    write_config "$node_dir" "$free_p"
    start_node_in_screen "$i" "$node_dir"
  done

  echo
  echo -e "${G}Hoàn tất!${N} Screens created:"
  screen -ls || true
  echo -e "Attach: ${Y}screen -r titan-1${N} (hoặc titan-2, titan-3, ...)"
  echo -e "Detach: ${Y}Ctrl+A rồi D${N}"
  echo -e "Workdirs: ${Y}${WORKDIR_PREFIX}-1 .. ${WORKDIR_PREFIX}-${NODES}${N}"
  echo -e "Logs: ${Y}${WORKDIR_PREFIX}-<i>/agent.log${N}"
}

main "$@"
