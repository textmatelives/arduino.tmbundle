#!/bin/sh
# Monitor launcher tests: rlwrap branch vs plain branch + tip.
# Stubbed arduino-build/cli, no hardware, no network.
SUPPORT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/arduino-monitor-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
check() { # name expected actual
	if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS $1";
	else FAIL=$((FAIL+1)); echo "FAIL $1 -- expected [$2] got [$3]"; fi
}

# Fake support tree: Monitor resolves arduino-build via its own dirname.
mkdir -p "$TMP/fakebin" "$TMP/monsupport/bin"
cp "$SUPPORT/Monitor" "$TMP/monsupport/Monitor"
cp "$SUPPORT/bin/port_health" "$TMP/monsupport/bin/port_health"
chmod +x "$TMP/monsupport/bin/port_health"
cat > "$TMP/monsupport/bin/arduino-build" <<'EOF'
#!/bin/sh
case "$1" in
monitor-resolve) printf "PORT='${STUB_PORT-/dev/cu.test1}'\nBAUD='${STUB_BAUD-115200}'\nPORT_GUESS='${STUB_PGUESS-/dev/cu.test1}'\nBAUD_GUESS='${STUB_BGUESS-115200}'\nSRC_PORT='test'\nSRC_BAUD='test'\n" ;;
cli) command -v arduino-cli ;;
esac
EOF
chmod +x "$TMP/monsupport/bin/arduino-build"
printf '#!/bin/sh\necho "CLI CALLED: $@"\n' > "$TMP/fakebin/arduino-cli"
chmod +x "$TMP/fakebin/arduino-cli"
printf '#!/bin/sh\necho "RLWRAP CALLED: $@"\n' > "$TMP/fakebin/rlwrap"
chmod +x "$TMP/fakebin/rlwrap"
export HOME="$TMP/fakehome" && mkdir -p "$HOME"
rm -f /tmp/arduino-tmbundle-monitor.cu.test1.pid

# rlwrap missing: tip printed, plain cli exec'd.
mv "$TMP/fakebin/rlwrap" "$TMP/rlwrap.hidden"
OUT="$(PATH="$TMP/fakebin:/usr/bin:/bin" "$TMP/monsupport/Monitor" "$TMP" 2>&1)"
check "tip shown without rlwrap" "Tip: brew install rlwrap for up-arrow command history." "$(printf '%s\n' "$OUT" | grep '^Tip:')"
check "plain cli exec'd" "CLI CALLED: monitor -p /dev/cu.test1 -c baudrate=115200" "$(printf '%s\n' "$OUT" | grep '^CLI CALLED:')"

# rlwrap present: no tip, rlwrap wraps the cli.
mv "$TMP/rlwrap.hidden" "$TMP/fakebin/rlwrap"
OUT="$(PATH="$TMP/fakebin:/usr/bin:/bin" "$TMP/monsupport/Monitor" "$TMP" 2>&1)"
check "no tip with rlwrap" "" "$(printf '%s\n' "$OUT" | grep '^Tip:' || true)"
check "rlwrap wraps cli" "RLWRAP CALLED: -H $TMP/fakehome/.arduino-monitor-history $TMP/fakebin/arduino-cli monitor -p /dev/cu.test1 -c baudrate=115200" "$(printf '%s\n' "$OUT" | grep '^RLWRAP CALLED:')"

# Plain branch again for the no-prompt assertions.
mv "$TMP/fakebin/rlwrap" "$TMP/rlwrap.hidden2"

# No baud anywhere: default the guess, announce, never prompt.
OUT="$(STUB_BAUD="" STUB_BGUESS="115200" PATH="$TMP/fakebin:/usr/bin:/bin" "$TMP/monsupport/Monitor" "$TMP" </dev/null 2>&1)"
check "baud defaults silently" "CLI CALLED: monitor -p /dev/cu.test1 -c baudrate=115200" "$(printf '%s\n' "$OUT" | grep '^CLI CALLED:')"
check "baud announces default" "Baud 115200 (default -- no sketch here; bring your sketch to the front and re-run for its rate)" "$(printf '%s\n' "$OUT" | grep '^Baud ')"
check "no baud prompt" "" "$(printf '%s\n' "$OUT" | grep 'Baud rate?' || true)"

# Sketch dir without baud: message points at Serial.begin.
mkdir -p "$TMP/sketchdir" && touch "$TMP/sketchdir/Sketch.ino"
OUT="$(STUB_BAUD="" STUB_BGUESS="115200" PATH="$TMP/fakebin:/usr/bin:/bin" "$TMP/monsupport/Monitor" "$TMP/sketchdir" </dev/null 2>&1)"
check "baud message names Serial.begin" "Baud 115200 (default -- add Serial.begin(...) to set it)" "$(printf '%s\n' "$OUT" | grep '^Baud ')"

# No port at all: fail loud, no prompt.
OUT="$(STUB_PORT="" STUB_PGUESS="" PATH="$TMP/fakebin:/usr/bin:/bin" "$TMP/monsupport/Monitor" "$TMP" </dev/null 2>&1)"
check "no port fails loud" "No port -- plug a board in." "$(printf '%s\n' "$OUT" | grep '^No port')"
check "no port prompt" "" "$(printf '%s\n' "$OUT" | grep 'Port? ' || true)"

# Several ports: keep the prompt, Enter accepts the guess.
OUT="$(printf '\n' | STUB_PORT="" STUB_PGUESS="/dev/cu.guess" PATH="$TMP/fakebin:/usr/bin:/bin" "$TMP/monsupport/Monitor" "$TMP" 2>&1)"
check "multi-port keeps prompt" "CLI CALLED: monitor -p /dev/cu.guess -c baudrate=115200" "$(printf '%s\n' "$OUT" | grep '^CLI CALLED:')"
rm -f /tmp/arduino-tmbundle-monitor.cu.guess.pid

# Port held by a stranger: refuse, name the pid, launch nothing.
HOLD="$TMP/held"; sleep 8 >"$HOLD" 2>/dev/null & HPID=$!
OUT="$(STUB_PORT="$HOLD" PATH="$TMP/fakebin:/usr/bin:/bin" "$TMP/monsupport/Monitor" "$TMP" </dev/null 2>&1)"
check "held port refuses" "0" "$(printf '%s\n' "$OUT" | grep -q "is busy (held by pid $HPID" && echo 0 || echo 1)"
check "held port launches nothing" "" "$(printf '%s\n' "$OUT" | grep '^CLI CALLED:' || true)"
echo "$HPID" > /tmp/arduino-tmbundle-monitor.held.pid
OUT="$(STUB_PORT="$HOLD" PATH="$TMP/fakebin:/usr/bin:/bin" "$TMP/monsupport/Monitor" "$TMP" </dev/null 2>&1)"
check "own monitor named" "0" "$(printf '%s\n' "$OUT" | grep -q 'already open in another Arduino monitor window' && echo 0 || echo 1)"
kill $HPID 2>/dev/null || true
wait $HPID 2>/dev/null || true
rm -f /tmp/arduino-tmbundle-monitor.held.pid

# Wedged adapter: say so and do not start the monitor.
cat > "$TMP/monsupport/bin/port_health" << 'EOF'
#!/bin/sh
echo verdict=wedged
echo bytes=12000
echo seconds=0.250
echo rate=48000
echo limit=11520
EOF
chmod +x "$TMP/monsupport/bin/port_health"
OUT="$(PATH="$TMP/fakebin:/usr/bin:/bin" "$TMP/monsupport/Monitor" "$TMP" </dev/null 2>&1)"
check "wedge names the port" "The adapter on /dev/cu.test1 is wedged." "$(printf '%s\n' "$OUT" | grep '^The adapter')"
check "wedge says unplug" "Unplug the board and plug it back in, then run Monitor again." "$(printf '%s\n' "$OUT" | grep '^Unplug')"
check "wedge does not launch" "" "$(printf '%s\n' "$OUT" | grep '^CLI CALLED:' || true)"

rm -f /tmp/arduino-tmbundle-monitor.cu.test1.pid
echo "--- $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
