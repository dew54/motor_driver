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
    "RC2_MIN": 1100,
    "RC2_MAX": 1900,
    "RC2_TRIM": 1500,
    "RC3_MIN": 1100,
    "RC3_MAX": 1900,
    "RC3_TRIM": 1500,
    "RC4_MIN": 1100,
    "RC4_MAX": 1900,
    "RC4_TRIM": 1500,
    "SYSID_THISMAV": SYSTEM_ID,
    "MAV_TYPE": mavutil.mavlink.MAV_TYPE_GROUND_ROVER,
    "CRUISE_SPEED": 2.0,
    "CRUISE_THROTTLE": 50,
    "WP_TURN_G": 1.0,
    "BATT_CAPACITY": 10000,
    "BATT_MONITOR": 4,
    "ARMING_CHECK": 1,
}

# Initialize hardware with PWM
print("[INIT] Initializing PWM motor controller...")
motor_controller = MotorControllerPWM(
    pwm_freq=500    # 1kHz PWM frequency
)

print("[INIT] Initializing manual control with acceleration...")
manual_controller = ManualControlPWM(
    motor_controller,
    deadzone=100,
    enable_timeout=True,
    timeout_duration=3.0,
    acceleration_rate=70.0  # 0-100% in 0.5 seconds
)

# State
armed = False
mode = 0
home_position = {
        'lat': 456548733,  # 45.6548733°N
        'lon': 137989892,  # 13.7989892°E
        'alt': 5000        # 5 metri
}

# Joystick tracking
last_manual_control = {"x": None, "y": None, "z": None, "r": None}
JOYSTICK_THRESHOLD = 20

# Parameter queue
param_queue = []

# Helper functions (same as before)
def send_param_value(param_id, param_value, param_index, param_count):
    the_connection.mav.param_value_send(
        param_id.encode('utf-8'),
        float(param_value),
        mavutil.mavlink.MAV_PARAM_TYPE_REAL32,
        param_count,
        param_index
    )

def queue_param_list():
    global param_queue
    param_queue = list(parameters.items())
    print(f"[PARAM] Queued {len(param_queue)} parameters")

def send_next_param():
    global param_queue
    if param_queue:
        idx = len(parameters) - len(param_queue)
        pid, val = param_queue.pop(0)
        send_param_value(pid, val, idx, len(parameters))

def send_home_position():
    the_connection.mav.home_position_send(
        home_position['lat'],
        home_position['lon'],
        home_position['alt'],
        0, 0, 0,
        [1, 0, 0, 0],
        0, 0, 0,
        int(time.time() * 1e6)
    )

def handle_message(msg):
    global armed, mode, home_position

    msg_type = msg.get_type()

    if msg_type == "PARAM_REQUEST_LIST":
        print("[RX] PARAM_REQUEST_LIST")
        queue_param_list()

    elif msg_type == "PARAM_REQUEST_READ":
        param_id = msg.param_id.decode('utf-8').strip('\x00')
        if param_id in parameters:
            idx = list(parameters.keys()).index(param_id)
            send_param_value(param_id, parameters[param_id], idx, len(parameters))

    elif msg_type == "PARAM_SET":
        pid = msg.param_id.decode('utf-8').strip('\x00')
        if pid in parameters:
            parameters[pid] = msg.param_value
            idx = list(parameters.keys()).index(pid)
            send_param_value(pid, msg.param_value, idx, len(parameters))

    elif msg_type == "COMMAND_LONG":
        cmd = msg.command
        
        if cmd == mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM:
            if int(msg.param1) == 1:
                armed = True
                print("[CMD] ✓ ARMED")
            else:
                armed = False
                manual_controller.emergency_stop()
                print("[CMD] ✓ DISARMED - emergency stop")
            
            the_connection.mav.command_ack_send(
                cmd,
                mavutil.mavlink.MAV_RESULT_ACCEPTED
            )

        elif cmd == mavutil.mavlink.MAV_CMD_DO_SET_HOME:
            home_position['lat'] = int(msg.param5 * 1e7)
            home_position['lon'] = int(msg.param6 * 1e7)
            home_position['alt'] = int(msg.param7 * 1000)
            send_home_position()
            the_connection.mav.command_ack_send(cmd, mavutil.mavlink.MAV_RESULT_ACCEPTED)

        elif cmd == mavutil.mavlink.MAV_CMD_DO_SET_MODE:
            mode = int(msg.param2)
            the_connection.mav.command_ack_send(cmd, mavutil.mavlink.MAV_RESULT_ACCEPTED)

    elif msg_type == "MANUAL_CONTROL":
        changed = False
        for axis in ["x", "y", "z", "r"]:
            val = getattr(msg, axis)
            last_val = last_manual_control[axis]
            if last_val is None or abs(val - last_val) > JOYSTICK_THRESHOLD:
                changed = True
            last_manual_control[axis] = val

        if changed and armed:
            manual_controller.manage_command(msg)

# Wait for QGC heartbeat
print("[INIT] Waiting for QGroundControl...")
while True:
    the_connection.mav.heartbeat_send(
        type=mavutil.mavlink.MAV_TYPE_GROUND_ROVER,
        autopilot=mavutil.mavlink.MAV_AUTOPILOT_ARDUPILOTMEGA,
        base_mode=0,
        custom_mode=0,
        system_status=mavutil.mavlink.MAV_STATE_STANDBY
    )
    
    msg = the_connection.recv_match(type='HEARTBEAT', blocking=False)
    if msg:
        print(f"[INIT] ✓ Connected to system {msg.get_srcSystem()}")
        break
    time.sleep(0.5)

print("[INIT] Starting main loop with PWM control...")

# Loop timers
last_heartbeat = 0
last_sys_status = 0
last_attitude = 0
last_global_pos = 0
last_param_send = 0
last_motor_update = 0

try:
    while True:
        now = time.time()

        # Process messages
        while True:
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
                base_mode |= mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED
            
            the_connection.mav.heartbeat_send(
                type=mavutil.mavlink.MAV_TYPE_GROUND_ROVER,
                autopilot=mavutil.mavlink.MAV_AUTOPILOT_ARDUPILOTMEGA,
                base_mode=base_mode,
                custom_mode=mode,
                system_status=mavutil.mavlink.MAV_STATE_ACTIVE
            )
            last_heartbeat = now

        # System status (2Hz)
        if now - last_sys_status >= 0.5:
            the_connection.mav.sys_status_send(
                0xFFFF, 0xFFFF, 0xFFFF,
                500, 12000, 500, 80,
                0, 0, 0, 0, 0, 0
            )
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