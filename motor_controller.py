#!/usr/bin/env python3
"""
Motor controller with PWM speed control for differential drive rover
Supports variable speed via L298N ENA/ENB pins
"""

import RPi.GPIO as gpio
import threading
import time


class MotorControllerPWM:
    """
    Controls a differential drive rover using H-bridge motor driver with PWM.
    
    Pin mapping:
    - GPIO 17: Left motor forward (IN1)
    - GPIO 22: Left motor reverse (IN2)
    - GPIO 23: Right motor forward (IN3)
    - GPIO 24: Right motor reverse (IN4)
    - GPIO 12: Left motor speed (ENA) - PWM
    - GPIO 13: Right motor speed (ENB) - PWM
    """
    
    def __init__(self, direction_pins=None, pwm_pins=None, pwm_freq=1000):
        """
        Initialize motor controller with PWM.
        
        Args:
            direction_pins (dict): Direction control pins
            pwm_pins (dict): PWM enable pins
            pwm_freq (int): PWM frequency in Hz (default 1000Hz)
        """
        if direction_pins is None:
            self.dir_pins = {
                'left_fwd': 17,
                'left_rev': 22,
                'right_fwd': 23,
                'right_rev': 24
            }
        else:
            self.dir_pins = direction_pins
        
        if pwm_pins is None:
            self.pwm_pins = {
                'left_enable': 12,   # ENA
                'right_enable': 13   # ENB
            }
        else:
            self.pwm_pins = pwm_pins
        
        self.pwm_freq = pwm_freq
        
        # Initialize GPIO
        gpio.setmode(gpio.BCM)
        gpio.setwarnings(False)
        
        # Setup direction pins
        for pin in self.dir_pins.values():
            gpio.setup(pin, gpio.OUT)
            gpio.output(pin, False)
        
        # Setup PWM pins
        for pin in self.pwm_pins.values():
            gpio.setup(pin, gpio.OUT)
        
        # Create PWM objects
        self.pwm_left = gpio.PWM(self.pwm_pins['left_enable'], pwm_freq)
        self.pwm_right = gpio.PWM(self.pwm_pins['right_enable'], pwm_freq)
        
        # Start PWM at 0% duty cycle
        self.pwm_left.start(0)
        self.pwm_right.start(0)
        
        self.lock = threading.Lock()
        self.current_state = {
            'left_speed': 0.0,
            'left_direction': 0,
            'right_speed': 0.0,
            'right_direction': 0
        }
        
        print(f"[MOTOR_PWM] Initialized")
        print(f"  Direction pins: {self.dir_pins}")
        print(f"  PWM pins: {self.pwm_pins}")
        print(f"  PWM frequency: {pwm_freq}Hz")
    
    def set_motors(self, left_speed, right_speed):
        """
        Set motor speeds with direction.
        
        Args:
            left_speed (float): -1.0 (full reverse) to +1.0 (full forward)
            right_speed (float): -1.0 (full reverse) to +1.0 (full forward)
        """
        with self.lock:
            # Clamp values
            left_speed = max(-1.0, min(1.0, left_speed))
            right_speed = max(-1.0, min(1.0, right_speed))
            
            # Extract direction and magnitude
            left_dir = 1 if left_speed > 0 else (-1 if left_speed < 0 else 0)
            right_dir = 1 if right_speed > 0 else (-1 if right_speed < 0 else 0)
            
            left_mag = abs(left_speed)
            right_mag = abs(right_speed)
            
            # Set direction pins (inverted based on your hardware)
            gpio.output(self.dir_pins['left_fwd'], left_dir < 0)   # Inverted
            gpio.output(self.dir_pins['left_rev'], left_dir > 0)   # Inverted
            gpio.output(self.dir_pins['right_fwd'], right_dir < 0) # Inverted
            gpio.output(self.dir_pins['right_rev'], right_dir > 0) # Inverted
            
            # Set PWM duty cycle (0-100%)
            self.pwm_left.ChangeDutyCycle(left_mag * 100)
            self.pwm_right.ChangeDutyCycle(right_mag * 100)
            
            # Update state
            self.current_state = {
                'left_speed': left_speed,
                'left_direction': left_dir,
                'right_speed': right_speed,
                'right_direction': right_dir
            }
    
    def forward(self, speed=1.0):
        """Move forward at specified speed"""
        self.set_motors(speed, speed)
    
    def reverse(self, speed=1.0):
        """Move backward at specified speed"""
        self.set_motors(-speed, -speed)
    
    def left_turn(self, speed=1.0):
        """Turn left at specified speed"""
        self.set_motors(-speed, speed)
    
    def right_turn(self, speed=1.0):
        """Turn right at specified speed"""
        self.set_motors(speed, -speed)
    
    def stop(self):
        """Stop all motors"""
        self.set_motors(0, 0)
    
    def get_state(self):
        """Get current motor state"""
        with self.lock:
            return self.current_state.copy()
    
    def cleanup(self):
        """Clean shutdown"""
        self.stop()
        self.pwm_left.stop()
        self.pwm_right.stop()
        gpio.cleanup()
        print("[MOTOR_PWM] Cleanup complete")


if __name__ == "__main__":
    # Test with gradual acceleration
    print("Testing PWM motor controller with acceleration...")
    motors = MotorControllerPWM()
    
    try:
        print("\nGradual acceleration forward")
        for speed in [0.2, 0.4, 0.6, 0.8, 1.0]:
            print(f"  Speed: {speed*100:.0f}%")
            motors.forward(speed)
            time.sleep(0.5)
        
        print("\nGradual deceleration")
        for speed in [0.8, 0.6, 0.4, 0.2, 0.0]:
            print(f"  Speed: {speed*100:.0f}%")
            motors.forward(speed)
            time.sleep(0.5)
        
        print("\nStop")
        motors.stop()
        time.sleep(1)
        
        print("\nGradual turn")
        for speed in [0.3, 0.6, 0.9]:
            print(f"  Turn speed: {speed*100:.0f}%")
            motors.left_turn(speed)
            time.sleep(0.5)
        
        motors.stop()
        
    except KeyboardInterrupt:
        print("\nInterrupted")
    finally:
        motors.cleanup()