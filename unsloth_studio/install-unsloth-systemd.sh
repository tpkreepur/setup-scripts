#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ $# -ne 6 ]]; then
    echo "Usage: $0 <template_file> <unit_file> <service_name> <unsloth_user> <unsloth_dir> <venv_dir>" >&2
    exit 1
fi

template_file="$1"
unit_file="$2"
service_name="$3"
unsloth_user="$4"
unsloth_dir="$5"
venv_dir="$6"

if [[ ! -f "${template_file}" ]]; then
    echo "Template file not found: ${template_file}" >&2
    exit 1
fi

sed \
    -e "s|__UNSLOTH_USER__|${unsloth_user}|g" \
    -e "s|__UNSLOTH_DIR__|${unsloth_dir}|g" \
    -e "s|__VENV_DIR__|${venv_dir}|g" \
    "${template_file}" > "${unit_file}"

chmod 644 "${unit_file}"
systemctl daemon-reload
systemctl enable "${service_name}"
systemctl start "${service_name}"

if ! systemctl is-active --quiet "${service_name}"; then
    echo "Systemd service '${service_name}' failed to start. Review: systemctl status ${service_name}" >&2
    exit 1
fi
