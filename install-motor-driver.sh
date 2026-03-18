#!/bin/bash
# =============================================================================
# install-motor-driver.sh
# Motor Driver Service — idempotent provisioning script
#
# Executed by HIVE as run-script on ROV devices (component: motor-driver).
# Safe to run multiple times: every step checks state before acting.
#
# Prerequisites:
#   - User: pi with passwordless sudo
#   - Internet access available
#   - /tmp/motor-driver.tar.gz already deployed by HIVE copy-file
#
# Exit codes:
#   0 — success (all steps completed or already in desired state)
#   1 — fatal error (logged to stderr and journal)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
TARBALL="/tmp/motor-driver.tar.gz"
INSTALL_DIR="/opt/motor-driver"
SERVICE_NAME="motor-driver"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
VENV_DIR="${INSTALL_DIR}/venv"
REQUIREMENTS="${INSTALL_DIR}/requirements.txt"

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log()  { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO]  $*"; }
warn() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN]  $*" >&2; }
die()  { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Step 0 — Preconditions
# -----------------------------------------------------------------------------
step0_preconditions() {
    log "=== Step 0: preconditions ==="

    [[ -f "$TARBALL" ]] \
        || die "Tarball not found at ${TARBALL}. Deploy it via HIVE copy-file first."

    sudo -n true 2>/dev/null \
        || die "Passwordless sudo not available for user $(whoami)."

    command -v python3 &>/dev/null \
        || die "python3 not found — install it before running this script."

    log "Preconditions OK."
}

# -----------------------------------------------------------------------------
# Step 1 — Extract tarball to /opt/motor-driver
# -----------------------------------------------------------------------------
step1_extract() {
    log "=== Step 1: extract tarball ==="

    sudo mkdir -p "$INSTALL_DIR"

    # Fix: directory must be world-traversable (755) so that User=pi
    # in the systemd unit can reach files inside it.
    local dir_mode
    dir_mode=$(stat -c '%a' "$INSTALL_DIR")
    if [[ "$dir_mode" != "755" ]]; then
        sudo chmod 755 "$INSTALL_DIR"
        log "Fixed ${INSTALL_DIR} permissions: ${dir_mode} → 755"
    fi

    log "Extracting ${TARBALL} → ${INSTALL_DIR}"
    # --strip-components=1 removes the top-level "motor_driver-1.0.0/" directory
    sudo tar -xzf "$TARBALL" -C "$INSTALL_DIR" --strip-components=1
    sudo chown -R pi:pi "$INSTALL_DIR"
    rm -f "$TARBALL"

    log "Extraction complete."
}

# -----------------------------------------------------------------------------
# Step 2 — Python venv + dependencies
# -----------------------------------------------------------------------------
step2_python_venv() {
    log "=== Step 2: Python venv + dependencies ==="

    [[ -f "$REQUIREMENTS" ]] \
        || die "requirements.txt not found at ${REQUIREMENTS} after extraction."

    # Create venv only if not already present
    if [[ ! -f "${VENV_DIR}/bin/python3" ]]; then
        log "Creating venv at ${VENV_DIR}"
        python3 -m venv "$VENV_DIR"
    else
        log "Venv already exists — skip creation"
    fi

    log "Installing/updating pip dependencies..."
    "${VENV_DIR}/bin/pip" install --quiet --upgrade pip
    "${VENV_DIR}/bin/pip" install --quiet -r "$REQUIREMENTS"
    log "Dependencies installed."
}

# -----------------------------------------------------------------------------
# Step 3 — Write systemd unit (idempotent via content comparison)
# -----------------------------------------------------------------------------
step3_systemd_unit() {
    log "=== Step 3: systemd unit ==="

    local desired_content
    desired_content=$(cat <<'EOF'
[Unit]
Description=Motor Driver ATV (mavlink_rover)
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/motor-driver
ExecStart=/opt/motor-driver/venv/bin/python3 /opt/motor-driver/mavlink_rover.py
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
)

    local needs_write=true
    if [[ -f "$SERVICE_FILE" ]]; then
        local current_content
        current_content=$(sudo cat "$SERVICE_FILE")
        if [[ "$current_content" == "$desired_content" ]]; then
            log "${SERVICE_FILE} already up to date — skip"
            needs_write=false
        fi
    fi

    if $needs_write; then
        printf '%s\n' "$desired_content" | sudo tee "$SERVICE_FILE" > /dev/null
        log "Written ${SERVICE_FILE}"
    fi
}

# -----------------------------------------------------------------------------
# Step 4 — Enable service (idempotent)
# -----------------------------------------------------------------------------
step4_enable_service() {
    log "=== Step 4: systemd enable ==="

    sudo systemctl daemon-reload

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        log "${SERVICE_NAME} already enabled — skip"
    else
        sudo systemctl enable "$SERVICE_NAME"
        log "${SERVICE_NAME} enabled."
    fi
}

# -----------------------------------------------------------------------------
# Step 5 — Start / restart service and verify
# -----------------------------------------------------------------------------
step5_start_and_verify() {
    log "=== Step 5: start + verify ==="

    sudo systemctl restart "$SERVICE_NAME"
    log "Restart signal sent — waiting 5s for service to stabilize..."
    sleep 5

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "${SERVICE_NAME} is active."
    else
        log "Service failed to start. Recent journal:"
        journalctl -u "$SERVICE_NAME" -n 20 --no-pager >&2 || true
        die "${SERVICE_NAME} is not active after restart."
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    log "=============================================="
    log "install-motor-driver.sh — start"
    log "Host: $(hostname)  User: $(whoami)  Date: $(date -u)"
    log "=============================================="

    step0_preconditions
    step1_extract
    step2_python_venv
    step3_systemd_unit
    step4_enable_service
    step5_start_and_verify

    log "=============================================="
    log "install-motor-driver.sh — completed OK"
    log "=============================================="
}

main "$@"