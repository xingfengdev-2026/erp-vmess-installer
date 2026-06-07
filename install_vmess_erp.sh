#!/usr/bin/env bash
set -Eeuo pipefail

ERP_SERVER_ADDR="${ERP_SERVER_ADDR:-}"
ERP_TOKEN="${ERP_TOKEN:-19890604}"
ERP_TRANSPORT="${ERP_TRANSPORT:-raw}"
ERP_REMOTE_PORT="${ERP_REMOTE_PORT:-}"
XRAY_LOCAL_PORT="${XRAY_LOCAL_PORT:-10086}"
XRAY_UUID="${XRAY_UUID:-}"
CLIENT_ID="${CLIENT_ID:-}"
GITHUB_PROXY_PREFIX="${GITHUB_PROXY_PREFIX:-}"
RUN_MODE="${RUN_MODE:-auto}"
INTERACTIVE="${INTERACTIVE:-0}"
INSTALL_ROOT="${INSTALL_ROOT:-}"

INSTALL_BIN_DIR="${INSTALL_BIN_DIR:-}"
XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-}"
XRAY_ASSET_DIR="${XRAY_ASSET_DIR:-}"
ERP_CONFIG_DIR="${ERP_CONFIG_DIR:-}"
LOG_DIR="${LOG_DIR:-}"
XRAY_CONFIG_PATH=""
ERP_CONFIG_PATH=""
TMP_DIR=""

log() {
  printf '[INFO] %s\n' "$*" >&2
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./install_vmess_erp.sh --remote-port PORT [options]
  ./install_vmess_erp.sh --interactive

Required (unless using --interactive):
  --server ADDR            erp server control address as host:port.
  --remote-port PORT       Public TCP port opened on the erp server.

Options:
  --token TOKEN            erp shared token. Default: 19890604
  --transport NAME         erp transport. Default: raw
  --xray-port PORT         Local Xray VMess port. Default: 10086
  --uuid UUID              VMess UUID. Default: generated automatically
  --client-id ID           erp client id. Default: hostname
  --github-proxy-prefix URL
                           Optional GitHub download accelerator URL prefix.
                           Default: none (download from GitHub directly).
  --run-mode MODE          auto, systemd, or tmux. Default: auto
  --install-root PATH      Install root for tmux mode, or custom root for all files.
                           Default tmux path: $HOME/.local/share/erp-vmess
  --interactive            Prompt for the main parameters.
  -h, --help               Show this help.

Environment variables with the same names are also supported:
  ERP_SERVER_ADDR ERP_TOKEN ERP_TRANSPORT ERP_REMOTE_PORT XRAY_LOCAL_PORT
  XRAY_UUID CLIENT_ID GITHUB_PROXY_PREFIX RUN_MODE INSTALL_ROOT INTERACTIVE

Example:
  ./install_vmess_erp.sh --interactive
  sudo ./install_vmess_erp.sh --server example.com:6000 --remote-port 10086
  ERP_SERVER_ADDR=example.com:6000 ERP_REMOTE_PORT=10086 RUN_MODE=tmux ./install_vmess_erp.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote-port)
      [[ $# -ge 2 ]] || die "--remote-port requires a value"
      ERP_REMOTE_PORT="$2"
      shift 2
      ;;
    --remote-port=*)
      ERP_REMOTE_PORT="${1#*=}"
      shift
      ;;
    --server)
      [[ $# -ge 2 ]] || die "--server requires a value"
      ERP_SERVER_ADDR="$2"
      shift 2
      ;;
    --server=*)
      ERP_SERVER_ADDR="${1#*=}"
      shift
      ;;
    --token)
      [[ $# -ge 2 ]] || die "--token requires a value"
      ERP_TOKEN="$2"
      shift 2
      ;;
    --token=*)
      ERP_TOKEN="${1#*=}"
      shift
      ;;
    --transport)
      [[ $# -ge 2 ]] || die "--transport requires a value"
      ERP_TRANSPORT="$2"
      shift 2
      ;;
    --transport=*)
      ERP_TRANSPORT="${1#*=}"
      shift
      ;;
    --xray-port)
      [[ $# -ge 2 ]] || die "--xray-port requires a value"
      XRAY_LOCAL_PORT="$2"
      shift 2
      ;;
    --xray-port=*)
      XRAY_LOCAL_PORT="${1#*=}"
      shift
      ;;
    --uuid)
      [[ $# -ge 2 ]] || die "--uuid requires a value"
      XRAY_UUID="$2"
      shift 2
      ;;
    --uuid=*)
      XRAY_UUID="${1#*=}"
      shift
      ;;
    --client-id)
      [[ $# -ge 2 ]] || die "--client-id requires a value"
      CLIENT_ID="$2"
      shift 2
      ;;
    --client-id=*)
      CLIENT_ID="${1#*=}"
      shift
      ;;
    --github-proxy-prefix)
      [[ $# -ge 2 ]] || die "--github-proxy-prefix requires a value"
      GITHUB_PROXY_PREFIX="$2"
      shift 2
      ;;
    --github-proxy-prefix=*)
      GITHUB_PROXY_PREFIX="${1#*=}"
      shift
      ;;
    --run-mode)
      [[ $# -ge 2 ]] || die "--run-mode requires a value"
      RUN_MODE="$2"
      shift 2
      ;;
    --run-mode=*)
      RUN_MODE="${1#*=}"
      shift
      ;;
    --install-root)
      [[ $# -ge 2 ]] || die "--install-root requires a value"
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --install-root=*)
      INSTALL_ROOT="${1#*=}"
      shift
      ;;
    --interactive)
      INTERACTIVE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

is_root() {
  [[ "$(id -u)" -eq 0 ]]
}

is_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] && (( 10#$value >= 1 && 10#$value <= 65535 ))
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

default_client_id() {
  hostname 2>/dev/null || printf 'erp-client'
}

systemd_is_usable() {
  have_cmd systemctl && [[ -d /run/systemd/system ]]
}

default_run_mode() {
  if is_root && systemd_is_usable; then
    printf 'systemd\n'
  else
    printf 'tmux\n'
  fi
}

prompt_value() {
  local var_name="$1"
  local label="$2"
  local default_value="$3"
  local current_value
  local input

  eval "current_value=\"\${${var_name}:-}\""
  if [[ -n "$current_value" ]]; then
    default_value="$current_value"
  fi

  if [[ -n "$default_value" ]]; then
    read -r -p "${label} [${default_value}]: " input
    input="${input:-$default_value}"
  else
    read -r -p "${label}: " input
  fi
  printf -v "$var_name" '%s' "$input"
}

prompt_optional_value() {
  local var_name="$1"
  local label="$2"
  local default_value="$3"
  local current_value
  local input

  eval "current_value=\"\${${var_name}:-}\""
  if [[ -n "$current_value" ]]; then
    default_value="$current_value"
  fi

  if [[ -n "$default_value" ]]; then
    read -r -p "${label} [${default_value}, blank for auto/default]: " input
  else
    read -r -p "${label} [blank for auto/default]: " input
  fi

  if [[ -n "$input" ]]; then
    printf -v "$var_name" '%s' "$input"
  fi
}

prompt_interactive_inputs() {
  [[ -t 0 ]] || die "--interactive requires a TTY."

  prompt_value ERP_SERVER_ADDR "erp server control address" "$ERP_SERVER_ADDR"
  prompt_value ERP_TOKEN "erp token" "$ERP_TOKEN"
  prompt_value ERP_TRANSPORT "erp transport" "$ERP_TRANSPORT"
  prompt_value ERP_REMOTE_PORT "erp server public remote port" "${ERP_REMOTE_PORT:-10086}"
  prompt_value XRAY_LOCAL_PORT "local Xray VMess port" "$XRAY_LOCAL_PORT"
  prompt_optional_value XRAY_UUID "VMess UUID" "$XRAY_UUID"
  prompt_value CLIENT_ID "erp client id" "${CLIENT_ID:-$(default_client_id)}"
  prompt_value GITHUB_PROXY_PREFIX "GitHub accelerator prefix" "$GITHUB_PROXY_PREFIX"
  prompt_value RUN_MODE "run mode (auto/systemd/tmux)" "$RUN_MODE"

  if [[ "$RUN_MODE" == "tmux" || "$RUN_MODE" == "auto" ]]; then
    prompt_optional_value INSTALL_ROOT "install root" "${INSTALL_ROOT:-${HOME:-$PWD}/.local/share/erp-vmess}"
  else
    prompt_optional_value INSTALL_ROOT "install root" "$INSTALL_ROOT"
  fi
}

resolve_run_mode() {
  case "$RUN_MODE" in
    auto)
      RUN_MODE="$(default_run_mode)"
      ;;
    systemd|tmux)
      ;;
    *)
      die "RUN_MODE must be auto, systemd, or tmux."
      ;;
  esac

  if [[ "$RUN_MODE" == "systemd" ]]; then
    is_root || die "RUN_MODE=systemd requires root. Use --run-mode tmux for a non-root install."
    systemd_is_usable || die "RUN_MODE=systemd requires a running systemd."
  fi
}

resolve_install_paths() {
  if [[ -n "$INSTALL_ROOT" ]]; then
    INSTALL_ROOT="${INSTALL_ROOT%/}"
    INSTALL_BIN_DIR="${INSTALL_BIN_DIR:-${INSTALL_ROOT}/bin}"
    XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-${INSTALL_ROOT}/xray}"
    XRAY_ASSET_DIR="${XRAY_ASSET_DIR:-${INSTALL_ROOT}/xray/assets}"
    ERP_CONFIG_DIR="${ERP_CONFIG_DIR:-${INSTALL_ROOT}/erp}"
    LOG_DIR="${LOG_DIR:-${INSTALL_ROOT}/logs}"
  elif [[ "$RUN_MODE" == "tmux" ]]; then
    INSTALL_ROOT="${HOME:-$PWD}/.local/share/erp-vmess"
    INSTALL_BIN_DIR="${INSTALL_BIN_DIR:-${INSTALL_ROOT}/bin}"
    XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-${INSTALL_ROOT}/xray}"
    XRAY_ASSET_DIR="${XRAY_ASSET_DIR:-${INSTALL_ROOT}/xray/assets}"
    ERP_CONFIG_DIR="${ERP_CONFIG_DIR:-${INSTALL_ROOT}/erp}"
    LOG_DIR="${LOG_DIR:-${INSTALL_ROOT}/logs}"
  else
    INSTALL_BIN_DIR="${INSTALL_BIN_DIR:-/usr/local/bin}"
    XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-/usr/local/etc/xray}"
    XRAY_ASSET_DIR="${XRAY_ASSET_DIR:-/usr/local/share/xray}"
    ERP_CONFIG_DIR="${ERP_CONFIG_DIR:-/etc/erp}"
    LOG_DIR="${LOG_DIR:-/var/log/erp-vmess}"
  fi

  XRAY_CONFIG_PATH="${XRAY_CONFIG_DIR}/config.json"
  ERP_CONFIG_PATH="${ERP_CONFIG_DIR}/client.raw.toml"
}

control_port_from_addr() {
  local addr="$1"
  if [[ "$addr" =~ :([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

server_host_from_addr() {
  local addr="$1"
  if [[ "$addr" =~ ^\[([^]]+)\]:[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$addr" =~ ^([^:]+):[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "$addr"
  fi
}

validate_inputs() {
  [[ "$(uname -s)" == "Linux" ]] || die "This installer only supports Linux."

  if [[ -z "$ERP_SERVER_ADDR" ]]; then
    if [[ -t 0 ]]; then
      prompt_value ERP_SERVER_ADDR "erp server control address (host:port)" ""
    else
      die "ERP_SERVER_ADDR is required. Pass --server host:port or set ERP_SERVER_ADDR."
    fi
  fi

  if [[ -z "$ERP_REMOTE_PORT" ]]; then
    if [[ -t 0 ]]; then
      prompt_value ERP_REMOTE_PORT "erp server public remote port" "10086"
    else
      die "ERP_REMOTE_PORT is required in non-interactive mode."
    fi
  fi

  is_port "$ERP_REMOTE_PORT" || die "ERP_REMOTE_PORT must be an integer from 1 to 65535."
  is_port "$XRAY_LOCAL_PORT" || die "XRAY_LOCAL_PORT must be an integer from 1 to 65535."
  [[ -n "$ERP_SERVER_ADDR" ]] || die "ERP_SERVER_ADDR must not be empty."
  [[ -n "$ERP_TOKEN" ]] || die "ERP_TOKEN must not be empty."
  [[ "$ERP_TRANSPORT" == "raw" ]] || die "This script implements erp raw transport only."

  local control_port
  control_port="$(control_port_from_addr "$ERP_SERVER_ADDR" || true)"
  if [[ -n "$control_port" && "$ERP_REMOTE_PORT" == "$control_port" ]]; then
    die "ERP_REMOTE_PORT must not equal the erp control port ${control_port}."
  fi

  if [[ -z "$CLIENT_ID" ]]; then
    CLIENT_ID="$(default_client_id)"
  fi

  if [[ -z "$XRAY_UUID" ]]; then
    XRAY_UUID="$(generate_uuid)"
  fi

  if [[ ! "$XRAY_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    die "XRAY_UUID is not a valid UUID: ${XRAY_UUID}"
  fi
}

generate_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  elif command -v openssl >/dev/null 2>&1; then
    local hex
    hex="$(openssl rand -hex 16)"
    printf '%s-%s-%s-%s-%s\n' \
      "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}"
  else
    die "Cannot generate UUID. Install uuidgen or openssl, or pass --uuid."
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_packages() {
  local packages=("$@")
  if [[ ${#packages[@]} -eq 0 ]]; then
    packages=(ca-certificates curl unzip)
  fi

  if have_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y "${packages[@]}"
  elif have_cmd dnf; then
    dnf install -y "${packages[@]}"
  elif have_cmd yum; then
    yum install -y "${packages[@]}"
  elif have_cmd apk; then
    apk add --no-cache "${packages[@]}"
  elif have_cmd zypper; then
    zypper --non-interactive install "${packages[@]}"
  elif have_cmd pacman; then
    pacman -Sy --noconfirm "${packages[@]}"
  else
    die "No supported package manager found. Install ${packages[*]} manually."
  fi

  if have_cmd update-ca-certificates; then
    update-ca-certificates || true
  fi
}

ensure_dependencies() {
  local missing=()

  have_cmd curl || missing+=(curl)
  have_cmd unzip || missing+=(unzip)
  if [[ "$RUN_MODE" == "tmux" ]]; then
    have_cmd tmux || missing+=(tmux)
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    if is_root; then
      log "Installing required packages: ca-certificates ${missing[*]}"
      install_packages ca-certificates "${missing[@]}"
    else
      die "Missing required command(s): ${missing[*]}. Install them first, or run as root so the script can install packages."
    fi
  fi

  have_cmd curl || die "curl is required."
  have_cmd unzip || die "unzip is required."
  if [[ "$RUN_MODE" == "tmux" ]]; then
    have_cmd tmux || die "tmux is required for RUN_MODE=tmux."
  fi
  have_cmd install || die "install from coreutils is required."
  have_cmd awk || die "awk is required."
  have_cmd sed || die "sed is required."
  have_cmd base64 || die "base64 is required."
}

proxify_url() {
  local url="$1"
  local prefix="${GITHUB_PROXY_PREFIX%/}"
  if [[ -n "$prefix" ]]; then
    printf '%s/%s\n' "$prefix" "$url"
  else
    printf '%s\n' "$url"
  fi
}

fetch_text() {
  local url="$1"
  curl -fsSL --show-error --retry 3 --connect-timeout 20 \
    -H 'User-Agent: erp-vmess-installer' \
    "$url"
}

download_file() {
  local url="$1"
  local output="$2"
  curl -fsSL --show-error --retry 3 --connect-timeout 20 \
    -H 'User-Agent: erp-vmess-installer' \
    -o "$output" \
    "$url"
}

asset_url_from_latest_release() {
  local repo="$1"
  local asset_name="$2"
  local api_url="https://api.github.com/repos/${repo}/releases/latest"
  local json
  local asset_url

  log "Resolving ${repo} latest asset: ${asset_name}"
  json="$(fetch_text "$(proxify_url "$api_url")")"
  asset_url="$(
    printf '%s\n' "$json" |
      tr ',' '\n' |
      awk -v asset="/${asset_name}" '
        /"browser_download_url":/ {
          line = $0
          sub(/^[^:]*:[[:space:]]*"/, "", line)
          sub(/".*$/, "", line)
          if (substr(line, length(line) - length(asset) + 1) == asset) {
            print line
            exit
          }
        }
      '
  )"

  [[ -n "$asset_url" ]] || die "Asset ${asset_name} not found in ${repo} latest release."
  printf '%s\n' "$asset_url"
}

detect_assets() {
  local machine
  machine="$(uname -m)"

  case "$machine" in
    x86_64|amd64)
      XRAY_ASSET_NAME="Xray-linux-64.zip"
      ERP_ASSET_NAME="erp-x86_64-unknown-linux-musl"
      ;;
    aarch64|arm64)
      XRAY_ASSET_NAME="Xray-linux-arm64-v8a.zip"
      die "erp latest release currently has no Linux arm64 binary. Use an x86_64 VPS or build erp from source."
      ;;
    *)
      die "Unsupported CPU architecture for this release-based installer: ${machine}"
      ;;
  esac
}

install_xray() {
  local tmp_dir="$1"
  local asset_url
  local zip_path="${tmp_dir}/${XRAY_ASSET_NAME}"
  local unpack_dir="${tmp_dir}/xray"

  asset_url="$(asset_url_from_latest_release "XTLS/Xray-core" "$XRAY_ASSET_NAME")"
  log "Downloading Xray via GitHub accelerator"
  download_file "$(proxify_url "$asset_url")" "$zip_path"

  mkdir -p "$unpack_dir"
  unzip -q "$zip_path" -d "$unpack_dir"

  [[ -f "${unpack_dir}/xray" ]] || die "Downloaded Xray archive does not contain xray binary."

  install -d -m 0755 "$INSTALL_BIN_DIR" "$XRAY_CONFIG_DIR" "$XRAY_ASSET_DIR"
  install -m 0755 "${unpack_dir}/xray" "${INSTALL_BIN_DIR}/xray"

  if [[ -f "${unpack_dir}/geoip.dat" ]]; then
    install -m 0644 "${unpack_dir}/geoip.dat" "${XRAY_ASSET_DIR}/geoip.dat"
  fi
  if [[ -f "${unpack_dir}/geosite.dat" ]]; then
    install -m 0644 "${unpack_dir}/geosite.dat" "${XRAY_ASSET_DIR}/geosite.dat"
  fi
}

install_erp() {
  local tmp_dir="$1"
  local asset_url
  local bin_path="${tmp_dir}/${ERP_ASSET_NAME}"

  asset_url="$(asset_url_from_latest_release "xingfengdev-2026/erp" "$ERP_ASSET_NAME")"
  log "Downloading erp via GitHub accelerator"
  download_file "$(proxify_url "$asset_url")" "$bin_path"

  install -d -m 0755 "$INSTALL_BIN_DIR"
  install -m 0755 "$bin_path" "${INSTALL_BIN_DIR}/erp"
}

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g'
}

toml_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_xray_config() {
  local old_umask

  log "Writing Xray config: ${XRAY_CONFIG_PATH}"
  install -d -m 0755 "$XRAY_CONFIG_DIR"
  old_umask="$(umask)"
  umask 077
  cat >"$XRAY_CONFIG_PATH" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vmess-in",
      "listen": "127.0.0.1",
      "port": ${XRAY_LOCAL_PORT},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${XRAY_UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
EOF
  chmod 0600 "$XRAY_CONFIG_PATH"
  umask "$old_umask"
}

write_erp_config() {
  local old_umask
  local token_escaped
  local server_addr_escaped
  local client_id_escaped

  token_escaped="$(printf '%s' "$ERP_TOKEN" | toml_escape)"
  server_addr_escaped="$(printf '%s' "$ERP_SERVER_ADDR" | toml_escape)"
  client_id_escaped="$(printf '%s' "$CLIENT_ID" | toml_escape)"

  log "Writing erp client config: ${ERP_CONFIG_PATH}"
  install -d -m 0755 "$ERP_CONFIG_DIR"
  old_umask="$(umask)"
  umask 077
  cat >"$ERP_CONFIG_PATH" <<EOF
role = "client"
token = "${token_escaped}"
transport = "${ERP_TRANSPORT}"

[client]
server_addr = "${server_addr_escaped}"
client_id = "${client_id_escaped}"

[[client.mappings]]
name = "vmess-tcp"
protocol = "tcp"
local_addr = "127.0.0.1:${XRAY_LOCAL_PORT}"
remote_port = ${ERP_REMOTE_PORT}
EOF
  chmod 0600 "$ERP_CONFIG_PATH"
  umask "$old_umask"
}

write_systemd_units() {
  [[ -d /etc/systemd/system ]] || return 0

  log "Writing systemd units"
  cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray VMess TCP inbound
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=XRAY_LOCATION_ASSET=${XRAY_ASSET_DIR}
ExecStart=${INSTALL_BIN_DIR}/xray run -config ${XRAY_CONFIG_PATH}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  cat >/etc/systemd/system/erp-client.service <<EOF
[Unit]
Description=erp client tunnel for local VMess TCP
Documentation=https://github.com/xingfengdev-2026/erp
After=network-online.target xray.service
Wants=network-online.target
Requires=xray.service

[Service]
Type=simple
Environment=RUST_LOG=info
Environment=ERP_NOFILE=1048576
ExecStart=${INSTALL_BIN_DIR}/erp client --config ${ERP_CONFIG_PATH}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  chmod 0644 /etc/systemd/system/xray.service /etc/systemd/system/erp-client.service
}

start_services() {
  if systemd_is_usable; then
    write_systemd_units
    log "Starting systemd services"
    systemctl daemon-reload
    systemctl enable xray.service erp-client.service >/dev/null
    systemctl restart xray.service
    systemctl restart erp-client.service
    sleep 2

    if ! systemctl is-active --quiet xray.service; then
      journalctl -u xray.service --no-pager -n 50 >&2 || true
      die "xray.service is not active."
    fi

    if ! systemctl is-active --quiet erp-client.service; then
      journalctl -u erp-client.service --no-pager -n 50 >&2 || true
      die "erp-client.service is not active."
    fi
  else
    warn "systemd is not running. Services were not started automatically."
    warn "Manual Xray command: XRAY_LOCATION_ASSET=${XRAY_ASSET_DIR} ${INSTALL_BIN_DIR}/xray run -config ${XRAY_CONFIG_PATH}"
    warn "Manual erp command: RUST_LOG=info ERP_NOFILE=1048576 ${INSTALL_BIN_DIR}/erp client --config ${ERP_CONFIG_PATH}"
  fi
}

shell_quote() {
  printf '%q' "$1"
}

start_tmux_runtime() {
  local xray_session="erp-vmess-xray"
  local erp_session="erp-vmess-client"
  local xray_log="${LOG_DIR}/xray.log"
  local erp_log="${LOG_DIR}/erp-client.log"
  local xray_cmd
  local erp_cmd

  install -d -m 0755 "$LOG_DIR"

  tmux kill-session -t "$xray_session" >/dev/null 2>&1 || true
  tmux kill-session -t "$erp_session" >/dev/null 2>&1 || true

  xray_cmd="exec env XRAY_LOCATION_ASSET=$(shell_quote "$XRAY_ASSET_DIR") $(shell_quote "${INSTALL_BIN_DIR}/xray") run -config $(shell_quote "$XRAY_CONFIG_PATH") >>$(shell_quote "$xray_log") 2>&1"
  erp_cmd="exec env RUST_LOG=info ERP_NOFILE=1048576 $(shell_quote "${INSTALL_BIN_DIR}/erp") client --config $(shell_quote "$ERP_CONFIG_PATH") >>$(shell_quote "$erp_log") 2>&1"

  log "Starting tmux sessions"
  tmux new-session -d -s "$xray_session" "$xray_cmd"
  tmux new-session -d -s "$erp_session" "$erp_cmd"
  sleep 2

  if ! tmux has-session -t "$xray_session" >/dev/null 2>&1; then
    tail -n 50 "$xray_log" >&2 || true
    die "tmux session ${xray_session} is not running."
  fi

  if ! tmux has-session -t "$erp_session" >/dev/null 2>&1; then
    tail -n 50 "$erp_log" >&2 || true
    die "tmux session ${erp_session} is not running."
  fi
}

start_runtime() {
  case "$RUN_MODE" in
    systemd)
      start_services
      ;;
    tmux)
      start_tmux_runtime
      ;;
    *)
      die "internal error: unresolved RUN_MODE=${RUN_MODE}"
      ;;
  esac
}

base64_no_wrap() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w 0
  else
    base64 | tr -d '\n'
  fi
}

print_result() {
  local server_host
  local ps_escaped
  local server_host_escaped
  local vmess_json
  local vmess_link

  server_host="$(server_host_from_addr "$ERP_SERVER_ADDR")"
  ps_escaped="$(printf 'erp-vmess-%s' "$CLIENT_ID" | json_escape)"
  server_host_escaped="$(printf '%s' "$server_host" | json_escape)"

  vmess_json="$(cat <<EOF
{
  "v": "2",
  "ps": "${ps_escaped}",
  "add": "${server_host_escaped}",
  "port": "${ERP_REMOTE_PORT}",
  "id": "${XRAY_UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "",
  "sni": "",
  "alpn": "",
  "fp": ""
}
EOF
)"
  vmess_link="vmess://$(printf '%s' "$vmess_json" | base64_no_wrap)"

  cat <<EOF

Installed.

erp server:      ${ERP_SERVER_ADDR}
erp remote port: ${ERP_REMOTE_PORT}
Xray local:      127.0.0.1:${XRAY_LOCAL_PORT}
VMess UUID:      ${XRAY_UUID}
transport:       vmess + tcp + no TLS, erp raw
run mode:        ${RUN_MODE}
install bin:     ${INSTALL_BIN_DIR}

VMess link:
${vmess_link}

VMess JSON:
${vmess_json}

EOF

  if [[ "$RUN_MODE" == "systemd" ]]; then
    cat <<EOF
Useful commands:
  systemctl status xray --no-pager
  systemctl status erp-client --no-pager
  journalctl -u xray -u erp-client --no-pager -n 100
EOF
  else
    cat <<EOF
Useful commands:
  tmux ls
  tmux attach -t erp-vmess-xray
  tmux attach -t erp-vmess-client
  tail -n 100 ${LOG_DIR}/xray.log
  tail -n 100 ${LOG_DIR}/erp-client.log
  tmux kill-session -t erp-vmess-xray
  tmux kill-session -t erp-vmess-client
EOF
  fi
}

main() {
  if is_truthy "$INTERACTIVE"; then
    prompt_interactive_inputs
  fi

  validate_inputs
  resolve_run_mode
  resolve_install_paths
  ensure_dependencies
  detect_assets

  TMP_DIR="$(mktemp -d)"
  trap '[[ -n "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"' EXIT

  install_xray "$TMP_DIR"
  install_erp "$TMP_DIR"
  write_xray_config
  write_erp_config

  if "${INSTALL_BIN_DIR}/xray" run -test -config "$XRAY_CONFIG_PATH"; then
    log "Xray config test passed"
  else
    die "Xray config test failed."
  fi

  "${INSTALL_BIN_DIR}/erp" --version >/dev/null || die "erp binary did not run."

  start_runtime
  print_result
}

main "$@"
