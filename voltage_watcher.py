#!/usr/bin/env python3
# Watches the Raspberry Pi throttling/under-voltage flag via vcgencmd.
# Bit mapping: https://www.raspberrypi.com/documentation/computers/os.html#get_throttled

import subprocess
import time
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# Bit masks from official documentation
THROTTLE_FLAGS = {
    0x00001: "Under-voltage detected",
    0x00002: "Arm frequency capped",
    0x00004: "Currently throttled",
    0x00008: "Soft temperature limit active",
    0x10000: "Under-voltage has occurred",
    0x20000: "Arm frequency capping has occurred",
    0x40000: "Throttling has occurred",
    0x80000: "Soft temperature limit has occurred",
}

def get_throttled() -> int:
    """Returns the raw throttled bitmask from vcgencmd."""
    result = subprocess.run(
        ["vcgencmd", "get_throttled"],
        capture_output=True, text=True, timeout=2
    )
    # Output format: "throttled=0x00000"
    raw = result.stdout.strip().split("=")[1]
    return int(raw, 16)

def decode_flags(value: int) -> list[str]:
    """Decodes active flags from bitmask."""
    return [desc for mask, desc in THROTTLE_FLAGS.items() if value & mask]

def watch(interval_sec: float = 1.0):
    logging.info("Starting throttle watcher (interval=%.1fs)", interval_sec)
    prev_value = None

    while True:
        try:
            value = get_throttled()

            # Log only on change (avoid log spam)
            if value != prev_value:
                if value == 0:
                    logging.info("OK — no throttling flags active (0x%05x)", value)
                else:
                    active = decode_flags(value)
                    for flag in active:
                        logging.warning("FLAG ACTIVE: %s (raw=0x%05x)", flag, value)
                prev_value = value

        except Exception as e:
            logging.error("vcgencmd failed: %s", e)

        time.sleep(interval_sec)

if __name__ == "__main__":
    watch(interval_sec=1.0)