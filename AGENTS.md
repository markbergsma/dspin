# Agent Guidelines & Repository Rules

This document defines architectural standards, hardware constraints, and coding guidelines for AI coding assistants working in the `dspin` repository.

DSPin is a Sendspin network audio player built from an ESP32-S3 board and a [DSPi](https://github.com/WeebLabs/DSPi). This repo holds **one ESPHome config and its documentation** — there is no C++ here. Control is handled by the [`esphome-dspi`](https://github.com/markbergsma/esphome-dspi) component, pulled in via `external_components`.

The **ESP32-S3-BOX-3** is the only board supported today, with others intended. Keep every board-specific value — pins above all — in the `substitutions:` block, so adding a board is an edit to that block rather than a hunt through the config.

---

## 1. Separation of Concerns

**The dependency runs one way: DSPin knows about audio, `esphome-dspi` does not.**

- Control features belong in `esphome-dspi`. If something needs a new DSPi command, add it there and consume it here; do not work around a missing command with a lambda that hand-rolls the protocol.
- Anything audio-specific — Sendspin, I2S, PSRAM sizing, clock-slave wiring — belongs here and must never be pushed down into the component.
- When both repos need changing, change `esphome-dspi` first and verify it standalone, since its tests are the ones that can run without hardware.

---

## 2. Hardware Constraints & Principles

- **PSRAM is a hard requirement**, measured rather than assumed. Sendspin's stream buffer defaults to 1 MB; without PSRAM that allocation fails and both `sendspin` and `sendspin.media_source` are marked FAILED at setup. Shrinking it only moves the failure to the I2S speaker task, because the binding constraint is the largest *contiguous* block rather than total free heap. Do not propose a no-PSRAM board without re-reading the numbers in the README.
- **The ESP32 is the I2S clock master; the DSPi is the clock slave.** That is what lets the DSPi auto-detect the rate and servo its own outputs to our clock.
  - `bits_per_sample: 32bit` is **required** — the DSPi's slave mode expects `BCK = 64 × Fs` and does not detect the frame format at runtime.
  - Only 44.1 / 48 / 96 kHz ever lock. Sendspin resamples to a fixed `sample_rate`, so the DSPi sees a constant rate.
  - No MCLK is wired: the DSPi forces its own MCK output off while clock-slaved.
- **Pin choices are constrained and deliberate.** All five signals come off PMOD1 on the Box-3's PCIe edge connector. GPIO19/20 are the USB D+/D− lines and GPIO42 doubles as SD_D2 — all three are avoided on purpose. See the README before moving any pin.

---

## 3. Known Behaviours — Do Not Re-litigate

These were measured on hardware. Re-deriving them costs a flash cycle each.

- **`timeout: never` on the speaker does not keep the clock running.** It governs bus teardown, not clock output. An explicit pause stops BCLK/LRCLK within ~2 s regardless, dropping the DSPi to ACQUIRING until playback resumes. The option is kept for the teardown behaviour alone.
- **Track changes cost nothing.** Sendspin keeps the stream, and therefore the clock, running across boundaries — verified across a real track change with the lock counters unmoved. Only explicit pause/stop stops it.
- **Expect a beat of silence after unpausing**, and nothing at all between tracks. That is correct behaviour, not a bug to fix.
- **The media_player platform must be `speaker_source`, not `speaker`.** Only `speaker_source` accepts a `sources:` list referencing the Sendspin media source. With plain `speaker` the device receives the stream and has nowhere to put it, logging `Failed to send audio chunk` endlessly — a message that comes from the local pipeline handoff, not the network, so it reads misleadingly.

---

## 4. Build & Verification Workflows

- **Normally build directly**, resolving the component from `@main` as a user would:
  ```bash
  esphome run dspin.yaml --device dspin.local
  ```
- **Build through the wrapper when working on the component itself**, which rewrites the `github://` source to a local checkout in a scratch copy:
  ```bash
  ./tools/build.sh config                    # validate
  ./tools/build.sh compile                   # build
  ./tools/build.sh run --device dspin.local  # build, upload, tail logs
  ```
  `dspin.yaml` itself keeps the published URL, because that is what someone cloning this repo should get. **Do not edit it to a local path**, even temporarily — use the wrapper, or `DSPI_COMPONENTS` if the checkout is not a sibling directory.
- The component tracks `@main` and has no version tags, so its interface can change without notice. If a build breaks after a component change, fix this repo to match rather than pinning around it.
- **Verify audio changes on hardware.** A successful compile proves nothing about clocking. With a DSPi attached over USB:
  ```bash
  python3 tools/dspi_i2s_status.py --watch
  ```
  A healthy player reports `LOCKED` at the configured rate with `slips=0`, and the counters stay still across a track change. This reads over USB, independently of both ESPHome and the UART link, so it still answers when those are the things misbehaving.
- **Credential Safety**: never commit network credentials or keys. Keep them in `secrets.yaml` (excluded by `.gitignore`) and provide sanitized templates in `secrets.yaml.example`.

---

## 5. Debugging & Logs

**Anything ESPHome prints at boot is effectively unreachable on this board.** That includes `dump_config` output and the `i2c` bus scan. Do not spend attempts on it:

- **Over USB**, the logger is `USB_SERIAL_JTAG`, so the port re-enumerates when the app's USB stack starts and the open handle goes stale. The capture stops around `boot: Disabling RNG early entropy source`. Reconnecting works but only shows output from that point on.
- **Over the network**, `App.dump_config()` runs right after `setup()`, while WiFi and API association complete later in `loop()` — so a log client always attaches after the boot output is gone.

**To check whether a peripheral is alive, add a temporary automation that logs at INFO from a trigger** rather than hunting for the boot scan. That also distinguishes "peripheral silent" from "responding but mis-transformed", which a bus scan would not have told you.

Two traps that follow from this:

- A per-tag log level **cannot be more verbose than the global level**, so reading one component's `ESP_LOGD` lines means setting the whole `logger:` to `DEBUG`.
- Flashing can fail with "port is busy" when another `esphome run`/`logs` session holds the serial port. Check `lsof /dev/cu.usbmodem*` before suspecting hardware — and the holder may be a session the user started, so ask rather than killing it.

Also note this machine has **no `timeout` binary**, so bounding a streaming command needs a background process plus `pkill`, not `timeout 30 ...`.

---

## 6. Git

- **Never make a git commit without explicit approval from the user.** Suggest commit messages freely; they are for the user to review or edit.
- Add an **`Assisted-by: <model name>`** trailer when you contributed to a change, e.g. `Assisted-by: Claude Opus 5`.
- Commit messages should summarize *what* and *why*, but not explain the implementation in extensive detail. 2-3 Paragraphs should usually suffice. Record findings either in comments in the config where appropriate, or in the README.
