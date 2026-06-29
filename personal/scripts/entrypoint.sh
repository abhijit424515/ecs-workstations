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
# Note: ECS Exec needs no in-container SSM agent. The ECS container agent
# injects the SSM binaries from the host (/var/lib/ecs/deps/execute-command)
# at runtime; the task role carries the ssmmessages perms.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Homebrew — installed here (not in the image) because it lives at
# /home/linuxbrew, outside the persistent /home/hermes EBS mount, so it is
# wiped on every fresh container and must be reinstalled at start.
# ponytail: reinstalls each cold start; move to image if boot time matters.
# ---------------------------------------------------------------------------
if [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    echo "[entrypoint] Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Load brew into this shell + persist for interactive shells (~/.bashrc on EBS)
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
if ! grep -q 'brew shellenv' "${HOME}/.bashrc" 2>/dev/null; then
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "${HOME}/.bashrc"
fi

# ---------------------------------------------------------------------------
# Claude Code — installs to ~/.local/bin, which IS on the persistent EBS
# mount, so this runs once ever (guard skips it on subsequent starts).
# ---------------------------------------------------------------------------
if [ ! -x "${HOME}/.local/bin/claude" ]; then
    echo "[entrypoint] Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
fi
case ":${PATH}:" in *":${HOME}/.local/bin:"*) ;; *) export PATH="${HOME}/.local/bin:${PATH}";; esac

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
