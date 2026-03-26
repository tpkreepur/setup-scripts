#!/usr/bin/env bash

# ==============================================================================
# Title:           setup_unsloth.sh
# Description:     Enterprise-grade setup for Unsloth ML environment.
# Author:          DevOps Engineering
# Date:            2026-03-26
# Usage:           sudo ./setup_unsloth.sh [--force] [--service]
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Configuration & Constants ---
readonly UNSLOTH_USER="unsloth"
readonly UNSLOTH_DIR="/opt/unsloth"
readonly VENV_DIR="${UNSLOTH_DIR}/venv"
readonly PYTHON_BIN="python3.12"
readonly LOG_FILE="/var/log/unsloth_setup.log"
readonly UNIT_FILE="/etc/systemd/system/unsloth.service"
readonly SERVICE_NAME="unsloth.service"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DEPENDENCY_INSTALL_SCRIPT="${SCRIPT_DIR}/install-unsloth-dependencies.sh"
readonly VENV_PROVISION_SCRIPT="${SCRIPT_DIR}/provision-unsloth-venv.sh"
readonly SYSTEMD_INSTALL_SCRIPT="${SCRIPT_DIR}/install-unsloth-systemd.sh"
readonly SYSTEMD_TEMPLATE_FILE="${SCRIPT_DIR}/unsloth.service.template"

# --- State Variables ---
FORCE_INSTALL=false
CREATE_SERVICE=false

# --- Logging Infrastructure ---
log_info()  { printf "[%(%Y-%m-%dT%H:%M:%S%z)T] [INFO]  %s\n" -1 "$*" | tee -a "$LOG_FILE"; }
log_warn()  { printf "[%(%Y-%m-%dT%H:%M:%S%z)T] [WARN]  %s\n" -1 "$*" | tee -a "$LOG_FILE" >&2; }
log_error() { printf "[%(%Y-%m-%dT%H:%M:%S%z)T] [ERROR] %s\n" -1 "$*" | tee -a "$LOG_FILE" >&2; }

# --- Cleanup & Traps ---
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code ${exit_code}. Check ${LOG_FILE} for details."
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# --- Functions ---

usage() {
    local exit_code="${1:-1}"
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    -f, --force      Force re-installation of system packages.
    -s, --service    Generate and enable a systemd service unit.
    -h, --help       Display this help message.

Description:
    Provision a hardened environment for Unsloth using a dedicated system user.
    Must be run as root.
EOF
    exit "${exit_code}"
}

check_privileges() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root (or via sudo)."
        exit 1
    fi
}

install_dependencies() {
    log_info "Updating system and installing dependencies..."

    if [[ ! -x "${DEPENDENCY_INSTALL_SCRIPT}" ]]; then
        log_error "Dependency install helper is missing or not executable: ${DEPENDENCY_INSTALL_SCRIPT}"
        exit 1
    fi

    "${DEPENDENCY_INSTALL_SCRIPT}" "${FORCE_INSTALL}" "${PYTHON_BIN}"
}

validate_python() {
    if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
        log_error "Required Python binary '${PYTHON_BIN}' is not installed or not in PATH."
        exit 1
    fi
}

setup_user() {
    log_info "Configuring system user: ${UNSLOTH_USER}"

    if ! id -u "${UNSLOTH_USER}" >/dev/null 2>&1; then
        useradd -r -m -d "${UNSLOTH_DIR}" -s /sbin/nologin "${UNSLOTH_USER}"
        log_info "User ${UNSLOTH_USER} created."
    else
        log_info "User ${UNSLOTH_USER} already exists."
    fi

    mkdir -p "${UNSLOTH_DIR}"
    chown "${UNSLOTH_USER}:${UNSLOTH_USER}" "${UNSLOTH_DIR}"
    chmod 750 "${UNSLOTH_DIR}"
}

provision_venv() {
    log_info "Provisioning Python virtual environment in ${VENV_DIR}..."

    if [[ ! -x "${VENV_PROVISION_SCRIPT}" ]]; then
        log_error "Venv provision helper is missing or not executable: ${VENV_PROVISION_SCRIPT}"
        exit 1
    fi

    "${VENV_PROVISION_SCRIPT}" "${UNSLOTH_USER}" "${UNSLOTH_DIR}" "${VENV_DIR}" "${PYTHON_BIN}"
}

generate_systemd_unit() {
    log_info "Generating systemd unit file at ${UNIT_FILE}..."

    if [[ ! -x "${SYSTEMD_INSTALL_SCRIPT}" ]]; then
        log_error "Systemd install helper is missing or not executable: ${SYSTEMD_INSTALL_SCRIPT}"
        exit 1
    fi

    if [[ ! -f "${SYSTEMD_TEMPLATE_FILE}" ]]; then
        log_error "Systemd template file not found: ${SYSTEMD_TEMPLATE_FILE}"
        exit 1
    fi

    "${SYSTEMD_INSTALL_SCRIPT}" \
        "${SYSTEMD_TEMPLATE_FILE}" \
        "${UNIT_FILE}" \
        "${SERVICE_NAME}" \
        "${UNSLOTH_USER}" \
        "${UNSLOTH_DIR}" \
        "${VENV_DIR}"

    log_info "Systemd service 'unsloth' has been created, enabled, and started."
}

# --- Main Logic ---

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)   FORCE_INSTALL=true; shift ;;
            -s|--service) CREATE_SERVICE=true; shift ;;
            -h|--help)    usage 0 ;;
            *) log_error "Unknown option: $1"; usage ;;
        esac
    done

    check_privileges
    if [[ ! -e "$LOG_FILE" ]]; then
        install -m 640 -o root -g root /dev/null "$LOG_FILE"
    else
        chmod 640 "$LOG_FILE"
    fi

    install_dependencies
    validate_python
    setup_user
    provision_venv

    if [[ "${CREATE_SERVICE}" == "true" ]]; then
        generate_systemd_unit
    fi

    log_info "Unsloth Studio environment successfully configured."
}

main "$@"