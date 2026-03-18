# ── hive/gstreamer-install.sh ─────────────────────────────────────────────────
# Lives in the motor_driver repo at hive/gstreamer-install.sh
# Versioned independently — upload to bank as a BankResource.
#
# HIVE injects all release vars as environment variables before execution:
#   HIVE_PARAM_PACKAGE_NAMES → space-separated list of apt package names
#!/bin/bash
set -euo pipefail

echo "Installing GStreamer packages: $HIVE_PARAM_PACKAGE_NAMES"

# Install packages — idempotent
# shellcheck disable=SC2086
sudo apt-get install -y --no-install-recommends $HIVE_PARAM_PACKAGE_NAMES

# Remove broken v4l2codecs plugin (segfaults on arm64)
sudo rm -f \
  /usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstv4l2codecs.so

echo "gstreamer-install.sh completed successfully"