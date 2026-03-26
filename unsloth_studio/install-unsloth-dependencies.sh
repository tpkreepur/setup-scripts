#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <force_install:true|false> <python_bin>" >&2
    exit 1
fi

force_install="$1"
python_bin="$2"

if [[ ! -f /etc/os-release ]]; then
    echo "Cannot detect operating system: /etc/os-release not found." >&2
    exit 1
fi

# shellcheck source=/dev/null
source /etc/os-release

if command -v dnf >/dev/null 2>&1; then
    pkgs=("${python_bin}" "${python_bin}-pip" "git" "sudo")
    if [[ "${force_install}" == "true" ]]; then
        dnf update -y
    fi
    dnf install -y "${pkgs[@]}"
elif command -v yum >/dev/null 2>&1; then
    pkgs=("${python_bin}" "${python_bin}-pip" "git" "sudo")
    if [[ "${force_install}" == "true" ]]; then
        yum update -y
    fi
    yum install -y "${pkgs[@]}"
elif command -v apt-get >/dev/null 2>&1; then
    pkgs=("${python_bin}" "${python_bin}-venv" "python3-pip" "git" "sudo")
    apt-get update -y
    if [[ "${force_install}" == "true" ]]; then
        apt-get upgrade -y
    fi
    apt-get install -y "${pkgs[@]}"
else
    echo "Unsupported Linux distribution: no supported package manager found for ${ID:-unknown}." >&2
    exit 1
fi
