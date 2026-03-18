# ── hive/install.sh ───────────────────────────────────────────────────────────
# Lives in the motor_driver repo at hive/install.sh
# GStreamer is NOT installed here — it is managed by the gstreamer component.
#
# HIVE injects all release vars as environment variables before execution:
#   HIVE_RES_SERVICE_ARCHIVE    → local path of downloaded source tarball
#   HIVE_PARAM_INSTALL_DIR      → absolute installation path
#   HIVE_PARAM_SERVICE_USER     → system user owning the installation
#   HIVE_PARAM_PRIMARY_SERVICE  → primary systemd service name
#!/bin/bash
set -euo pipefail

# 1. Extract source archive
sudo mkdir -p "$HIVE_PARAM_INSTALL_DIR"
sudo tar -xzf "$HIVE_RES_SERVICE_ARCHIVE" \
  -C "$HIVE_PARAM_INSTALL_DIR" --strip-components=1
sudo chown -R "$HIVE_PARAM_SERVICE_USER:$HIVE_PARAM_SERVICE_USER" \
  "$HIVE_PARAM_INSTALL_DIR"

# 2. Python venv + dependencies
python3 -m venv "$HIVE_PARAM_INSTALL_DIR/venv"
"$HIVE_PARAM_INSTALL_DIR/venv/bin/pip" install --quiet \
  -r "$HIVE_PARAM_INSTALL_DIR/requirements.txt"

# 3. Make shell scripts executable
find "$HIVE_PARAM_INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;

# 4. Runtime permissions and tmpfiles.d for QGC PID file
sudo touch /var/log/qgc-video-stream.log
sudo chown "$HIVE_PARAM_SERVICE_USER:$HIVE_PARAM_SERVICE_USER" \
  /var/log/qgc-video-stream.log
printf 'f /var/run/qgc-video-stream.pid 0644 %s %s -\n' \
  "$HIVE_PARAM_SERVICE_USER" "$HIVE_PARAM_SERVICE_USER" \
  | sudo tee /etc/tmpfiles.d/qgc-video-stream.conf
sudo systemd-tmpfiles --create \
  /etc/tmpfiles.d/qgc-video-stream.conf

# 5. Write systemd unit files
sudo tee /etc/systemd/system/qgc-video-stream.service > /dev/null << EOF
[Unit]
Description=QGC Video Stream
After=network.target

[Service]
Type=simple
User=$HIVE_PARAM_SERVICE_USER
WorkingDirectory=$HIVE_PARAM_INSTALL_DIR
ExecStart=$HIVE_PARAM_INSTALL_DIR/qgc-video-stream.sh
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/"$HIVE_PARAM_PRIMARY_SERVICE".service > /dev/null << EOF
[Unit]
Description=Motor Driver ATV (mavlink_rover)
After=network.target qgc-video-stream.service
Wants=qgc-video-stream.service

[Service]
Type=simple
User=$HIVE_PARAM_SERVICE_USER
WorkingDirectory=$HIVE_PARAM_INSTALL_DIR
ExecStart=$HIVE_PARAM_INSTALL_DIR/venv/bin/python3 $HIVE_PARAM_INSTALL_DIR/mavlink_rover.py
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 6. Enable services
sudo systemctl daemon-reload
sudo systemctl enable qgc-video-stream "$HIVE_PARAM_PRIMARY_SERVICE"

echo "install.sh completed successfully"