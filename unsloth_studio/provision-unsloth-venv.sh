#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 <unsloth_user> <unsloth_dir> <venv_dir> <python_bin>" >&2
    exit 1
fi

unsloth_user="$1"
unsloth_dir="$2"
venv_dir="$3"
python_bin="$4"

sudo -H -u "${unsloth_user}" env HOME="${unsloth_dir}" bash -s -- "${venv_dir}" "${python_bin}" "${unsloth_dir}" <<'EOF'
set -euo pipefail

venv_dir="$1"
python_bin="$2"
unsloth_dir="$3"

cd "${unsloth_dir}"

if [[ -d "${venv_dir}" ]]; then
    if [[ ! -x "${venv_dir}/bin/python" ]]; then
        echo "Existing virtual environment is invalid: ${venv_dir}" >&2
        exit 1
    fi
else
    "${python_bin}" -m venv "${venv_dir}"
fi

"${venv_dir}/bin/python" -m pip install --upgrade pip uv
# Intentionally unpinned per user preference: always install latest unsloth.
"${venv_dir}/bin/uv" pip install unsloth
EOF
