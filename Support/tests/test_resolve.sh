#!/bin/bash
# Focused test for Support/bin/arduino-build board/port resolution.
# Runs with a stub arduino-cli; needs no hardware. Run: sh test_resolve.sh
BIN="$(cd "$(dirname "$0")/../bin" && pwd)/arduino-build"
TMP="$(mktemp -d -t arduino-test)" || exit 1
trap 'rm -rf "$TMP"' EXIT
FAIL=0

cat > "$TMP/arduino-cli" <<'STUB'
#!/bin/bash
if [ "$1 $2" = "board list" ]; then cat "$STUB_JSON"
elif [ "$1 $2" = "board listall" ]; then cat "$STUB_KNOWN"
elif [ "$1 $2" = "core list" ]; then cat "$STUB_CORES"
elif [ "$1 $2" = "board attach" ]; then
  if [ -n "$STUB_ATTACH_FAIL" ]; then echo "STUB-ATTACH-BOOM" >&2; exit 3; fi
  shift 2; F=""; P=""; PSET=0; D=""
  while [ $# -gt 0 ]; do case "$1" in
    -b) F="$2"; shift 2;; -p) P="$2"; PSET=1; shift 2;; *) D="$1"; shift;;
  esac; done
  Y="$D/sketch.yaml"; touch "$Y"
  grep -v '^default_fqbn:' "$Y" > "$Y.tmp" || true
  if [ $PSET = 1 ]; then grep -v '^default_port:' "$Y.tmp" > "$Y.tmp2" || true; mv "$Y.tmp2" "$Y.tmp"; fi
  { echo "default_fqbn: $F"; [ $PSET = 1 ] && echo "default_port: $P"; cat "$Y.tmp"; } > "$Y"; rm -f "$Y.tmp"
  echo "STUB-ATTACH fqbn=$F port=$P"
elif [ "$1 $2" = "config get" ]; then echo "/tmp/fake-sketchbook"
elif [ "$1" = "version" ]; then echo "arduino-cli  Version: 9.9.9 Commit: stub"
elif [ "$1" = "compile" ]; then
  if [ -n "$STUB_COMPILE_FAIL" ]; then exit 7; fi
  if [ -n "$STUB_COMPILE_SLEEP" ]; then sleep "$STUB_COMPILE_SLEEP"; fi
  echo "STUB-COMPILE $*"
elif [ "$1" = "cache" ]; then echo "STUB-CLEAN"
elif [ "$1" = "monitor" ]; then echo "STUB-MONITOR $*"
else echo "STUB: unexpected: $*" >&2; exit 9; fi
STUB
chmod +x "$TMP/arduino-cli"

# listall: uno, esp32, ozobot, feather are real; esp32_family is a detection alias.
# only the esp32 core is "installed", so uno must be filtered from installed.
# feather sorts first alphabetically but must rank below ESP32 Dev Module.
cat > "$TMP/known.json" <<'JSON'
{"boards": [{"name": "Uno", "fqbn": "arduino:avr:uno"}, {"name": "ESP32 Dev Module", "fqbn": "esp32:esp32:esp32"}, {"name": "Ozobot DRVKit", "fqbn": "esp32:esp32:ozobot_drvkit"}, {"name": "Adafruit Feather ESP32", "fqbn": "esp32:esp32:feather_esp32"}]}
JSON
cat > "$TMP/cores.json" <<'JSON'
{"platforms": [{"id": "esp32:esp32"}]}
JSON
cat > "$TMP/one.json" <<'JSON'
{"detected_ports": [
  {"port": {"address": "/dev/cu.usbmodem1"}, "matching_boards": [{"name": "Uno", "fqbn": "arduino:avr:uno"}]},
  {"port": {"address": "/dev/cu.Bluetooth-Incoming-Port"}}
]}
JSON
cat > "$TMP/two.json" <<'JSON'
{"detected_ports": [
  {"port": {"address": "/dev/cu.usbmodem1"}, "matching_boards": [{"name": "Uno", "fqbn": "arduino:avr:uno"}]},
  {"port": {"address": "/dev/cu.usbmodem2"}, "matching_boards": [{"name": "ESP32", "fqbn": "esp32:esp32:esp32"}]}
]}
JSON
cat > "$TMP/alias.json" <<'JSON'
{"detected_ports": [
  {"port": {"address": "/dev/cu.usbmodem1"}, "matching_boards": [
    {"name": "ESP32 Family Device", "fqbn": "esp32:esp32:esp32_family"},
    {"name": "Ozobot DRVKit", "fqbn": "esp32:esp32:ozobot_drvkit"}]}
]}
JSON
echo '{"detected_ports": [{"port": {"address": "/dev/cu.Bluetooth-Incoming-Port"}}]}' > "$TMP/none.json"
cat > "$TMP/unmatched.json" <<'JSON'
{"detected_ports": [
  {"port": {"address": "/dev/cu.usbserial-0001", "protocol_label": "Serial Port (USB)"}},
  {"port": {"address": "/dev/cu.Bluetooth-Incoming-Port", "protocol_label": "Serial Port"}}
]}
JSON
cat > "$TMP/multiu.json" <<'JSON'
{"detected_ports": [
  {"port": {"address": "/dev/cu.usbserial-0001", "protocol_label": "Serial Port (USB)"}},
  {"port": {"address": "/dev/cu.usbserial-0002", "protocol_label": "Serial Port (USB)"}}
]}
JSON

mkdir -p "$TMP/Sketch" && echo "void setup(){} void loop(){}" > "$TMP/Sketch/Sketch.ino"

check() { # label, expected, actual
  if [ "$2" = "$3" ]; then echo "PASS $1";
  else echo "FAIL $1 -- want [$2] got [$3]"; FAIL=1; fi
}

export PATH="$TMP:/usr/bin:/bin"
export STUB_KNOWN="$TMP/known.json"
export STUB_CORES="$TMP/cores.json"
export ARDUINO_CLI="$TMP/arduino-cli"
export ARDUINO_CACHE_DIR="$TMP/cache"
export STUB_JSON="$TMP/one.json"

check "single board auto-picks" "PORT=/dev/cu.usbmodem1
FQBN=arduino:avr:uno" "$(env -u TM_ARDUINO_FQBN -u TM_ARDUINO_PORT "$BIN" detect)"

check "explicit port picks its board" "PORT=/dev/cu.usbmodem2
FQBN=esp32:esp32:esp32" "$(STUB_JSON=$TMP/two.json TM_ARDUINO_PORT=/dev/cu.usbmodem2 "$BIN" detect)"

STUB_JSON=$TMP/two.json "$BIN" detect >/dev/null 2>&1
check "two boards fails loud" "1" "$?"
STUB_JSON=$TMP/two.json "$BIN" detect 2>&1 | grep -q "Select Board"
check "two-boards message points at Select Board" "0" "$?"
STUB_JSON=$TMP/two.json "$BIN" detect 2>&1 | grep -q "looks like: Uno, ESP32 Dev Module"
check "two-boards names friendly boards" "0" "$?"
STUB_JSON=$TMP/two.json "$BIN" detect 2>&1 | grep -q "arduino:avr:uno"
check "two-boards hides board IDs" "1" "$?"

STUB_JSON=$TMP/alias.json "$BIN" detect >/dev/null 2>&1
check "alias mix fails loud" "1" "$?"
STUB_JSON=$TMP/alias.json "$BIN" detect 2>&1 | grep -q "looks like: Ozobot DRVKit, ESP32 Family Device"
check "alias message names friendly boards" "0" "$?"
STUB_JSON=$TMP/alias.json "$BIN" detect 2>&1 | grep -q "esp32_family"
check "alias message hides board IDs" "1" "$?"

check "explicit FQBN trusted over alias" "PORT=/dev/cu.usbmodem1
FQBN=esp32:esp32:esp32" "$(STUB_JSON=$TMP/alias.json TM_ARDUINO_FQBN=esp32:esp32:esp32 "$BIN" detect)"

check "unrecognized USB takes explicit board" "PORT=/dev/cu.usbserial-0001
FQBN=esp32:esp32:esp32" "$(STUB_JSON=$TMP/unmatched.json TM_ARDUINO_FQBN=esp32:esp32:esp32 "$BIN" detect)"
STUB_JSON=$TMP/unmatched.json "$BIN" detect >/dev/null 2>&1
check "unrecognized USB fails loud" "1" "$?"
STUB_JSON=$TMP/unmatched.json "$BIN" detect 2>&1 | grep -q "do not recognize it.*Select Board"
check "unrecognized message points at Select Board" "0" "$?"
STUB_JSON=$TMP/multiu.json TM_ARDUINO_FQBN=esp32:esp32:esp32 "$BIN" detect 2>&1 | grep -q "more than one unrecognized"
check "two unknowns refuse to guess" "0" "$?"
STUB_JSON=$TMP/unmatched.json TM_ARDUINO_PORT=/dev/cu.usbserial-0001 "$BIN" detect 2>&1 | grep -q "cannot tell which board is on"
check "port-only on unknown asks for board" "0" "$?"

check "explicit port+fqbn skips scan" "PORT=/dev/cu.x
FQBN=y:z" "$(STUB_JSON=$TMP/none.json TM_ARDUINO_PORT=/dev/cu.x TM_ARDUINO_FQBN=y:z "$BIN" detect)"

TM_ARDUINO_PORT=/dev/cu.bogus "$BIN" detect >/dev/null 2>&1
check "bogus port fails" "1" "$?"

STUB_JSON="$TMP/none.json" "$BIN" detect >/dev/null 2>&1
check "no boards fails" "1" "$?"

check "compile passes fqbn+dir" "Compiling Sketch for arduino:avr:uno...
STUB-COMPILE compile --fqbn arduino:avr:uno $TMP/Sketch" \
  "$(env -u TM_ARDUINO_FQBN "$BIN" compile "$TMP/Sketch")"
HEARTBEAT_SECS=1 STUB_COMPILE_SLEEP=2.5 "$BIN" compile "$TMP/Sketch" 2>&1 | grep -q "still compiling (1s)"
check "heartbeat signs life" "0" "$?"
HEARTBEAT_SECS=1 STUB_COMPILE_SLEEP=2.5 "$BIN" compile "$TMP/Sketch" 2>&1 | grep -q "STUB-COMPILE"
check "heartbeat passes output through" "0" "$?"
STUB_COMPILE_FAIL=1 "$BIN" compile "$TMP/Sketch" >/dev/null 2>&1
check "heartbeat propagates failure" "7" "$?"

mkdir -p "$TMP/Wrong" && echo x > "$TMP/Wrong/other.ino"
"$BIN" compile "$TMP/Wrong" >/dev/null 2>&1
check "wrong .ino name fails once" "1" "$?"
"$BIN" compile "$TMP/Wrong" 2>&1 | grep -q "must be named exactly"
check "wrong-name hint" "0" "$?"
check "single error only" "1" "$("$BIN" compile "$TMP/Wrong" 2>&1 | grep -c "arduino-build")"
mkdir -p "$TMP/Space" && echo x > "$TMP/Space/Space.ino "
"$BIN" compile "$TMP/Space" 2>&1 | grep -q "trailing spaces"
check "trailing-space hint" "0" "$?"
mkdir -p "$TMP/Empty"
"$BIN" compile "$TMP/Empty" 2>&1 | grep -q "contains: nothing"
check "empty dir lists contents" "0" "$?"

check "monitor needs only port" "STUB-MONITOR monitor -p /dev/cu.usbmodem1 -c baudrate=115200" \
  "$(TM_ARDUINO_BAUD=115200 "$BIN" monitor)"

TM_ARDUINO_BUILDER=idf "$BIN" detect >/dev/null 2>&1
check "idf stub fails clean" "1" "$?"
TM_ARDUINO_BUILDER=idf "$BIN" detect 2>&1 | grep -q "not implemented"
check "idf message" "0" "$?"

TM_ARDUINO_BUILDER=bogus "$BIN" detect >/dev/null 2>&1
check "bogus builder fails" "1" "$?"

check "boards detected tags alias" "ESP32 Family Device|esp32:esp32:esp32_family|alias|/dev/cu.usbmodem1
Ozobot DRVKit|esp32:esp32:ozobot_drvkit|known|/dev/cu.usbmodem1" "$(STUB_JSON=$TMP/alias.json "$BIN" boards detected)"

check "boards installed filters cores" "ESP32 Dev Module|esp32:esp32:esp32
Ozobot DRVKit|esp32:esp32:ozobot_drvkit
Adafruit Feather ESP32|esp32:esp32:feather_esp32" "$("$BIN" boards installed)"
check "boards family agrees" "esp32" "$(STUB_JSON=$TMP/alias.json "$BIN" boards family)"
check "boards family single" "arduino" "$(STUB_JSON=$TMP/one.json "$BIN" boards family)"
check "boards family disagrees" "" "$(STUB_JSON=$TMP/two.json "$BIN" boards family)"
check "boards family none" "" "$(STUB_JSON=$TMP/unmatched.json "$BIN" boards family)"
check "ports shows unknown USB" "/dev/cu.usbserial-0001|?" "$(STUB_JSON=$TMP/unmatched.json "$BIN" ports)"

check "match-board exact fqbn" "esp32:esp32:esp32" "$("$BIN" match-board esp32:esp32:esp32)"
check "match-board substring" "esp32:esp32:ozobot_drvkit" "$("$BIN" match-board Ozobot)"
"$BIN" match-board esp32 >/dev/null 2>&1
check "match-board ambiguous fails" "1" "$?"
"$BIN" match-board esp32 2>&1 | grep -q "3 boards match"
check "match-board counts" "0" "$?"
"$BIN" match-board nonexistent >/dev/null 2>&1
check "match-board no match fails" "1" "$?"
check "match-boards lists all" "ESP32 Dev Module|esp32:esp32:esp32
Adafruit Feather ESP32|esp32:esp32:feather_esp32
Ozobot DRVKit|esp32:esp32:ozobot_drvkit" "$("$BIN" match-boards esp32)"
check "match-boards ranks dev module first" "ESP32 Dev Module|esp32:esp32:esp32" "$("$BIN" match-boards esp32 | head -1)"
check "folk word wroom finds classic" "ESP32 Dev Module|esp32:esp32:esp32" "$("$BIN" match-boards wroom)"
check "folk word ignores case/dashes" "ESP32 Dev Module|esp32:esp32:esp32" "$("$BIN" match-boards WROOM-32)"
check "folk word devkitv1 finds classic" "ESP32 Dev Module|esp32:esp32:esp32" "$("$BIN" match-boards devkitv1)"
check "uninstalled alias skipped, wroom fires" "ESP32 Dev Module|esp32:esp32:esp32" "$("$BIN" match-boards wroom1)"
check "missing keyword file falls back" "" "$(BOARD_KEYWORDS=/nonexistent/kw.txt "$BIN" match-boards wroom)"
check "match-boards empty exit 0" "" "$("$BIN" match-boards zzz)"
"$BIN" match-boards zzz >/dev/null 2>&1
check "match-boards empty exits 0" "0" "$?"
check "match-boards exact fqbn" "Ozobot DRVKit|esp32:esp32:ozobot_drvkit" "$("$BIN" match-boards esp32:esp32:ozobot_drvkit)"

mkdir -p "$TMP/UB" && printf 'void setup() { Serial.begin(115200); }\nvoid loop(){}\n' > "$TMP/UB/UB.ino"
STUB_JSON=$TMP/one.json "$BIN" use-board "$TMP/UB" esp32:esp32:esp32 >/dev/null
check "use-board writes yaml fqbn+port" "default_fqbn: esp32:esp32:esp32
default_port: /dev/cu.usbmodem1
default_port_config:
  baudrate: 115200" "$(cat "$TMP/UB/sketch.yaml")"
check "use-board skips tm_properties" "1" "$([ -f "$TMP/UB/.tm_properties" ] && echo 0 || echo 1)"

mkdir -p "$TMP/UB2" && printf 'void setup(){}\nvoid loop(){}\n' > "$TMP/UB2/UB2.ino"
STUB_JSON=$TMP/two.json "$BIN" use-board "$TMP/UB2" arduino:avr:uno >/dev/null
check "use-board omits port when ambiguous" "default_fqbn: arduino:avr:uno" "$(cat "$TMP/UB2/sketch.yaml")"

mkdir -p "$TMP/UB3" && printf 'void setup() { Serial.begin(9600); }\nvoid loop(){}\n' > "$TMP/UB3/UB3.ino"
printf 'default_fqbn: old:old:old\nprofiles:\n  keepme: [1]\ndefault_port_config:\n  baudrate: 115200\n' > "$TMP/UB3/sketch.yaml"
check "merge replaces baud, keeps profiles" "default_port_config:
  baudrate: 9600" "$(STUB_JSON=$TMP/one.json "$BIN" use-board "$TMP/UB3" esp32:esp32:esp32 >/dev/null; grep -A1 'default_port_config:' "$TMP/UB3/sketch.yaml")"
check "merge keeps profiles block" "0" "$(grep -q 'keepme' "$TMP/UB3/sketch.yaml" && echo 0 || echo 1)"
check "use-board names board friendly" "Board for this sketch: ESP32 Dev Module (saved to sketch.yaml)" "$(STUB_JSON=$TMP/one.json "$BIN" use-board "$TMP/UB" esp32:esp32:esp32)"
mkdir -p "$TMP/UB4" && printf 'void setup(){}\nvoid loop(){}\n' > "$TMP/UB4/UB4.ino"
STUB_JSON=$TMP/unmatched.json "$BIN" use-board "$TMP/UB4" esp32:esp32:esp32 >/dev/null
check "use-board pins unknown USB port" "default_fqbn: esp32:esp32:esp32
default_port: /dev/cu.usbserial-0001" "$(cat "$TMP/UB4/sketch.yaml")"
"$BIN" use-board "$TMP/Empty" esp32:esp32:esp32 >/dev/null 2>&1
check "use-board rejects non-sketch" "1" "$?"
"$BIN" use-board "$TMP/Empty" esp32:esp32:esp32 2>&1 | grep -qF "no .ino file in $TMP/Empty"
check "use-board names the dir" "0" "$?"
STUB_ATTACH_FAIL=1 "$BIN" use-board "$TMP/UB" esp32:esp32:esp32 >/dev/null 2>&1
check "use-board attach failure exits 1" "1" "$?"
STUB_ATTACH_FAIL=1 "$BIN" use-board "$TMP/UB" esp32:esp32:esp32 2>&1 | grep -qF "STUB-ATTACH-BOOM"
check "use-board surfaces attach error" "0" "$?"

echo 'TM_ARDUINO_FQBN = "arduino:avr:uno"' > "$TMP/Sketch/.tm_properties"
check "info full line" "// Board: Uno [arduino:avr:uno] on /dev/cu.usbmodem1 (from sketch .tm_properties)" "$(TM_ARDUINO_FQBN=arduino:avr:uno "$BIN" info "$TMP/Sketch")"
rm "$TMP/Sketch/.tm_properties"
check "info shell var source" "// Board: Uno [arduino:avr:uno] on /dev/cu.usbmodem1 (from TM_ARDUINO_FQBN)" "$(TM_ARDUINO_FQBN=arduino:avr:uno "$BIN" info "$TMP/Sketch")"
check "info auto source" "// Board: Uno [arduino:avr:uno] on /dev/cu.usbmodem1 (from auto-detected)" "$(env -u TM_ARDUINO_FQBN "$BIN" info)"

mkdir -p "$TMP/MR1" && printf 'void setup() { Serial.begin(57600); }\nvoid loop(){}\n' > "$TMP/MR1/MR1.ino"
printf 'default_fqbn: esp32:esp32:esp32\ndefault_port: /dev/cu.yaml1\ndefault_port_config:\n  baudrate: 115200\n' > "$TMP/MR1/sketch.yaml"
check "resolve args beat files" "PORT='/dev/arg'
BAUD='1234'
PORT_GUESS='/dev/arg'
BAUD_GUESS='1234'
SRC_PORT='TextMate setting'
SRC_BAUD='TextMate setting'" "$("$BIN" monitor-resolve "$TMP/MR1" /dev/arg 1234)"
check "begin beats yaml baud" "PORT='/dev/cu.yaml1'
BAUD='57600'
PORT_GUESS='/dev/cu.yaml1'
BAUD_GUESS='57600'
SRC_PORT='sketch.yaml'
SRC_BAUD='Serial.begin()'" "$("$BIN" monitor-resolve "$TMP/MR1")"
eval "$("$BIN" monitor-resolve "$TMP/MR1")" && check "resolve output is eval-safe" "Serial.begin()" "$SRC_BAUD"

mkdir -p "$TMP/MR2" && printf 'void setup(){}\nvoid loop(){}\n' > "$TMP/MR2/MR2.ino"
printf 'default_fqbn: esp32:esp32:esp32\n' > "$TMP/MR2/sketch.yaml"
check "yaml baud when no begin" "BAUD='115200'" "$(printf 'default_fqbn: esp32:esp32:esp32\ndefault_port_config:\n  baudrate: 115200\n' > "$TMP/MR2/sketch.yaml"; "$BIN" monitor-resolve "$TMP/MR2" | grep '^BAUD=')"
printf 'default_fqbn: esp32:esp32:esp32\n' > "$TMP/MR2/sketch.yaml"
check "baud falls back to 115200 guess" "BAUD=''
BAUD_GUESS='115200'" "$("$BIN" monitor-resolve "$TMP/MR2" | grep '^BAUD')"
check "single port auto-picks" "PORT='/dev/cu.usbmodem1'" "$("$BIN" monitor-resolve "$TMP/MR2" | grep '^PORT=')"
check "unknown USB auto-picks" "PORT='/dev/cu.usbserial-0001'" "$(STUB_JSON=$TMP/unmatched.json "$BIN" monitor-resolve "$TMP/MR2" | grep '^PORT=')"
check "multi port asks with guess" "PORT=''
PORT_GUESS='/dev/cu.usbmodem1'" "$(STUB_JSON=$TMP/two.json "$BIN" monitor-resolve "$TMP/MR2" | grep '^PORT')"
check "no dir still detects port" "PORT='/dev/cu.usbmodem1'
BAUD=''
PORT_GUESS='/dev/cu.usbmodem1'
BAUD_GUESS='115200'" "$("$BIN" monitor-resolve | grep -E '^(PORT|BAUD)')"

check "compile uses yaml fqbn" "Compiling MR1 for esp32:esp32:esp32...
STUB-COMPILE compile --fqbn esp32:esp32:esp32 $TMP/MR1" "$(env -u TM_ARDUINO_FQBN -u TM_ARDUINO_PORT "$BIN" compile "$TMP/MR1")"
check "env beats yaml" "Compiling MR1 for arduino:avr:uno...
STUB-COMPILE compile --fqbn arduino:avr:uno $TMP/MR1" "$(TM_ARDUINO_FQBN=arduino:avr:uno "$BIN" compile "$TMP/MR1")"
check "upload announces board+port" "Uploading MR1 to arduino:avr:uno on /dev/cu.test9...
STUB-COMPILE compile --upload -p /dev/cu.test9 --fqbn arduino:avr:uno $TMP/MR1" "$(TM_ARDUINO_FQBN=arduino:avr:uno TM_ARDUINO_PORT=/dev/cu.test9 "$BIN" upload "$TMP/MR1")"
check "info source sketch.yaml" "// Board: ESP32 Dev Module [esp32:esp32:esp32] on /dev/cu.yaml1 (from sketch.yaml)" "$(env -u TM_ARDUINO_FQBN -u TM_ARDUINO_PORT "$BIN" info "$TMP/MR1")"

mkdir -p "$TMP/MR3" && printf 'void setup(){}\nvoid loop(){}\n' > "$TMP/MR3/MR3.ino"
printf 'default_fqbn: esp32:esp32:esp32:UploadSpeed=921600\n' > "$TMP/MR3/sketch.yaml"
check "options pass through to cli" "Compiling MR3 for esp32:esp32:esp32:UploadSpeed=921600...
STUB-COMPILE compile --fqbn esp32:esp32:esp32:UploadSpeed=921600 $TMP/MR3" "$(env -u TM_ARDUINO_FQBN -u TM_ARDUINO_PORT "$BIN" compile "$TMP/MR3")"
check "info strips options for name" "// Board: ESP32 Dev Module [esp32:esp32:esp32:UploadSpeed=921600] on /dev/cu.usbmodem1 (from sketch.yaml)" "$(env -u TM_ARDUINO_FQBN -u TM_ARDUINO_PORT "$BIN" info "$TMP/MR3")"

HTML="$(env -u TM_ARDUINO_FQBN -u TM_ARDUINO_PORT TM_ARDUINO_BAUD=19200 "$BIN" info --html "$TMP/MR1")"
check "html names board" "0" "$(echo "$HTML" | grep -q 'ESP32 Dev Module' && echo 0 || echo 1)"
check "html shows fqbn+port" "0" "$(echo "$HTML" | grep -q 'esp32:esp32:esp32' && echo "$HTML" | grep -q '/dev/cu.yaml1' && echo 0 || echo 1)"
check "html baud override wins" "0" "$(echo "$HTML" | grep -q '19200' && echo "$HTML" | grep -q 'TextMate setting' && echo 0 || echo 1)"
check "html overrides exclude yaml" "0" "$(echo "$HTML" | grep -q 'TM_ARDUINO_BAUD = 19200' && ! echo "$HTML" | grep -q 'TM_ARDUINO_FQBN =' && echo 0 || echo 1)"
check "html dumps yaml" "0" "$(echo "$HTML" | grep -q 'default_fqbn' && echo 0 || echo 1)"
check "html lists detected" "0" "$(echo "$HTML" | grep -q 'cu.usbmodem1' && echo 0 || echo 1)"
check "html unresolved explains" "0" "$(STUB_JSON=$TMP/two.json "$BIN" info --html "$TMP/Empty" | grep -q 'Not ready to build' && echo 0 || echo 1)"

check "ports lists candidates" "/dev/cu.usbmodem1|arduino:avr:uno" "$("$BIN" ports)"
rm -rf /tmp/fake-sketchbook
check "libraries-dir" "/tmp/fake-sketchbook/libraries" "$("$BIN" libraries-dir)"
check "libraries-dir pure query" "1" "$([ -d /tmp/fake-sketchbook/libraries ] && echo 0 || echo 1)"
"$BIN" libraries-dir --create >/dev/null
check "libraries-dir --create" "0" "$([ -d /tmp/fake-sketchbook/libraries ] && echo 0 || echo 1)"
rm -rf /tmp/fake-sketchbook
isours() { ( ARDUINO_BUILD_SOURCED=1; ARDUINO_CLI="$TMP/arduino-cli"; source "$BIN"; is_our_monitor_cmd "$1" "$2" ); }
isours "/opt/homebrew/bin/arduino-cli monitor -p /dev/cu.x -c baudrate=9600" /dev/cu.x
check "own monitor matches" "0" "$?"
isours "/opt/homebrew/bin/arduino-cli monitor -p /dev/cu.x -c baudrate=9600" /dev/cu.y
check "other port rejected" "1" "$?"
isours "screen /dev/cu.x 115200" /dev/cu.x
check "stranger rejected" "1" "$?"
isours "" /dev/cu.x
check "dead pid rejected" "1" "$?"

printf '#!/bin/bash\necho "Homebrew 9.9.9"\n' > "$TMP/fakebrew" && chmod +x "$TMP/fakebrew"
cat > "$TMP/cores_both.json" <<'JSON'
{"platforms": [{"id": "esp32:esp32", "installed_version": "3.3.12"}, {"id": "arduino:avr", "installed_version": "1.8.6"}]}
JSON
echo '{"platforms": []}' > "$TMP/cores_empty.json"

check "cli path" "$TMP/arduino-cli" "$("$BIN" cli)"
ARDUINO_CLI=/nonexistent/arduino-cli "$BIN" compile "$TMP/MR1" >/dev/null 2>&1
check "missing cli fails" "1" "$?"
ARDUINO_CLI=/nonexistent/arduino-cli "$BIN" compile "$TMP/MR1" 2>&1 | grep -q "arduino-cli not found.*brew install arduino-cli"
check "missing cli install hint" "0" "$?"
ARDUINO_CLI=/nonexistent/arduino-cli "$BIN" cli >/dev/null 2>&1
check "cli verb still fails without cli" "1" "$?"

DENV="env -u TM_ARDUINO_FQBN -u TM_ARDUINO_PORT"
check "doctor check healthy" "You are good to go!
Homebrew 9.9.9
arduino-cli 9.9.9
Cores: esp32:esp32 3.3.12 arduino:avr 1.8.6
Board: Uno on /dev/cu.usbmodem1" "$(BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores_both.json STUB_JSON=$TMP/one.json $DENV "$BIN" doctor --check)"
BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores_both.json STUB_JSON=$TMP/one.json $DENV "$BIN" doctor --check >/dev/null 2>&1
check "doctor check healthy exits 0" "0" "$?"
check "doctor check missing cli" "missing: cli core" "$(BREW_BIN=$TMP/fakebrew ARDUINO_CLI=/nonexistent/arduino-cli $DENV "$BIN" doctor --check)"
check "doctor check missing brew" "missing: brew" "$(BREW_BIN=/nonexistent/brew STUB_CORES=$TMP/cores_both.json STUB_JSON=$TMP/one.json $DENV "$BIN" doctor --check)"
check "doctor check no cores" "missing: core" "$(BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores_empty.json STUB_JSON=$TMP/none.json $DENV "$BIN" doctor --check)"
BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores.json STUB_JSON=$TMP/none.json $DENV "$BIN" doctor --check 2>&1 | grep -q "Board: none detected"
check "doctor check no board but cores" "0" "$?"
check "doctor check board needs core" "missing: core:arduino:avr" "$(BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores.json STUB_JSON=$TMP/one.json $DENV "$BIN" doctor --check)"
BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores.json STUB_JSON=$TMP/alias.json $DENV "$BIN" doctor --check 2>&1 | grep -q "unclear.*Select Board"
check "doctor check ambiguous points at Select Board" "0" "$?"
BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores.json STUB_JSON=$TMP/alias.json $DENV "$BIN" doctor --check 2>&1 | grep -q "looks like Ozobot DRVKit, ESP32 Family Device"
check "doctor check names friendly boards" "0" "$?"
BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores.json STUB_JSON=$TMP/alias.json $DENV "$BIN" doctor --check 2>&1 | grep -q "ozobot_drvkit"
check "doctor check hides board IDs" "1" "$?"
BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores.json STUB_JSON=$TMP/unmatched.json $DENV "$BIN" doctor --check 2>&1 | grep -q "unknown device on /dev/cu.usbserial-0001.*Select Board"
check "doctor check unknown USB points at Select Board" "0" "$?"
TM_ARDUINO_PORT=/dev/cu.stale9 BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores.json STUB_JSON=$TMP/one.json env -u TM_ARDUINO_FQBN "$BIN" doctor --check 2>&1 | grep -q "is empty"
check "doctor check stale port" "0" "$?"
DFLOW="$(BREW_BIN=/nonexistent/brew ARDUINO_CLI=/nonexistent/arduino-cli STUB_CORES=$TMP/cores_empty.json STUB_JSON=$TMP/none.json RLWRAP_BIN=/nonexistent/rlwrap DOCTOR_DRYRUN=1 $DENV "$BIN" doctor 2>/dev/null <<'EOF'
y
y
3
n
EOF
)"
check "doctor dryrun brew installer" "0" "$(echo "$DFLOW" | grep -q 'would run: /bin/bash -c' && echo 0 || echo 1)"
check "doctor dryrun cli install" "0" "$(echo "$DFLOW" | grep -q 'would run: brew install arduino-cli' && echo 0 || echo 1)"
check "doctor dryrun core installs" "0" "$(echo "$DFLOW" | grep -q 'would run: arduino-cli core update-index' && echo "$DFLOW" | grep -q 'would run: arduino-cli core install arduino:avr' && echo "$DFLOW" | grep -q 'would run: arduino-cli core install esp32:esp32' && echo 0 || echo 1)"
check "doctor dryrun says dry run" "0" "$(echo "$DFLOW" | grep -q 'dry run -- nothing was installed' && echo 0 || echo 1)"
UFLOW="$(BREW_BIN=$TMP/fakebrew STUB_CORES=$TMP/cores.json STUB_JSON=$TMP/unmatched.json RLWRAP_BIN=/nonexistent/rlwrap DOCTOR_DRYRUN=1 $DENV "$BIN" doctor 2>/dev/null <<'EOF'
n
EOF
)"
check "doctor walkthrough unknown USB" "0" "$(echo "$UFLOW" | grep -q 'Unknown device on /dev/cu.usbserial-0001 -- run Select Board' && echo 0 || echo 1)"
printf 'n\n' | BREW_BIN=/nonexistent/brew DOCTOR_DRYRUN=1 $DENV "$BIN" doctor >/dev/null 2>&1
check "doctor decline quits" "1" "$?"
"$BIN" version 2>&1 | grep -q "^arduino-build 1.0"
check "version prints" "0" "$?"

check "listall cached" "0" "$([ -f "$TMP/cache/arduino-listall-cache.json" ] && echo 0 || echo 1)"
echo "not json anymore" > "$TMP/known.json"
check "cache survives CLI breakage" "PORT=/dev/cu.usbmodem1
FQBN=arduino:avr:uno" "$(env -u TM_ARDUINO_FQBN -u TM_ARDUINO_PORT "$BIN" detect)"

exit $FAIL
