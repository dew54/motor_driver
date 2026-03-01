#!/usr/bin/env python3
"""
MAVLink Ground Rover Node with PWM Speed Control
Smooth acceleration/deceleration for better control
"""

import time
import math
from pymavlink import mavutil
from manual_control import ManualControlPWM
from motor_controller import MotorControllerPWM

# MAVLink identifiers
SYSTEM_ID = 1
COMPONENT_ID = 1
UDP_PORT = 14550

# Connection
the_connection = mavutil.mavlink_connection(
    f'udpin:0.0.0.0:{UDP_PORT}',
    source_system=SYSTEM_ID,
    source_component=COMPONENT_ID,
    protocol='mavlink2'
)

print(f"[INIT] MAVLink listening on UDP port {UDP_PORT}")

# Parameters (same as before)
parameters = {
    "RCMAP_ROLL": 1,
    "RCMAP_PITCH": 2,
    "RCMAP_YAW": 4,
    "RCMAP_THROTTLE": 3,
    "RC1_MIN": 1100,
    "RC1_MAX": 1900,
    "RC1_TRIM": 1500,
            msg = the_connection.recv_match(blocking=False)
            if not msg:
                break
            handle_message(msg)

        # Update motors with acceleration (50Hz)
        if now - last_motor_update >= 0.02:
            if armed:
                manual_controller.update_motors()
                manual_controller.check_timeout()
            last_motor_update = now

        # Heartbeat (1Hz)
        if now - last_heartbeat >= 1.0:
            base_mode = 0
            if armed:
            last_sys_status = now

        # Attitude (10Hz)
        if now - last_attitude >= 0.1:
            the_connection.mav.attitude_send(
                int(now * 1000) & 0xFFFFFFFF,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0
            )
            last_attitude = now

        # Position (2Hz)
        if now - last_global_pos >= 0.5:
            the_connection.mav.global_position_int_send(
                int(now * 1000) & 0xFFFFFFFF,
                home_position['lat'],
                home_position['lon'],
                home_position['alt'],
                0, 0, 0, 0, 65535
            )
            last_global_pos = now

        # Parameters (20Hz max)
        if param_queue and now - last_param_send >= 0.05:
            send_next_param()
            last_param_send = now

        time.sleep(0.005)  # ~200Hz main loop

except KeyboardInterrupt:
    print("\n[SHUTDOWN] Keyboard interrupt")
finally:
    print("[SHUTDOWN] Stopping motors...")
    motor_controller.stop()
    motor_controller.cleanup()
    print("[SHUTDOWN] Complete")
