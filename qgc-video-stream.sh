#!/bin/bash
# QGroundControl Video Streaming Service
# Hardware H.264 encoding for minimal latency

set -e

# ============================================
# CONFIGURATION
# ============================================

QGC_IP="192.168.1.69"
QGC_PORT="5600"
WEBCAM_DEVICE="/dev/video0"
WIDTH="640"
HEIGHT="480"
FRAMERATE="30"

# ============================================
# Script
# ============================================

LOG_FILE="/var/log/qgc-video-stream.log"
PID_FILE="/var/run/qgc-video-stream.pid"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "QGroundControl Video Streaming Service"
log "Using HARDWARE H.264 encoding"
log "=========================================="
log "Target: ${QGC_IP}:${QGC_PORT}"
log "Camera: ${WEBCAM_DEVICE}"
log "Resolution: ${WIDTH}x${HEIGHT} @ ${FRAMERATE}fps"

# Check webcam existence
if [ ! -e "$WEBCAM_DEVICE" ]; then
    log "ERROR: Webcam not found at $WEBCAM_DEVICE"
    log "Available devices:"
    ls -l /dev/video* 2>&1 | tee -a "$LOG_FILE" || log "  None found"
    exit 1
fi

# Check GStreamer installation
if ! command -v gst-launch-1.0 &> /dev/null; then
    log "ERROR: GStreamer not installed"
    exit 1
fi

# Network check
if ! ping -c 1 -W 2 "$QGC_IP" &> /dev/null; then
    log "WARNING: Cannot ping QGC at $QGC_IP"
fi

echo $$ > "$PID_FILE"

log "Starting GStreamer pipeline (hardware H.264 → RTP)..."

# Direct H.264 from camera (no re-encoding)
gst-launch-1.0 -v \
    v4l2src device="$WEBCAM_DEVICE" ! \
    video/x-h264,width="$WIDTH",height="$HEIGHT",framerate="$FRAMERATE"/1 ! \
    h264parse config-interval=-1 ! \
    rtph264pay pt=127 config-interval=1 ! \
    application/x-rtp,media=video,clock-rate=90000,encoding-name=H264 ! \
    udpsink host="$QGC_IP" port="$QGC_PORT" 2>&1 | tee -a "$LOG_FILE" &

GSTREAMER_PID=$!

log "GStreamer started with PID $GSTREAMER_PID (PT=127, hardware encoding)"

wait $GSTREAMER_PID
EXIT_CODE=$?

log "GStreamer exited with code $EXIT_CODE"
rm -f "$PID_FILE"

exit $EXIT_CODE