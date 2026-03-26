# SETUP-SCRIPTS

This repository contains installation scripts for software deployed on Debian or Rocky Linux.
Services are installed under `/opt`, run under dedicated service users, and managed by systemd.

## Unsloth Studio One-Line Install

The Unsloth installer is self-contained and can be executed directly from a shell using curl.

```bash
curl -fsSL https://raw.githubusercontent.com/tpkreepur/setup-scripts/main/unsloth_studio/install.sh | sudo bash
```

## Optional Flags

```bash
# Recreate existing virtualenv
curl -fsSL https://raw.githubusercontent.com/tpkreepur/setup-scripts/main/unsloth_studio/install.sh | sudo bash -s -- --force

# Install runtime only (skip systemd service)
curl -fsSL https://raw.githubusercontent.com/tpkreepur/setup-scripts/main/unsloth_studio/install.sh | sudo bash -s -- --skip-service

# Use a custom path under /opt
curl -fsSL https://raw.githubusercontent.com/tpkreepur/setup-scripts/main/unsloth_studio/install.sh | sudo bash -s -- --install-dir /opt/unsloth-studio
```

## Post-Install Checks

```bash
systemctl status unsloth.service --no-pager
journalctl -u unsloth.service -n 100 --no-pager
```
