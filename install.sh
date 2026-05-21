#!/usr/bin/env bash
set -euo pipefail

VERSION=1.0.0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

NPM_USER_PREFIX="${HOME}/.local"
export PATH="${NPM_USER_PREFIX}/bin:${PATH}"

QWEN_OSS_SH="${AI_CLI_QWEN_INSTALL_URL:-https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen.sh}"
NPM_MIRROR="${AI_CLI_NPM_REGISTRY:-https://registry.npmmirror.com}"
NPM_OFFICIAL="https://registry.npmjs.org"
OPENCODE_INSTALL="https://opencode.ai/install"
CURL_TIMEOUT=30
CURL_RETRIES=2

LAST_INSTALL_SOURCE=""

log() {
  printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"
}

die() { log "ERROR: $*"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_os_arch() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    linux*) os="linux" ;;
    darwin*) os="darwin" ;;
    msys*|mingw*|cygwin*) os="win32" ;;
    *) os="unknown" ;;
  esac
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
  esac
  echo "$os $arch"
}

ensure_npm_user_prefix() {
  mkdir -p "${NPM_USER_PREFIX}/bin" "${NPM_USER_PREFIX}/lib"
  if command_exists npm; then
    npm config set prefix "${NPM_USER_PREFIX}" >/dev/null 2>&1 || true
  fi
  export NPM_CONFIG_PREFIX="${NPM_USER_PREFIX}"
}

backup_if_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    local bak="${path}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$path" "$bak"
    log "Backed up: $path -> $bak"
  fi
}

prompt_choice() {
  local prompt="$1"
  local default="${2:-}"
  local choice
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " choice || true
    choice="${choice:-$default}"
  else
    read -r -p "$prompt: " choice || true
  fi
  echo "$choice"
}

read_secret() {
  local prompt="$1"
  local secret=""
  read -r -s -p "$prompt: " secret || true
  echo "" >&2
  echo "$secret"
}

curl_retry() {
  local url="$1"
  local out="$2"
  local attempt=1
  local curl_args=(--fail --location --silent --show-error --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT")
  if [[ -n "${HTTPS_PROXY:-}" ]]; then
    curl_args+=(--proxy "$HTTPS_PROXY")
  elif [[ -n "${HTTP_PROXY:-}" ]]; then
    curl_args+=(--proxy "$HTTP_PROXY")
  fi
  while (( attempt <= CURL_RETRIES )); do
    if curl "${curl_args[@]}" -o "$out" "$url"; then
      return 0
    fi
    log "curl retry ${attempt}/${CURL_RETRIES}: $url"
    sleep 3
    attempt=$((attempt + 1))
  done
  return 1
}

run_with_retry() {
  local attempt=1
  while (( attempt <= CURL_RETRIES )); do
    if "$@"; then
      return 0
    fi
    log "Retry ${attempt}/${CURL_RETRIES}: $*"
    sleep 3
    attempt=$((attempt + 1))
  done
  return 1
}

node_major_version() {
  if ! command_exists node; then
    echo "0"
    return
  fi
  node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo "0"
}

npm_install_global() {
  local pkg="$1"
  local registry="$2"
  ensure_npm_user_prefix
  run_with_retry npm install -g "$pkg" --prefix "${NPM_USER_PREFIX}" --registry="$registry"
}

install_qwen_oss() {
  log "Installing Qwen Code via OSS script..."
  local tmp
  tmp="$(mktemp /tmp/install-qwen.XXXXXX.sh)"
  curl_retry "$QWEN_OSS_SH" "$tmp" || return 1
  chmod +x "$tmp"
  bash "$tmp"
  LAST_INSTALL_SOURCE="qwen-oss:${QWEN_OSS_SH}"
}

install_qwen_npm() {
  local registry="$1"
  if ! command_exists npm; then
    die "npm not found; install Node.js 22+ or use OSS install"
  fi
  local major
  major="$(node_major_version)"
  if [[ "$major" -lt 22 ]]; then
    log "Node $(node -v 2>/dev/null || echo unknown) < 22; npm path may fail"
  fi
  npm_install_global "@qwen-code/qwen-code@latest" "$registry"
  LAST_INSTALL_SOURCE="qwen-npm:${registry}"
}

install_qwen() {
  local net="$1"
  case "$net" in
    1)
      if install_qwen_oss; then return 0; fi
      log "OSS install failed, falling back to npm mirror"
      install_qwen_npm "$NPM_MIRROR"
      ;;
    2)
      if install_qwen_oss; then return 0; fi
      log "OSS install failed, falling back to npm official"
      install_qwen_npm "$NPM_OFFICIAL"
      ;;
    3)
      [[ -n "${AI_CLI_QWEN_INSTALL_URL:-}" ]] || die "Set AI_CLI_QWEN_INSTALL_URL for corporate install"
      install_qwen_oss || die "Corporate Qwen install failed"
      ;;
    *) die "Invalid network choice: $net" ;;
  esac
}
install_opencode_npm() {
  local registry="$1"
  command_exists npm || return 1
  npm_install_global "opencode-ai@latest" "$registry"
  LAST_INSTALL_SOURCE="opencode-npm:${registry}"
}

install_opencode_curl() {
  log "Installing OpenCode via official install script..."
  local tmp
  tmp="$(mktemp /tmp/opencode-install.XXXXXX.sh)"
  curl_retry "$OPENCODE_INSTALL" "$tmp" || return 1
  chmod +x "$tmp"
  bash "$tmp"
  LAST_INSTALL_SOURCE="opencode-curl:${OPENCODE_INSTALL}"
}

install_opencode() {
  local net="$1"
  case "$net" in
    1)
      if install_opencode_npm "$NPM_MIRROR"; then return 0; fi
      log "npm mirror failed, falling back to curl installer"
      install_opencode_curl || die "OpenCode install failed"
      ;;
    2)
      install_opencode_npm "$NPM_OFFICIAL" || die "OpenCode npm official install failed"
      ;;
    3)
      local reg="${AI_CLI_NPM_REGISTRY:-$NPM_MIRROR}"
      install_opencode_npm "$reg" || die "OpenCode corporate npm install failed"
      ;;
    *) die "Invalid network choice: $net" ;;
  esac
}

merge_qwen_env_into_settings() {
  local settings="$1"
  local env_file="$2"
  python3 - "$settings" "$env_file" << 'PY'
import json, sys
from pathlib import Path

settings_path = Path(sys.argv[1])
env_path = Path(sys.argv[2])
data = json.loads(settings_path.read_text(encoding="utf-8"))
env_map = {}
if env_path.is_file():
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env_map[k.strip()] = v.strip()
if env_map:
    data.setdefault("env", {})
    data["env"].update(env_map)
settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

setup_qwen_config() {
  local ark_key="$1"
  local bailian_key="$2"
  local cfg_dir="${HOME}/.qwen"
  local settings="${cfg_dir}/settings.json"
  local env_file="${cfg_dir}/.env"
  local tpl="${TEMPLATE_DIR}/qwen-settings.json"

  mkdir -p "$cfg_dir"
  backup_if_exists "$settings"
  backup_if_exists "$env_file"

  cp -f "$tpl" "$settings"
  umask 077
  cat > "$env_file" <<ENVEOF
VOLCENGINE_ARK_CODING_API_KEY=${ark_key}
ALI_BANLIAN_CODING_API_KEY=${bailian_key}
ENVEOF
  chmod 600 "$env_file" 2>/dev/null || true

  merge_qwen_env_into_settings "$settings" "$env_file"
  log "Qwen config: ${settings} ${env_file}"

  local validator="${SCRIPTS_DIR}/validate-qwen-config.sh"
  if [[ -x "$validator" ]]; then
    log "Running Qwen config validation..."
    bash "$validator" "$settings" "$env_file" || log "Validation reported issues (see above)"
  fi
}

setup_opencode_config() {
  local key="$1"
  local provider="${2:-openai}"
  local cfg_dir="${HOME}/.config/opencode"
  local cfg="${cfg_dir}/opencode.json"
  local env_file="${cfg_dir}/.env"
  local tpl="${TEMPLATE_DIR}/opencode.json"

  local env_key="OPENAI_API_KEY"
  case "$provider" in
    anthropic) env_key="ANTHROPIC_API_KEY" ;;
    dashscope) env_key="DASHSCOPE_API_KEY" ;;
    openai|*) env_key="OPENAI_API_KEY" ;;
  esac

  mkdir -p "$cfg_dir"
  backup_if_exists "$cfg"
  backup_if_exists "$env_file"

  cp -f "$tpl" "$cfg"
  umask 077
  printf "%s=%s\n" "$env_key" "$key" > "$env_file"
  chmod 600 "$env_file" 2>/dev/null || true

  log "OpenCode config: ${cfg} (${env_key} in ${env_file})"
}
verify_cli() {
  local cli="$1"
  ensure_npm_user_prefix
  command_exists "$cli" || return 1
  "$cli" --version >/dev/null 2>&1
}

check_dependencies() {
  local missing=()
  command_exists curl || missing+=("curl")
  command_exists bash || missing+=("bash")
  if ((${#missing[@]})); then
    die "Missing dependencies: ${missing[*]}"
  fi
}

print_summary() {
  local tool="$1"
  local cli="$2"
  echo ""
  echo "=== Install summary (v${VERSION}) ==="
  echo "Tool: ${tool}"
  echo "Install source: ${LAST_INSTALL_SOURCE:-unknown}"
  if [[ "$tool" == "qwen" ]]; then
    echo "Config: ${HOME}/.qwen/settings.json"
    echo "Secrets: ${HOME}/.qwen/.env"
    echo "Verify: qwen --version"
    echo "Docs: https://qwenlm.github.io/qwen-code-docs/"
  else
    echo "Config: ${HOME}/.config/opencode/opencode.json"
    echo "Secrets: ${HOME}/.config/opencode/.env"
    echo "Verify: opencode --version"
    echo "Docs: https://dev.opencode.ai/docs/config/"
  fi
  echo "PATH hint: export PATH=\"${NPM_USER_PREFIX}/bin:\\$PATH\""
  echo "Done."
}

main() {
  local os arch
  read -r os arch <<< "$(detect_os_arch)"
  log "AI CLI Installer v${VERSION} (${os}/${arch})"

  check_dependencies
  ensure_npm_user_prefix

  echo ""
  echo "Network environment:"
  echo "  1) Domestic mirror (default)"
  echo "  2) Official source"
  echo "  3) Corporate (env overrides)"
  local net
  net="$(prompt_choice "Select" "1")"

  echo ""
  echo "Tool:"
  echo "  1) OpenCode"
  echo "  2) Qwen Code"
  local tool_choice
  tool_choice="$(prompt_choice "Select" "1")"

  local tool cli
  if [[ "$tool_choice" == "2" ]]; then
    tool="qwen"
    cli="qwen"
  else
    tool="opencode"
    cli="opencode"
  fi

  local skip_install=0
  if verify_cli "$cli"; then
    log "${cli} already installed."
    echo "  1) Reinstall"
    echo "  2) Config only"
    echo "  3) Exit"
    local act
    act="$(prompt_choice "Select" "2")"
    case "$act" in
      3) exit 0 ;;
      2) skip_install=1; LAST_INSTALL_SOURCE="skipped" ;;
      1) skip_install=0 ;;
      *) skip_install=1; LAST_INSTALL_SOURCE="skipped" ;;
    esac
  fi

  if [[ "$skip_install" -eq 0 ]]; then
    if [[ "$tool" == "qwen" ]]; then
      install_qwen "$net" || die "Qwen Code installation failed"
    else
      install_opencode "$net" || die "OpenCode installation failed"
    fi
    verify_cli "$cli" || die "${cli} not found in PATH after install"
  fi

  if [[ "$tool" == "qwen" ]]; then
    local ark_key bailian_key
    ark_key="$(read_secret "Volcengine Ark Coding API Key")"
    bailian_key="$(read_secret "Ali Bailian Coding API Key")"
    [[ -n "$ark_key" ]] || die "Ark API key empty"
    [[ -n "$bailian_key" ]] || die "Bailian API key empty"
    setup_qwen_config "$ark_key" "$bailian_key"
  else
    echo ""
    echo "Provider:"
    echo "  1) openai (default)"
    echo "  2) anthropic"
    echo "  3) dashscope"
    local p prov
    p="$(prompt_choice "Select" "1")"
    case "$p" in
      2) prov="anthropic" ;;
      3) prov="dashscope" ;;
      *) prov="openai" ;;
    esac
    local key
    key="$(read_secret "Enter API Key")"
    [[ -n "$key" ]] || die "API Key empty"
    setup_opencode_config "$key" "$prov"
  fi

  print_summary "$tool" "$cli"
}

main "$@"
