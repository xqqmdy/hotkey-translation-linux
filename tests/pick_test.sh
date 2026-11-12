#!/bin/sh
# --pick test: stub rofi returns a model row; the id must be persisted.
set -eu
cd "$(dirname "$0")/.."

PORT=18802
T=$(mktemp -d)
trap 'kill $SRV 2>/dev/null || true; rm -rf "$T"' EXIT INT TERM

mkdir -p "$T/bin" "$T/home"
cat > "$T/bin/rofi" <<'EOF'
#!/bin/sh
cat > "$FZ_STDIN"
printf 'Google: Gemma 4 31B  262K  [google/gemma-4-31b-it:free]'
EOF
chmod +x "$T/bin/rofi"

python3 - "$PORT" <<'PY' &
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        raw = json.dumps({"data": [
            {"id": "google/gemma-4-31b-it:free", "name": "Google: Gemma 4 31B",
             "context_length": 262144,
             "pricing": {"prompt": "0", "completion": "0"},
             "architecture": {"output_modalities": ["text"]}},
            {"id": "vendor/paid", "name": "Paid", "context_length": 8000,
             "pricing": {"prompt": "0.000001", "completion": "0.000002"},
             "architecture": {"output_modalities": ["text"]}},
        ]}).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(raw)))
        self.end_headers(); self.wfile.write(raw)
    def log_message(self, *a):
        pass
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
SRV=$!
sleep 0.5

cat > "$T/cfg.toml" <<EOF
openrouter_api_key = "k"
model = ""
models_ttl_secs = 0
base_url = "http://127.0.0.1:$PORT"
EOF

HOME="$T/home" FZ_STDIN="$T/stdin" PATH="$T/bin:$PATH" \
  HT_CONFIG="$T/cfg.toml" ./hotkey-translation --pick > "$T/out.txt"

fail() { echo "FAIL: $1" >&2; exit 1; }
[ "$(cat "$T/out.txt")" = "google/gemma-4-31b-it:free" ] || fail "picked: $(cat "$T/out.txt")"
[ "$(cat "$T/home/.cache/hotkey-translation/last_model")" = "google/gemma-4-31b-it:free" ] \
  || fail "pick not persisted"
grep -q "vendor/paid" "$T/stdin" && fail "paid model leaked into the list"
echo "PASS: --pick persists the chosen model, free filter intact"
