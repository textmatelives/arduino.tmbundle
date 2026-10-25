#!/bin/sh
# Classifier only. No port is opened.
SUPPORT="$(cd "$(dirname "$0")/.." && pwd)"
HP="$SUPPORT/bin/port_health"
PASS=0; FAIL=0
check() {
	if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS $1";
	else FAIL=$((FAIL+1)); echo "FAIL $1 -- expected [$2] got [$3]"; fi
}
run() { # baud seconds  -- bytes on stdin via the next file
	"$HP" classify --baud "$1" --seconds "$2" < "$3"
}

TMP="$(mktemp -d /tmp/arduino-port-health.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

printf 'Intensity? 0-255, on, off\r\nShowing intensity=128\n' > "$TMP/text"
check "sketch text is ok" "ok" "$(run 115200 0.25 "$TMP/text")"

: > "$TMP/empty"
check "silence is ok" "ok" "$(run 115200 0.25 "$TMP/empty")"

python3 - "$TMP/flood" << 'PY'
import sys
open(sys.argv[1], "wb").write(b"\x00\x80" * 6000)
PY
check "00 80 flood is wedged" "wedged" "$(run 115200 0.25 "$TMP/flood")"

python3 - "$TMP/slow" << 'PY'
import sys
open(sys.argv[1], "wb").write(b"\x00\x80" * 40)
PY
check "slow 00 80 is not a wedge" "garbage" "$(run 115200 0.25 "$TMP/slow")"

python3 - "$TMP/junk" << 'PY'
import sys
open(sys.argv[1], "wb").write(bytes([0xff, 0xfe, 0xc3, 0x01]) * 30)
PY
check "slow junk is garbage" "garbage" "$(run 115200 0.25 "$TMP/junk")"

python3 - "$TMP/mixed" << 'PY'
import sys
msg = b"Showing intensity=128\nIntensity? 0-255, on, off\r\n"
open(sys.argv[1], "wb").write(msg + b"\x00\x80" * 4)
PY
check "text with a little noise is ok" "ok" "$(run 115200 0.25 "$TMP/mixed")"

echo "--- $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
