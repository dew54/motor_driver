#!/bin/bash
# =============================================================================
# install-qgc-streamer.sh
# QGC Video Streaming Service — idempotent provisioning script
#
# Executed by HIVE as run-script on ROV devices (component: qgc-streamer).
# Safe to run multiple times: every step checks state before acting.
#
# Prerequisites:
#   - User: pi with passwordless sudo
#   - Internet access available
#   - /opt/motor-driver/qgc-video-stream.sh already deployed by HIVE copy-file
#
# Exit codes:
#   0 — success (all steps completed or already in desired state)
#   1 — fatal error (logged to stderr and journal)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
INSTALL_DIR="/opt/motor-driver"
SCRIPT_PATH="${INSTALL_DIR}/qgc-video-stream.sh"
SERVICE_NAME="qgc-video-stream"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOG_FILE="/var/log/qgc-video-stream.log"
TMPFILES_CONF="/etc/tmpfiles.d/qgc-video-stream.conf"
BROKEN_PLUGIN="/usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstv4l2codecs.so"

GSTREAMER_PACKAGES=(
    gstreamer1.0-tools
    gstreamer1.0-plugins-good
    gstreamer1.0-plugins-bad
    gstreamer1.0-plugins-ugly
)

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

    # Script must already be deployed by HIVE copy-file before this runs
    [[ -f "$SCRIPT_PATH" ]] || die "Script not found at ${SCRIPT_PATH}. Deploy it via HIVE copy-file first."

    # Verify sudo is available without password
    sudo -n true 2>/dev/null || die "Passwordless sudo not available for user $(whoami)."

    log "Preconditions OK."
}

# -----------------------------------------------------------------------------
# Step 1 — Ensure install dir and script permissions
# -----------------------------------------------------------------------------
step1_script_permissions() {
    log "=== Step 1: install dir + script permissions ==="

    # Create install dir if missing
    sudo mkdir -p "$INSTALL_DIR"

    # Fix: directory must be world-traversable (755) so that User=pi in the
    # systemd unit can reach the script. If the directory is 700 root:root,
    # systemd gets exit 126 before the script even starts.
    local dir_mode
    dir_mode=$(stat -c '%a' "$INSTALL_DIR")
    if [[ "$dir_mode" != "755" ]]; then
        sudo chmod 755 "$INSTALL_DIR"
        log "Fixed ${INSTALL_DIR} permissions: ${dir_mode} → 755"
    else
        log "${INSTALL_DIR} permissions OK (755) — skip"
    fi

    # Fix: use explicit 755 instead of +x to avoid partial permission states
    # (e.g. 711 root:root which blocks tee/log calls inside the script
    # when running as User=pi)
    local script_mode
    script_mode=$(stat -c '%a' "$SCRIPT_PATH")
    if [[ "$script_mode" != "755" ]]; then
        sudo chmod 755 "$SCRIPT_PATH"
        log "Fixed ${SCRIPT_PATH} permissions: ${script_mode} → 755"
    else
        log "${SCRIPT_PATH} permissions OK (755) — skip"
    fi

    # Validate the script is parseable before we go any further
    bash -n "$SCRIPT_PATH" || die "Syntax error in ${SCRIPT_PATH} — aborting before any system changes."
    log "Script syntax OK."
}

# -----------------------------------------------------------------------------
# Step 2 — Fix interrupted dpkg state
# -----------------------------------------------------------------------------
step2_dpkg_repair() {
    log "=== Step 2: dpkg repair ==="

    # Only run if there are packages in an inconsistent state
    if dpkg --audit 2>/dev/null | grep -q .; then
        log "Inconsistent dpkg state detected — running --configure -a"
        sudo dpkg --configure -a
    else
        log "dpkg state clean — skip"
    fi
}

# -----------------------------------------------------------------------------
# Step 3 — Install GStreamer packages
# -----------------------------------------------------------------------------
step3_install_gstreamer() {
    log "=== Step 3: GStreamer installation ==="

    # Build list of packages not yet installed
    local missing=()
    for pkg in "${GSTREAMER_PACKAGES[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log "All GStreamer packages already installed — skip"
        return
    fi

    log "Installing missing packages: ${missing[*]}"
    sudo apt-get install -y --no-install-recommends "${missing[@]}"
    log "GStreamer installation complete."
}

# -----------------------------------------------------------------------------
# Step 4 — Remove broken v4l2codecs plugin (segfaults on arm64)
# -----------------------------------------------------------------------------
step4_remove_broken_plugin() {
    log "=== Step 4: broken plugin removal ==="

    if [[ -f "$BROKEN_PLUGIN" ]]; then
        sudo rm -f "$BROKEN_PLUGIN"
        log "Removed broken plugin: ${BROKEN_PLUGIN}"
    else
        log "Broken plugin not present — skip"
    fi
}

# -----------------------------------------------------------------------------
# Step 5 — Runtime file permissions and tmpfiles.d
# -----------------------------------------------------------------------------
step5_runtime_permissions() {
    log "=== Step 5: runtime file permissions ==="

    # Log file — create and assign to pi if missing or wrong owner
    if [[ ! -f "$LOG_FILE" ]]; then
        sudo touch "$LOG_FILE"
        log "Created ${LOG_FILE}"
    fi
    local log_owner
    log_owner=$(stat -c '%U' "$LOG_FILE")
    if [[ "$log_owner" != "pi" ]]; then
        sudo chown pi:pi "$LOG_FILE"
        log "Ownership of ${LOG_FILE} set to pi:pi"
    else
        log "${LOG_FILE} already owned by pi — skip"
    fi

    # tmpfiles.d entry — ensures PID file directory entry is recreated at boot
    local tmpfiles_line="f /var/run/qgc-video-stream.pid 0644 pi pi -"
    if [[ ! -f "$TMPFILES_CONF" ]] || ! grep -qF "$tmpfiles_line" "$TMPFILES_CONF"; then
        printf '%s\n' "$tmpfiles_line" | sudo tee "$TMPFILES_CONF" > /dev/null
        sudo systemd-tmpfiles --create "$TMPFILES_CONF"
        log "tmpfiles.d entry written and applied."
    else
        log "tmpfiles.d entry already present — skip"
    fi
}

# -----------------------------------------------------------------------------
# Step 6 — Write systemd unit (idempotent via checksum)
# -----------------------------------------------------------------------------
step6_systemd_unit() {
    log "=== Step 6: systemd unit ==="

    # Define the desired unit content
    local desired_content
    desired_content=$(cat <<'EOF'
[Unit]
Description=QGC Video Stream
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/motor-driver
ExecStart=/opt/motor-driver/qgc-video-stream.sh
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
)

    # Compare with existing file — only write if content differs
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
# Step 7 — Enable service (idempotent)
# -----------------------------------------------------------------------------
step7_enable_service() {
    log "=== Step 7: systemd enable ==="

    sudo systemctl daemon-reload

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        log "${SERVICE_NAME} already enabled — skip"
    else
        sudo systemctl enable "$SERVICE_NAME"
        log "${SERVICE_NAME} enabled."
    fi
}

# -----------------------------------------------------------------------------
# Step 8 — Start / restart service and verify
# -----------------------------------------------------------------------------
step8_start_and_verify() {
    log "=== Step 8: start + verify ==="

    sudo systemctl restart "$SERVICE_NAME"
    log "Restart signal sent — waiting 5s for service to stabilize..."
    sleep 5

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "${SERVICE_NAME} is active."
    else
        # Dump recent journal for HIVE lastError visibility
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
    log "install-qgc-streamer.sh — start"
    log "Host: $(hostname)  User: $(whoami)  Date: $(date -u)"
    log "=============================================="

    step0_preconditions
    step1_script_permissions
    step2_dpkg_repair
    step3_install_gstreamer
    step4_remove_broken_plugin
    step5_runtime_permissions
    step6_systemd_unit
    step7_enable_service
    step8_start_and_verify

    log "=============================================="
    log "install-qgc-streamer.sh — completed OK"
    log "=============================================="
}

main "$@"