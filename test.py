#!/usr/bin/env python3
"""
L298N Hardware Test - Diagnose reverse problem
"""

import RPi.GPIO as gpio
import time

# Your pin configuration
PINS = {
    'left_fwd': 17,
    'left_rev': 22,
    'right_fwd': 23,
    'right_rev': 24
}

def setup():
    gpio.setmode(gpio.BCM)
    gpio.setwarnings(False)
    for pin in PINS.values():
        gpio.setup(pin, gpio.OUT)
        gpio.output(pin, False)
    print("[SETUP] GPIO initialized")

def cleanup():
    for pin in PINS.values():
        gpio.output(pin, False)
    gpio.cleanup()
    print("[CLEANUP] Done")

def test_pin(pin_num, pin_name):
    """Test a single pin"""
    print(f"\n[TEST] Pin {pin_num} ({pin_name})")
    print("  Setting HIGH for 2 seconds...")
    gpio.output(pin_num, True)
    time.sleep(2)
    
    print("  Setting LOW")
    gpio.output(pin_num, False)
    time.sleep(1)

def test_motor(fwd_pin, rev_pin, motor_name):
    """Test forward and reverse for one motor"""
    print(f"\n{'='*50}")
    print(f"Testing {motor_name} Motor")
    print(f"{'='*50}")
    
    # Test forward
    print(f"\n[{motor_name}] FORWARD (pin {fwd_pin} HIGH)")
    gpio.output(fwd_pin, True)
    gpio.output(rev_pin, False)
    time.sleep(3)
    gpio.output(fwd_pin, False)
    
    input(f"\nDid {motor_name} motor spin FORWARD? Press Enter...")
    
    # Test reverse
    print(f"\n[{motor_name}] REVERSE (pin {rev_pin} HIGH)")
    gpio.output(fwd_pin, False)
    gpio.output(rev_pin, True)
    time.sleep(3)
    gpio.output(rev_pin, False)
    
    input(f"\nDid {motor_name} motor spin REVERSE? Press Enter...")

def main():
    print("="*60)
    print("L298N HARDWARE TEST - Reverse Troubleshooting")
    print("="*60)
    print("\nThis test will:")
    print("1. Test each GPIO pin individually")
    print("2. Test each motor forward/reverse")
    print("3. Help diagnose L298N issues")
    print("\nWatch the motors and LEDs on the L298N board!")
    input("\nPress Enter to start...")
    
    setup()
    
    try:
        # Part 1: Test individual pins
        print("\n" + "="*60)
        print("PART 1: Individual Pin Test")
        print("="*60)
        print("Watch for voltage on multimeter or LED on L298N")
        
        for pin_name, pin_num in PINS.items():
            test_pin(pin_num, pin_name)
        
        # Part 2: Test motors
        print("\n" + "="*60)
        print("PART 2: Motor Movement Test")
        print("="*60)
        
        test_motor(PINS['left_fwd'], PINS['left_rev'], "LEFT")
        test_motor(PINS['right_fwd'], PINS['right_rev'], "RIGHT")
        
        # Part 3: Simultaneous test (both motors reverse)
        print("\n" + "="*60)
        print("PART 3: Both Motors REVERSE Simultaneously")
        print("="*60)
        
        print("\nActivating BOTH motors in REVERSE...")
        gpio.output(PINS['left_fwd'], False)
        gpio.output(PINS['left_rev'], True)
        gpio.output(PINS['right_fwd'], False)
        gpio.output(PINS['right_rev'], True)
        
        time.sleep(3)
        
        gpio.output(PINS['left_rev'], False)
        gpio.output(PINS['right_rev'], False)
        
        input("\nDid BOTH motors spin in reverse? Press Enter...")
        
        print("\n" + "="*60)
        print("TEST COMPLETE")
        print("="*60)
        
    except KeyboardInterrupt:
        print("\n\nTest interrupted")
    finally:
        cleanup()

if __name__ == "__main__":
    main()