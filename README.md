# Arduino TextMate Bundle

Edit, compile, and upload Arduino sketches from TextMate. The build commands
are a thin front end over [arduino-cli](https://arduino.github.io/arduino-cli/):
no Java IDE needed, any board with a CLI core works (AVR, ESP32, ...).

## Installation

1. Install this bundle
 * TextMate Preferences > Bundles tick
 * Or clone to `~/Library/Application Support/TextMate/Bundles/`

2. Run Bundles > Arduino > Install / Fix Arduino Tools. It checks for
   Homebrew, arduino-cli, and a board core, and offers to install
   anything missing. (Prefer the terminal? `brew install arduino-cli`,
   then `arduino-cli core install esp32:esp32` -- or `arduino:avr`.)

3. Plug your board in and run Bundles > Arduino > Select Board.
   Single-board setups (e.g. an Uno) work with no configuration:
   the port and board are auto-detected from `arduino-cli board list`.

## Usage

* **Bundles > Arduino > Select Board** Set the board for the current sketch
  (saved to the sketch's `sketch.yaml`; unambiguous setups attach with no
  questions, a plugged-in family opens its short list, otherwise type part
  of the name and pick from the ranked matches)
* **⌘B** Verify Sketch: compile the current sketch
* **⌘U** Upload to Board: compile and upload to the connected board
  (closes our serial monitor first if it holds the port)
* **⇧⌘B** Show Assembly for the current sketch
* **⌃⌘C** Clean the build cache
* **⌃⌥⌘H** Look up the current word in the Arduino docs: CLI commands open
  the command reference, language words open the language reference,
  anything else opens the language index
* **Bundles > Arduino > Monitor with Terminal.app / Monitor with iTerm** Serial monitor on the auto-detected port.
  Before opening it, the launcher reads the port for a quarter of a second.
  A `00 80` stream faster than the baud rate can carry means the USB-serial
  chip is wedged: the monitor would show that as `????`, so it stops and
  tells you to unplug the board and plug it back in. Slower non-text is
  reported as a baud mismatch and the monitor still starts.
* **Bundles > Arduino > Show Board Info** Diagnostics: what the next build and
  monitor will use, where each value came from, detected boards, sketch.yaml

## Where the board, port, and baud come from

The sketch describes itself in `sketch.yaml` (board, monitor baud, usually the
port). The CLI, the Arduino IDE, and a cloned copy of the sketch all read that
file, so Select Board writes there -- FQBN and port via `arduino-cli board
attach`, baud from your sketch's `Serial.begin()`. With it present, bare
`arduino-cli compile`, `upload`, and `monitor` work in the sketch folder.

The port is the shaky entry: `/dev/cu.usbmodem1101` is this Mac and this cable.
Recording it is normal, and a missing or wrong port just falls through to
auto-detection of the one connected board.

Resolution order everywhere (first hit wins):

* port: `TM_ARDUINO_PORT` → sketch.yaml → single connected board → ask.
* baud: `TM_ARDUINO_BAUD` → `Serial.begin()` → sketch.yaml → 115200 default (announced, never asked).
* board: `TM_ARDUINO_FQBN` → sketch.yaml → auto-detect, failing loud when ambiguous.

Shell Variables (TextMate > Settings > Variables -- all optional overrides)
============================================================================

| Variable           | Meaning                                                                      |
|:-------------------|:-----------------------------------------------------------------------------|
| TM_ARDUINO_FQBN    | Board ID, e.g. `esp32:esp32:esp32h2`. Beats sketch.yaml and auto-detection.   |
| TM_ARDUINO_PORT    | Serial port, e.g. `/dev/cu.usbmodem1101`. Also skips the ~1.5s port scan.     |
| TM_ARDUINO_BAUD    | Serial monitor baud rate. Beats `Serial.begin()` and sketch.yaml.             |
| TM_ARDUINO_BUILDER | Build backend (default `arduino-cli`; `idf` is planned for ESP-IDF projects). |

For a sketch you intend to keep, consider adding a `profiles:` block to
`sketch.yaml` pinning the core version and libraries, so it still builds
after a boards-manager update.

How it works
============

All build commands call `Support/bin/arduino-build`, which resolves the CLI,
board, and port, then shells out to `arduino-cli`. `Support/tests/test_resolve.sh`
covers the resolution logic against a stub CLI (no hardware needed):

    sh Support/tests/test_resolve.sh

`Support/language_urls.txt` maps language keywords to docs pages for the
Lookup command; refresh it from the live docs with
`sh Support/update_language_urls.sh`.
