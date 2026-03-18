# ── hive/teardown.sh ──────────────────────────────────────────────────────────
# Lives in the motor_driver repo at hive/teardown.sh
#
# HIVE injects all release vars as environment variables before execution:
#   HIVE_PARAM_INSTALL_DIR      → absolute installation path
#   HIVE_PARAM_SERVICE_USER     → system user owning the installation
#   HIVE_PARAM_PRIMARY_SERVICE  → primary systemd service name
#
# NOTE: gstreamer is managed by its own component — do NOT remove it here.
#!/bin/bash
set -euo pipefail

# 1. Stop and disable services
sudo systemctl stop "$HIVE_PARAM_PRIMARY_SERVICE" qgc-video-stream || true
sudo systemctl disable "$HIVE_PARAM_PRIMARY_SERVICE" qgc-video-stream || true

# 2. Remove systemd unit files
sudo rm -f \
  /etc/systemd/system/"$HIVE_PARAM_PRIMARY_SERVICE".service \
  /etc/systemd/system/qgc-video-stream.service

# 3. Remove tmpfiles.d entry for QGC PID file
sudo rm -f /etc/tmpfiles.d/qgc-video-stream.conf

# 4. Remove log file
sudo rm -f /var/log/qgc-video-stream.log

# 5. Reload systemd
sudo systemctl daemon-reload

# 6. Remove installation directory
sudo rm -rf "$HIVE_PARAM_INSTALL_DIR"

echo "teardown.sh completed successfully"