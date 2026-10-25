#!/bin/bash
# Refresh Support/language_urls.txt from the live Arduino language reference.
# Takes a few minutes (fetches the site's page index, then HEAD-checks every
# route so the Lookup command can never open a 404). Run yearly, or when
# lookups start missing new keywords.
set -u
cd "$(dirname "$0")/.." || exit 1
SRC="https://docs.arduino.cc/language-reference/page-data/index/page-data.json"
TMP="$(mktemp -d -t arduino-langurls)" || exit 1
trap 'rm -rf "$TMP"' EXIT

echo "Fetching page index..." >&2
curl -sSL --max-time 120 -o "$TMP/index.json" "$SRC" || { echo "update failed: fetch failed"; exit 1; }
python3 - "$TMP/index.json" > "$TMP/urls.txt" <<'EOF'
import json, re, sys
d = json.load(open(sys.argv[1]))
slugs = sorted(set(m.strip('"').rstrip('/') for m in re.findall(r'"/en/[a-zA-Z0-9/_.-]+', json.dumps(d))))
if len(slugs) < 200:
    sys.exit("update failed: only %d slugs, site structure must have changed" % len(slugs))
for s in slugs:
    print('https://docs.arduino.cc/language-reference' + s + '/')
EOF
[ $? -eq 0 ] || exit 1
echo "Checking $(wc -l < "$TMP/urls.txt" | tr -d ' ') pages..." >&2
xargs -P8 -I{} curl -sL -o /dev/null --max-time 15 -w "%{http_code} %{url_effective}\n" {} \
	< "$TMP/urls.txt" > "$TMP/verify.txt"
grep '^000' "$TMP/verify.txt" | awk '{print $2}' > "$TMP/retry.txt" || true
if [ -s "$TMP/retry.txt" ]; then
	echo "Retrying $(wc -l < "$TMP/retry.txt" | tr -d ' ') timeouts..." >&2
	xargs -P4 -I{} curl -sL -o /dev/null --max-time 30 -w "%{http_code} %{url_effective}\n" {} \
		< "$TMP/retry.txt" > "$TMP/verify2.txt"
else
	: > "$TMP/verify2.txt"
fi
python3 - "$TMP/verify.txt" "$TMP/verify2.txt" > Support/language_urls.txt <<'EOF'
import re, sys
from collections import defaultdict
good = set()
for f in sys.argv[1:]:
    for line in open(f):
        code, url = line.split(' ', 1)
        if code == '200':
            m = re.search(r'/language-reference(/.+?)/?$', url.strip())
            if m:
                good.add(m.group(1).rstrip('/'))
by_key = defaultdict(list)
for s in good:
    by_key[s.rsplit('/', 1)[-1].lower()].append(s)
# Curated aliases for grouped pages (constants) and multi-word lookups.
ALIASES = {
    'high': '/en/variables/constants/highLow',
    'low': '/en/variables/constants/highLow',
    'true': '/en/variables/constants/trueFalse',
    'false': '/en/variables/constants/trueFalse',
    'input': '/en/variables/constants/inputOutputPullup',
    'output': '/en/variables/constants/inputOutputPullup',
    'input_pullup': '/en/variables/constants/inputOutputPullup',
    'led_builtin': '/en/variables/constants/ledbuiltin',
    'switch': '/en/structure/control-structure/switchCase',
    'case': '/en/structure/control-structure/switchCase',
    'do': '/en/structure/control-structure/doWhile',
}
final, dropped = {}, []
for k, v in sorted(by_key.items()):
    if len(v) == 1:
        final[k] = v[0]
    else:
        ser = [s for s in v if s == '/en/functions/communication/serial'
               or s.startswith('/en/functions/communication/serial/')]
        if len(ser) == 1:
            final[k] = ser[0]  # ambiguous? Serial wins (most common object)
        else:
            dropped.append(k)
print('# stem -> language-reference path. Generated %s by' % __import__('datetime').date.today().isoformat())
print('# Support/update_language_urls.sh from the live docs; every path below')
print('# returned HTTP 200 when generated. Ambiguous stems resolve to Serial,')
print('# otherwise they are left out (Lookup falls back to the index).')
for k, v in sorted(final.items()):
    print('%s %s' % (k, v))
print('# --- curated aliases (grouped/renamed pages) ---')
for k, v in sorted(ALIASES.items()):
    if v in good:
        print('%s %s' % (k, v))
    else:
        sys.stderr.write('warning: alias target gone, skipped: %s -> %s\n' % (k, v))
sys.stderr.write('%d entries, %d ambiguous dropped: %s\n'
                 % (len(final) + len(ALIASES), len(dropped), ', '.join(sorted(dropped))))
EOF
echo "Wrote Support/language_urls.txt" >&2
