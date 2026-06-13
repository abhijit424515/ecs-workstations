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
# ---------------------------------------------------------------------------
if [ ! -d "${WORKSPACE}" ]; then
    echo "[entrypoint] Creating workspace directory..."
    sudo mkdir -p "${WORKSPACE}"
fi

echo "[entrypoint] Ensuring workspace ownership..."
sudo chown hermes:hermes "${WORKSPACE}"

# ---------------------------------------------------------------------------
# Setup Hermes SSH config
# ---------------------------------------------------------------------------
if [ -d "/home/hermes/.ssh" ]; then
    echo "[entrypoint] SSH config exists."
else
    mkdir -p /home/hermes/.ssh
    chmod 700 /home/hermes/.ssh
fi

# ---------------------------------------------------------------------------
# Validate Hermes config
# ---------------------------------------------------------------------------
if [ -z "${HERMES_TELEGRAM_TOKEN}" ] || [ "${HERMES_TELEGRAM_TOKEN}" = "your-bot-token-here" ]; then
    echo "[entrypoint] WARNING: HERMES_TELEGRAM_TOKEN is not set."
    echo "[entrypoint] The bot will not respond to Telegram messages until you set it."
    echo "[entrypoint] Set it in the ECS task definition environment, or run:"
    echo "[entrypoint]   hermes config set gateways.telegram.bot_token <token>"
fi

# ---------------------------------------------------------------------------
# Substitute env vars in Hermes config (${VAR} → actual values)
# ---------------------------------------------------------------------------
echo "[entrypoint] Substituting env vars in config..."
# Write .env file for Hermes (API keys + Telegram config)
if [ -n "${HERMES_TELEGRAM_TOKEN}" ] && [ -n "${DEEPSEEK_API_KEY}" ]; then
    cat > /home/hermes/.hermes/.env << EOF
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
TELEGRAM_BOT_TOKEN=${HERMES_TELEGRAM_TOKEN}
TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS:-}
EOF
fi
echo "[entrypoint] Substitution done"

# ---------------------------------------------------------------------------
# Start Hermes (runs forever — the Telegram gateway keeps the process alive)
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting Hermes gateway..."
exec hermes gateway run --accept-hooks
