#!/bin/sh
# Model picker test: fake /models + stub fuzzel. Asserts the tab-column
# format, the --with-nth/--accept-nth wiring, and that the pick is persisted.
set -eu
cd "$(dirname "$0")/.."

PORT=18751
T=$(mktemp -d)
trap 'kill $SRV 2>/dev/null || true; rm -rf "$T"' EXIT INT TERM

mkdir -p "$T/bin" "$T/home/.cache/hotkey-translation"
cat > "$T/bin/fuzzel" <<'EOF'
#!/bin/sh
args="$*"
echo "$args" > "$FZ_ARGS"
stdin=$(cat)
printf '%s' "$stdin" > "$FZ_STDIN"
# accept-nth=1 semantics: return the first tab column of the first line
printf '%s' "$stdin" | head -1 | cut -f1
EOF
chmod +x "$T/bin/fuzzel"

python3 - "$PORT" <<'PY' &
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

MODELS = {"data": [
    {"id": "vendor/paid-model", "name": "Paid", "context_length": 8000,
     "pricing": {"prompt": "0.000001", "completion": "0.000002"},
     "architecture": {"output_modalities": ["text"]}},
    {"id": "vendor/free-chat:free", "name": "Free Chat", "context_length": 262144,
     "pricing": {"prompt": "0", "completion": "0"},
     "architecture": {"output_modalities": ["text"]}},
    {"id": "vendor/free-music:free", "name": "Free Music", "context_length": 1000,
     "pricing": {"prompt": "0", "completion": "0"},
     "architecture": {"output_modalities": ["text", "audio"]}},
]}

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        raw = json.dumps(MODELS).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
    def log_message(self, *a):
        pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
SRV=$!
sleep 0.5

cat > "$T/cfg.toml" <<EOF
openrouter_api_key = "test-key"
model = ""
models_ttl_secs = 0
base_url = "http://127.0.0.1:$PORT"
EOF

HOME="$T/home" FZ_ARGS="$T/args" FZ_STDIN="$T/stdin" \
  PATH="$T/bin:$PATH" HT_CONFIG="$T/cfg.toml" \
  ./hotkey-translation --pick > "$T/out.txt"

fail() { echo "FAIL: $1" >&2; exit 1; }

grep -q "with-nth {2}" "$T/args" || fail "with-nth columns missing: $(cat "$T/args")"
grep -q "accept-nth 1" "$T/args" || fail "accept-nth 1 missing: $(cat "$T/args")"
grep -q "tabs 2" "$T/args" || fail "--tabs missing: $(cat "$T/args")"
[ "$(cat "$T/out.txt")" = "vendor/free-chat:free" ] || fail "picked $(cat "$T/out.txt")"
[ "$(cat "$T/home/.cache/hotkey-translation/last_model")" = "vendor/free-chat:free" ] || fail "pick not persisted"
grep -q "vendor/free-music:free" "$T/stdin" && fail "audio model leaked into the list"
grep -q "vendor/paid-model" "$T/stdin" && fail "paid model leaked into the list"
echo "PASS: live free list, tab columns, pick persisted"
