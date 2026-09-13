# DSPin

A Sendspin network audio player built using ESPHome running on an ESP32-S3,
coupled with a [**DSPi**](https://github.com/WeebLabs/DSPi) board.

DSPi is an amazing project that turns a $5 Raspberry Pi Pico (2) into a full
fledged audio DSP / audio processor / DAC. Adding [ESPHome](https://esphome.io)
with an ESP32 integrates it with Home Assistant and streaming audio over the open
[**Sendspin**](https://www.sendspin-audio.com/) protocol, allowing synchronized,
whole house streaming.

The ESP32 receives synchronized network audio over the Open Home Foundation's
Sendspin protocol and feeds it to the DSPi as I2S, while separately controlling
the DSP over UART so it appears in Home Assistant. The DSPi does the actual
signal processing and drives the DACs.

The name is not quite a coincidence: `sendspin` contains `dspi`
(`sen·dspin`).

## Supported functionality
- Basic control in Home Assistant: user volume & master volume (in dB), mute, source selection, media_player entity, and track meta data.
- Streaming audio over Sendspin (from e.g. Music Assistant)

## Supported hardware

- ESP32-S3-BOX-3

Alternative hardware should be implemented & supported soon. Unfortunately, not any
ESP32-S3 will work, as **PSRAM** is required for Sendspin to operate -- see below.

DSPi:

- Any RP2040/RP2350 board supported by DSPi that exposes GPIO pins for UART and I2S.

## Architecture

Two independent links, deliberately not coupled:

```
                  ┌──────────────────────────┐
   Sendspin ─wifi─▶│  DSPin  (ESP32-S3-BOX-3) │
                  │  sendspin → speaker_source│
                  │  media_player → i2s_audio │
                  └──┬────────────────────┬───┘
     I2S, 3 wires    │                    │  UART, 2 wires
     ESP32 = clock   │                    │  8N1, 460800
        master       ▼                    ▼
                  ┌──────────────────────────┐
                  │ DSPi (RP2350)            │
                  │ input=I2S, clock=SLAVE   │──▶ DAC(s) via I2S / S/PDIF out
                  └──────────────────────────┘
```

Control is a separate concern entirely, handled by the
[**esphome-dspi**](https://github.com/markbergsma/esphome-dspi) component, which
knows nothing about audio and is useful on its own.

## Prerequisites

**A DSPi with its UART control interface enabled**, and its I2S input in
clock-slave mode. Both are one-time setup over USB, using
[`dspi_setup.py`](https://github.com/markbergsma/esphome-dspi/blob/main/tools/dspi_setup.py),
which ships with `esphome-dspi`:

```bash
pip install pyusb
curl -O https://raw.githubusercontent.com/markbergsma/esphome-dspi/main/tools/dspi_setup.py

python3 dspi_setup.py                          # read-only: show state
python3 dspi_setup.py --apply --audio --persist
```

`--persist` saves these settings beyond a reboot of the DSPi device.

## Wiring

### ESP32-S3-BOX-3

| ESP32 | → | DSPi | | DOCK position |
|---|---|---|---|---|
| GPIO39 | → | GPIO 2 | I2S BCK (slave pair) | PMOD1 IO3 |
| GPIO40 | → | GPIO 3 | I2S LRCLK | PMOD1 IO4 |
| GPIO41 | → | GPIO 1 | I2S data | PMOD1 IO8 |
| GPIO38 | → | GPIO 17 | UART RX | PMOD1 IO7 |
| GPIO21 | ← | GPIO 16 | UART TX | PMOD1 IO5 |
| GND | — | GND | | |

No MCLK line is wired: the DSPi forces its own MCK output off while clock-slaved
and does not want one from us.

Alternate pinouts may work as well, but need reconfiguration.

3.3 V logic throughout, and never drive the DSPi's RX pin above 3.3 V.

## Building

`esphome-dspi` is pulled in as an external component from `@main`, so the
normal case needs nothing special:

```bash
esphome run dspin.yaml --device dspin.local
```

## Hardware notes

### Clock behaviour

The ESP32 is the **I2S clock master** and the DSPi is the **clock slave**, which
is what lets the DSPi auto-detect the rate and servo its own outputs to our
clock. Two consequences:

- `bits_per_sample: 32bit` is required. The DSPi's slave mode expects
  **BCK = 64 × Fs** and does not detect the frame format at runtime. Rates other
  than 44.1 / 48 / 96 kHz never lock.
- **The DSPi forces its MCK output off** in slave mode, since a locally
  generated master clock would be asynchronous to our BCK/LRCLK. A downstream
  DAC that needs MCLK must generate its own.

Sendspin resamples to a fixed rate (`sample_rate`, default 48000) rather than
following the source, so the DSPi sees a constant 48 kHz.

### Why PSRAM is required

Sendspin's stream buffer defaults to **1 MB**. On an ESP32-S3 without PSRAM that
allocation fails outright and both `sendspin` and `sendspin.media_source` are
marked FAILED during setup, so nothing runs at all. Shrinking the buffer until it
fits, effectively leaves only 0.2s of audio buffering.

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
