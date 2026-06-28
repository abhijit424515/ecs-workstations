#!/bin/bash
# =============================================================================
# Personal Remote Workstation — Entrypoint
# =============================================================================
# - Sets up the workspace (chown)
# - Starts Hermes with the Telegram gateway
# =============================================================================

set -e

WORKSPACE="/workspace"

echo "[entrypoint] === Personal Remote Workstation ==="

# ---------------------------------------------------------------------------
# Ensure workspace is writable
# ---------------------------------------------------------------------------
if [ ! -d "${WORKSPACE}" ]; then
    echo "[entrypoint] Creating workspace directory..."
    sudo mkdir -p "${WORKSPACE}"
fi

echo "[entrypoint] Ensuring workspace ownership..."
sudo chown hermes:hermes "${WORKSPACE}"

# ---------------------------------------------------------------------------
# Start SSM agent for ECS Exec
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting SSM agent..."
if [ -f /usr/bin/amazon-ssm-agent ] || [ -f /opt/amazon/ssm/bin/amazon-ssm-agent ]; then
    sudo service amazon-ssm-agent start 2>/dev/null || sudo /usr/bin/amazon-ssm-agent -register -code "${AWS_SSM_ACTIVATION_CODE:-}" -id "${AWS_SSM_ACTIVATION_ID:-}" -region "${AWS_DEFAULT_REGION:-ap-south-1}" &
else
    echo "[entrypoint] Warning: SSM agent not found"
fi

# ---------------------------------------------------------------------------
# Validate that secrets exist on EBS (pre-written by build script)
# ---------------------------------------------------------------------------
if [ ! -f "/home/hermes/.hermes/.env" ]; then
    echo "[entrypoint] WARNING: /home/hermes/.hermes/.env not found."
    echo "[entrypoint] Run ./build-and-deploy.sh to write secrets to EBS."
fi

# ---------------------------------------------------------------------------
# Start Hermes (runs forever — the Telegram gateway keeps the process alive)
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting Hermes gateway..."
exec hermes gateway run --accept-hooks
