#!/usr/bin/env python3
"""Read the DSPi's I2S clock-slave lock status over USB.

This is the view from the far end of the audio link: whether the DSPi can see
the ESP32's clock, what rate it thinks it is, and whether it has been losing
lock or slipping frames. It reads over USB, independently of the UART control
link and of ESPHome, so it still answers when the rest is misbehaving.

Usage:
    python3 dspi_i2s_status.py            # one reading
    python3 dspi_i2s_status.py --watch    # print only when something changes

What to expect once DSPin is playing:
    state LOCKED, detected 48000 Hz, measured within a few tens of ppm of it,
    and slips staying at 0. Track changes should not move the counters at all.
    An explicit pause stops the clock: measured drops to 0, state falls to
    ACQUIRING, and losses increments once. That is normal -- it re-locks in
    under 2 s on resume.
"""

from __future__ import annotations

import argparse
import struct
import sys
import time

try:
    import usb.core
except ImportError:
    sys.exit("pyusb is required:  pip install pyusb")

VID, PID = 0x2E8B, 0xFEAA
VENDOR_INTERFACE = 2
IN = 0xC1
REQ_GET_I2S_SLAVE_STATUS = 0x8A

STATES = {
    0: "INACTIVE",   # not in the slave role, or the input is stopped
    1: "ACQUIRING",  # measuring, no lock yet; outputs muted
    2: "RELOCKING",  # clocks lost or the rate changed; outputs muted
    3: "LOCKED",     # locked to a supported external rate
}


def read(dev) -> dict:
    # I2sSlaveStatusPacket, 16 bytes, little-endian and packed.
    raw = bytes(dev.ctrl_transfer(IN, REQ_GET_I2S_SLAVE_STATUS, 0, VENDOR_INTERFACE, 16))
    state, mode, locks, losses, rate, measured, slips = struct.unpack("<BBBBIIB", raw[:13])
    return {
        "state": state,
        "clock_mode": mode,
        "locks": locks,
        "losses": losses,
        "detected": rate,
        "measured": measured,
        "slips": slips,
    }


def line(s: dict) -> str:
    ppm = ""
    if s["detected"] and s["measured"]:
        # How far the ESP32's clock sits from the rate the DSPi snapped to.
        off = (s["measured"] - s["detected"]) / s["detected"] * 1e6
        ppm = f" ({off:+.0f} ppm)"
    return (
        f"{STATES.get(s['state'], '?'):<9} "
        f"clock={'slave' if s['clock_mode'] else 'master':<6} "
        f"detected={s['detected'] or '-':<6} "
        f"measured={s['measured'] or '-':<6}{ppm:<13} "
        f"locks={s['locks']} losses={s['losses']} slips={s['slips']}"
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--watch", action="store_true", help="poll and print only on change")
    ap.add_argument("--interval", type=float, default=2.0, help="seconds between polls with --watch")
    args = ap.parse_args()

    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        sys.exit(f"No DSPi found (looked for {VID:#06x}:{PID:#06x}). Is it plugged in?")

    if not args.watch:
        s = read(dev)
        print(line(s))
        if s["clock_mode"] == 0:
            print("\nThe DSPi is in I2S clock-MASTER mode, so it is driving the clock rather")
            print("than following the ESP32. Run:  python3 dspi_setup.py --apply --audio")
        elif s["state"] != 3 and s["measured"] == 0:
            print("\nNo clock is arriving. Either nothing is playing, or check the I2S wiring")
            print("(BCLK, LRCLK and data, plus a common ground).")
        return 0

    print("watching; Ctrl-C to stop")
    previous = None
    try:
        while True:
            s = read(dev)
            key = (s["state"], s["locks"], s["losses"], s["slips"])
            if key != previous:
                print(f"{time.strftime('%H:%M:%S')}  {line(s)}")
                previous = key
            time.sleep(args.interval)
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
