#!/usr/bin/env python3
"""
Manual control handler with PWM speed control and acceleration ramping
"""

import time


class ManualControlPWM:
    """
    Handles MANUAL_CONTROL with smooth acceleration/deceleration.
    Supports PWM motor controllers for variable speed.
    """
    
    def __init__(self, motor_controller, deadzone=200, 
                 enable_timeout=True, timeout_duration=3.0,
                 acceleration_rate=2.0):
        """
        Initialize manual control with PWM support.
        
        Args:
            motor_controller: MotorControllerPWM instance
            deadzone (int): Joystick deadzone (0-1000 range)
            enable_timeout (bool): Enable command timeout
            timeout_duration (float): Timeout in seconds
            acceleration_rate (float): Speed change per second (0-1 scale)
                                      2.0 = full speed in 0.5s
                                      1.0 = full speed in 1.0s
                                      0.5 = full speed in 2.0s
        """
        self.motors = motor_controller
        self.deadzone = deadzone
        self.enable_timeout = enable_timeout
        self.command_timeout = timeout_duration
        self.acceleration_rate = acceleration_rate
        
        # Current and target speeds
        self.current_left = 0.0
        self.current_right = 0.0
        self.target_left = 0.0
        self.target_right = 0.0
        
        self.last_command_time = 0
        self.last_update_time = time.time()
        
        print(f"[MANUAL_PWM] Initialized")
        print(f"  Deadzone: {deadzone}")
        print(f"  Timeout: {'OFF' if not enable_timeout else f'{timeout_duration}s'}")
        print(f"  Acceleration: {acceleration_rate:.1f}/s")
    
    def manage_command(self, msg):
        """
        Process MANUAL_CONTROL message and update target speeds.
        
        Args:
            msg: MAVLink MANUAL_CONTROL message
        """
        self.last_command_time = time.time()
        
        # Extract and normalize
        throttle = self._normalize(msg.x)
        steering = self._normalize(msg.y)  # Inverted for correct direction
        
        # Apply deadzone
        throttle = self._apply_deadzone(throttle)
        steering = self._apply_deadzone(steering)
        
        # Tank drive mixing
        left = throttle - steering
        right = throttle + steering
        
        # Clamp
        left = max(-1.0, min(1.0, left))
        right = max(-1.0, min(1.0, right))
        
        # Update targets
        self.target_left = left
        self.target_right = right
        
        # Debug
        print(f"[MANUAL_PWM] T:{throttle:+.2f} S:{steering:+.2f} → Target L:{left:+.2f} R:{right:+.2f}")
    
    def update_motors(self):
        """
        Update motor speeds with acceleration ramping.
        Call this periodically (e.g., 50Hz) for smooth motion.
        
        Returns:
            bool: True if motors are moving
        """
        now = time.time()
        dt = now - self.last_update_time
        self.last_update_time = now
        
        # Maximum speed change this frame
        max_delta = self.acceleration_rate * dt
        
        # Ramp left motor
        if abs(self.target_left - self.current_left) > 0.01:
            delta_left = self.target_left - self.current_left
            if abs(delta_left) > max_delta:
                delta_left = max_delta if delta_left > 0 else -max_delta
            self.current_left += delta_left
        else:
            self.current_left = self.target_left
        
        # Ramp right motor
        if abs(self.target_right - self.current_right) > 0.01:
            delta_right = self.target_right - self.current_right
            if abs(delta_right) > max_delta:
                delta_right = max_delta if delta_right > 0 else -max_delta
            self.current_right += delta_right
        else:
            self.current_right = self.target_right
        
        # Apply to motors
        self.motors.set_motors(self.current_left, self.current_right)
        
        # Return True if still moving
        return abs(self.current_left) > 0.01 or abs(self.current_right) > 0.01
    
    def check_timeout(self):
        """Check for command timeout and stop if needed"""
        if not self.enable_timeout:
            return False
        
        if time.time() - self.last_command_time > self.command_timeout:
            # Set targets to zero (will ramp down)
            if self.target_left != 0 or self.target_right != 0:
                print("[MANUAL_PWM] Timeout - ramping down")
                self.target_left = 0
                self.target_right = 0
                return True
        return False
    
    def emergency_stop(self):
        """Immediate stop without ramping (for safety)"""
        self.target_left = 0
        self.target_right = 0
        self.current_left = 0
        self.current_right = 0
        self.motors.stop()
        print("[MANUAL_PWM] Emergency stop!")
    
    def _normalize(self, value):
        """Normalize MAVLink value (-1000 to 1000) to (-1.0 to 1.0)"""
        return max(-1.0, min(1.0, value / 1000.0))
    
    def _apply_deadzone(self, value):
        """Apply deadzone to normalized value"""
        deadzone_normalized = self.deadzone / 1000.0
        
        if abs(value) < deadzone_normalized:
            return 0.0
        
        # Scale remaining range to full -1..1
        sign = 1 if value > 0 else -1
        return sign * (abs(value) - deadzone_normalized) / (1.0 - deadzone_normalized)