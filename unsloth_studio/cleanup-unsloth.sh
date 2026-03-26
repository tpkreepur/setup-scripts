#!/usr/bin/env bash

# ==============================================================================
# Title:           cleanup_unsloth.sh
# Description:     Complete removal of Unsloth environment and artifacts.
# Author:          DevOps Engineering
# Date:            2026-03-26
# Usage:           sudo ./cleanup_unsloth.sh [--purge-logs]
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Configuration ---
readonly UNSLOTH_USER="unsloth"
readonly UNSLOTH_GROUP="unsloth"
readonly UNSLOTH_DIR="/opt/unsloth"
readonly LOG_FILE="/var/log/unsloth_setup.log"
readonly UNIT_FILE="/etc/systemd/system/unsloth.service"

# --- State ---
PURGE_LOGS=false

# --- Logging ---
log_info()  { printf "[%(%Y-%m-%dT%H:%M:%S%z)T] [INFO]  %s\n" -1 "$*"; }
log_warn()  { printf "[%(%Y-%m-%dT%H:%M:%S%z)T] [WARN]  %s\n" -1 "$*" >&2; }
log_error() { printf "[%(%Y-%m-%dT%H:%M:%S%z)T] [ERROR] %s\n" -1 "$*" >&2; }

check_privileges() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root."
        exit 1
    fi
}

remove_service() {
    if systemctl list-unit-files | grep -q "unsloth.service"; then
        log_info "Stopping and disabling unsloth service..."
        systemctl stop unsloth.service || log_warn "Failed to stop service."
        systemctl disable unsloth.service
        rm -f "$UNIT_FILE"
        systemctl daemon-reload
        systemctl reset-failed
    fi
}

clear_group_members() {
    if getent group "${UNSLOTH_GROUP}" >/dev/null; then
        log_info "Clearing all members from group: ${UNSLOTH_GROUP}"
        
        # Get comma-separated list of members and convert to space-separated array
        local members
        members=$(getent group "${UNSLOTH_GROUP}" | cut -d: -f4 | tr ',' ' ')
        
        for user in ${members}; do
            log_info "Removing user '${user}' from group '${UNSLOTH_GROUP}'"
            gpasswd -d "${user}" "${UNSLOTH_GROUP}" || log_warn "Could not remove ${user} from ${UNSLOTH_GROUP}"
        done
    fi
}

remove_user_and_group() {
    # Remove the specific service user
    if id "$UNSLOTH_USER" &>/dev/null; then
        log_info "Removing system user: ${UNSLOTH_USER}"
        userdel "$UNSLOTH_USER" || log_warn "Userdel failed (process might be active)."
    fi

    # Clear other members then remove the group itself
    clear_group_members
    
    if getent group "${UNSLOTH_GROUP}" >/dev/null; then
        log_info "Deleting group: ${UNSLOTH_GROUP}"
        groupdel "${UNSLOTH_GROUP}" || log_warn "Could not delete group (might be a user's primary group)."
    fi
}

remove_artifacts() {
    log_info "Removing installation directory: ${UNSLOTH_DIR}"
    if [[ -d "$UNSLOTH_DIR" ]]; then
        if [[ "$UNSLOTH_DIR" == "/" || "$UNSLOTH_DIR" == "/home"* ]]; then
            log_error "Safety check triggered: Refusing to delete ${UNSLOTH_DIR}"
            exit 1
        fi
        rm -rf "$UNSLOTH_DIR"
    fi

    if [[ "$PURGE_LOGS" == "true" ]]; then
        log_info "Purging log file: ${LOG_FILE}"
        rm -f "$LOG_FILE"
    fi
}

# --- Main ---
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --purge-logs) PURGE_LOGS=true; shift ;;
            *) echo "Usage: $0 [--purge-logs]"; exit 1 ;;
        esac
    done

    check_privileges
    log_warn "Starting full Unsloth cleanup..."

    remove_service
    remove_artifacts
    remove_user_and_group

    log_info "Cleanup complete."
}

main "$@"