#!/bin/bash
cd /home/pi/CODE/motor_driver

./qgc-video-stream.sh &
exec /home/pi/CODE/motor_driver/venv/bin/python3 mavlink_rover.py
