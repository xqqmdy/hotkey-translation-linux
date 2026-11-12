#!/bin/sh
# Cache behavior: cold fetch caches the raw payload, a warm cache skips the
# network, filters run on read, and a stale cache is served immediately while
# a background refresh rewrites it.
set -eu
cd "$(dirname "$0")/.."

PORT=18811
T=$(mktemp -d)
trap 'kill $SRV 2>/dev/null || true; rm -rf "$T"' EXIT INT TERM

mkdir -p "$T/home"
: > "$T/hits.log"
python3 - "$PORT" "$T/hits.log" <<'PY' &
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys
LOG = sys.argv[2]

ROWS = {"data": [
    {"id": "google/gemma-4-31b-it:free", "name": "Google: Gemma 4 31B",
     "context_length": 262144,
     "pricing": {"prompt": "0", "completion": "0"},
     "architecture": {"output_modalities": ["text"]}},
    {"id": "vendor/paid", "name": "Paid", "context_length": 8000,
     "pricing": {"prompt": "0.000001", "completion": "0.000002"},
     "architecture": {"output_modalities": ["text"]}},
    {"id": "vendor/music:free", "name": "Music", "context_length": 1000,
     "pricing": {"prompt": "0", "completion": "0"},
     "architecture": {"output_modalities": ["text", "audio"]}},
]}

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(LOG, "a") as f:
            f.write("hit\n")
        raw = json.dumps(ROWS).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, *a):
        pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
SRV=$!
sleep 0.5

CFG="$T/cfg.toml"
cat > "$CFG" <<EOF
openrouter_api_key = "k"
model = "google/gemma-4-31b-it:free"
models_ttl_secs = 86400
base_url = "http://127.0.0.1:$PORT"
EOF
CACHE="$T/home/.cache/hotkey-translation/models.json"
fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. cold: one fetch, raw payload cached
ROWS=$(HOME="$T/home" HT_CONFIG="$CFG" ./hotkey-translation --list-models)
echo "$ROWS" | grep -q "gemma" || fail "cold list missing the free text model"
[ -s "$CACHE" ] || fail "no cache written"
grep -q '"data"' "$CACHE" || fail "cache does not hold the raw payload"
grep -q '"models"' "$CACHE" && fail "cache still holds filtered models"

# 2. warm: no extra fetch
BEFORE=$(wc -l < "$T/hits.log")
ROWS=$(HOME="$T/home" HT_CONFIG="$CFG" ./hotkey-translation --list-models)
AFTER=$(wc -l < "$T/hits.log")
[ "$BEFORE" = "$AFTER" ] || fail "warm cache fetched again ($BEFORE -> $AFTER)"

# 3. filters applied on read: paid and audio rows never appear
echo "$ROWS" | grep -q "paid" && fail "paid model leaked"
echo "$ROWS" | grep -q "music" && fail "audio model leaked"

# 4. stale: served immediately, refreshed in the background
python3 - "$CACHE" <<'PY'
import json, sys, time
p = sys.argv[1]
d = json.load(open(p))
d["fetched"] = time.time() - 10**6
json.dump(d, open(p, "w"))
PY
BEFORE=$(wc -l < "$T/hits.log")
START=$(date +%s%N)
ROWS=$(HOME="$T/home" HT_CONFIG="$CFG" ./hotkey-translation --list-models)
END=$(date +%s%N)
MS=$(( (END - START) / 1000000 ))
echo "$ROWS" | grep -q "gemma" || fail "stale cache not served"
[ "$MS" -lt 1500 ] || fail "stale cache blocked ${MS}ms"
sleep 1.5
AFTER=$(wc -l < "$T/hits.log")
[ "$AFTER" -gt "$BEFORE" ] || fail "no background refresh"
python3 - "$CACHE" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1]))
assert time.time() - d["fetched"] < 300, "cache not refreshed"
PY
echo "PASS: raw payload cache, warm hit, read-time filters, stale served in ${MS}ms then refreshed"
