#!/usr/bin/env bash

# ==============================================================================
# Title:           install.sh
# Description:     Self-contained installer for Unsloth Studio on Linux.
# Usage:           curl -fsSL <url>/install.sh | sudo bash
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

readonly DEFAULT_INSTALL_DIR="/home/unsloth"
readonly DEFAULT_SERVICE_NAME="unsloth.service"
readonly DEFAULT_SERVICE_USER="unsloth"
readonly DEFAULT_LOG_FILE="/var/log/unsloth_install.log"

INSTALL_DIR="${DEFAULT_INSTALL_DIR}"
SERVICE_NAME="${DEFAULT_SERVICE_NAME}"
SERVICE_USER="${DEFAULT_SERVICE_USER}"
LOG_FILE="${DEFAULT_LOG_FILE}"
FORCE_REINSTALL=false
SKIP_SERVICE=false
RUN_UPGRADE=false

PYTHON_BIN=""
PYTHON_PKG=""
PKG_MGR=""
NOLOGIN_SHELL=""

log_info()  { printf "[%(%Y-%m-%dT%H:%M:%S%z)T] [INFO]  %s\n" -1 "$*" | tee -a "$LOG_FILE"; }
log_warn()  { printf "[%(%Y-%m-%dT%H:%M:%S%z)T] [WARN]  %s\n" -1 "$*" | tee -a "$LOG_FILE" >&2; }
log_error() { printf "[%(%Y-%m-%dT%H:%M:%S%z)T] [ERROR] %s\n" -1 "$*" | tee -a "$LOG_FILE" >&2; }

usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS]

Install Unsloth Studio in /opt and configure systemd service.

Options:
  --install-dir <path>   Install root directory (default: /opt/unsloth)
  --service-name <name>  Systemd service name (default: unsloth.service)
  --service-user <name>  System user to run service (default: unsloth)
  --skip-service         Install runtime only, do not configure systemd
  --force                Recreate existing virtual environment
  --upgrade              Run OS package upgrade/update before install
  -h, --help             Show help and exit

Examples:
  curl -fsSL https://example.com/install.sh | sudo bash
  curl -fsSL https://example.com/install.sh | sudo bash -s -- --force
EOF
}

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Installer failed with exit code ${exit_code}."
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install-dir)
                INSTALL_DIR="${2:-}"
                shift 2
                ;;
            --service-name)
                SERVICE_NAME="${2:-}"
                shift 2
                ;;
            --service-user)
                SERVICE_USER="${2:-}"
                shift 2
                ;;
            --skip-service)
                SKIP_SERVICE=true
                shift
                ;;
            --force)
                FORCE_REINSTALL=true
                shift
                ;;
            --upgrade)
                RUN_UPGRADE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$INSTALL_DIR" || "$INSTALL_DIR" != /opt/* ]]; then
        log_error "--install-dir must be under /opt (received: ${INSTALL_DIR:-<empty>})."
        exit 1
    fi

    if [[ "$SERVICE_NAME" != *.service ]]; then
        SERVICE_NAME="${SERVICE_NAME}.service"
    fi
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        printf "This installer must run as root (use sudo).\n" >&2
        exit 1
    fi
}

init_logging() {
    install -d -m 755 /var/log
    if [[ ! -e "$LOG_FILE" ]]; then
        install -m 640 -o root -g root /dev/null "$LOG_FILE"
    else
        chmod 640 "$LOG_FILE"
    fi
}

detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MGR="yum"
    else
        log_error "Unsupported Linux distribution: apt, dnf, or yum is required."
        exit 1
    fi
}

detect_nologin_shell() {
    for shell_path in /usr/sbin/nologin /sbin/nologin /usr/bin/nologin /bin/false; do
        if [[ -x "$shell_path" ]]; then
            NOLOGIN_SHELL="$shell_path"
            return
        fi
    done
    log_error "No suitable nologin shell found."
    exit 1
}

detect_python_bin() {
    local candidate
    for candidate in python3.12 python3.11 python3.10; do
        if command -v "$candidate" >/dev/null 2>&1; then
            PYTHON_BIN="$candidate"
            PYTHON_PKG="$candidate"
            log_info "Detected existing Python runtime: ${PYTHON_BIN}"
            return
        fi
    done
}

install_base_dependencies() {
    log_info "Installing base dependencies (git, sudo, venv tooling)..."

    case "$PKG_MGR" in
        apt)
            apt-get update -y
            if [[ "$RUN_UPGRADE" == "true" ]]; then
                apt-get upgrade -y
            fi
            apt-get install -y ca-certificates curl git sudo
            ;;
        dnf)
            if [[ "$RUN_UPGRADE" == "true" ]]; then
                dnf update -y
            fi
            dnf install -y ca-certificates curl git sudo
            ;;
        yum)
            if [[ "$RUN_UPGRADE" == "true" ]]; then
                yum update -y
            fi
            yum install -y ca-certificates curl git sudo
            ;;
    esac
}

ensure_python_installed() {
    if [[ -n "$PYTHON_BIN" ]]; then
        case "$PKG_MGR" in
            apt)
                apt-get install -y "${PYTHON_PKG}-venv" python3-pip || true
                ;;
            dnf|yum)
                "$PKG_MGR" install -y "${PYTHON_PKG}-pip" || true
                ;;
        esac
        return
    fi

    log_info "No supported Python found; attempting installation (3.12 -> 3.11 -> 3.10)."

    local candidate
    for candidate in python3.12 python3.11 python3.10; do
        case "$PKG_MGR" in
            apt)
                if apt-get install -y "$candidate" "${candidate}-venv" python3-pip >/dev/null 2>&1; then
                    PYTHON_BIN="$candidate"
                    PYTHON_PKG="$candidate"
                    break
                fi
                ;;
            dnf|yum)
                if "$PKG_MGR" install -y "$candidate" "${candidate}-pip" >/dev/null 2>&1; then
                    PYTHON_BIN="$candidate"
                    PYTHON_PKG="$candidate"
                    break
                fi
                ;;
        esac
    done

    if [[ -z "$PYTHON_BIN" ]]; then
        log_error "Unable to install python3.12, python3.11, or python3.10."
        exit 1
    fi

    log_info "Installed Python runtime: ${PYTHON_BIN}"
}

ensure_python_venv_support() {
    if ! "$PYTHON_BIN" -m venv --help >/dev/null 2>&1; then
        log_error "${PYTHON_BIN} is missing venv support."
        exit 1
    fi
}

setup_service_user() {
    if id -u "$SERVICE_USER" >/dev/null 2>&1; then
        log_info "Service user ${SERVICE_USER} already exists."
    else
        log_info "Creating service user ${SERVICE_USER}."
        useradd -r -m -d "$INSTALL_DIR" -s "$NOLOGIN_SHELL" "$SERVICE_USER"
    fi

    install -d -m 750 -o "$SERVICE_USER" -g "$SERVICE_USER" "$INSTALL_DIR"
}

run_as_service_user() {
    local cmd="$1"
    # UV_NO_CONFIG=1 prevents uv from reading config files outside the install
    # directory (e.g. /home/<invoking-user>/uv.toml) which the service user
    # cannot read, causing a Permission denied error.
    local extra_env="HOME='$INSTALL_DIR' UV_NO_CONFIG=1 XDG_CONFIG_HOME='$INSTALL_DIR/.config'"

    if command -v sudo >/dev/null 2>&1; then
        sudo -H -u "$SERVICE_USER" env \
            HOME="$INSTALL_DIR" \
            UV_NO_CONFIG=1 \
            XDG_CONFIG_HOME="$INSTALL_DIR/.config" \
            bash -c "$cmd"
    elif command -v runuser >/dev/null 2>&1; then
        runuser -u "$SERVICE_USER" -- env \
            HOME="$INSTALL_DIR" \
            UV_NO_CONFIG=1 \
            XDG_CONFIG_HOME="$INSTALL_DIR/.config" \
            bash -c "$cmd"
    else
        su -s /bin/bash "$SERVICE_USER" -c "$extra_env $cmd"
    fi
}

provision_virtualenv() {
    local venv_dir="${INSTALL_DIR}/venv"

    if [[ "$FORCE_REINSTALL" == "true" && -d "$venv_dir" ]]; then
        log_warn "--force specified, removing existing virtual environment."
        rm -rf "$venv_dir"
    fi

    if [[ ! -d "$venv_dir" ]]; then
        log_info "Creating virtual environment at ${venv_dir}."
        run_as_service_user "'$PYTHON_BIN' -m venv '$venv_dir'"
    fi

    if [[ ! -x "${venv_dir}/bin/python" ]]; then
        log_error "Virtual environment is invalid: ${venv_dir}"
        exit 1
    fi

    log_info "Installing Unsloth Python dependencies in virtual environment."
    # VIRTUAL_ENV must be set so that `uv pip install` knows which environment
    # to target; without it uv errors with "No virtual environment found".
    run_as_service_user "VIRTUAL_ENV='$venv_dir' '$venv_dir/bin/python' -m pip install --upgrade pip uv && VIRTUAL_ENV='$venv_dir' '$venv_dir/bin/uv' pip install unsloth"
}

systemd_available() {
    command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

install_systemd_unit() {
    local unit_file="/etc/systemd/system/${SERVICE_NAME}"
    local venv_dir="${INSTALL_DIR}/venv"

    if [[ "$SKIP_SERVICE" == "true" ]]; then
        log_warn "Skipping systemd configuration because --skip-service was provided."
        return
    fi

    if ! systemd_available; then
        log_error "systemd is not available on this host; use --skip-service to install runtime only."
        exit 1
    fi

    log_info "Installing systemd unit: ${SERVICE_NAME}"
    cat > "$unit_file" <<EOF
[Unit]
Description=Unsloth ML Studio Service
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${venv_dir}/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=${venv_dir}/bin/python -m unsloth
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$unit_file"
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log_error "Service failed to start: ${SERVICE_NAME}."
        log_error "Inspect with: systemctl status ${SERVICE_NAME} --no-pager"
        log_error "Inspect logs with: journalctl -u ${SERVICE_NAME} -n 100 --no-pager"
        exit 1
    fi

    log_info "Service is active: ${SERVICE_NAME}"
}

print_summary() {
    local venv_dir="${INSTALL_DIR}/venv"

    cat <<EOF

Installation complete.

Install directory : ${INSTALL_DIR}
Service user      : ${SERVICE_USER}
Python binary     : ${PYTHON_BIN}
Virtualenv        : ${venv_dir}
Log file          : ${LOG_FILE}
EOF

    if [[ "$SKIP_SERVICE" == "false" ]]; then
        cat <<EOF
Service name      : ${SERVICE_NAME}

Verify service:
  systemctl status ${SERVICE_NAME} --no-pager
  journalctl -u ${SERVICE_NAME} -f
EOF
    fi

    cat <<EOF

Manual runtime check:
  sudo -u ${SERVICE_USER} ${venv_dir}/bin/python -m unsloth
EOF
}

main() {
    parse_args "$@"
    require_root
    init_logging

    log_info "Starting Unsloth installer (self-contained bootstrap mode)."

    detect_pkg_manager
    detect_nologin_shell
    detect_python_bin

    install_base_dependencies
    ensure_python_installed
    ensure_python_venv_support
    setup_service_user
    provision_virtualenv
    install_systemd_unit
    print_summary

    log_info "Unsloth installation completed successfully."
}

main "$@"
