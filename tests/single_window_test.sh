#!/bin/sh
# Single-window test: one fuzzel invocation where the first Enter returns a
# model row (switch model, reopen) and the second returns source text.
set -eu
cd "$(dirname "$0")/.."

PORT=18771
T=$(mktemp -d)
trap 'kill $SRV 2>/dev/null || true; rm -rf "$T"' EXIT INT TERM

mkdir -p "$T/bin" "$T/home"
cat > "$T/bin/fuzzel" <<'EOF'
#!/bin/sh
cat > /dev/null              # stdin rows
n=$(cat "$FZ_COUNT" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$FZ_COUNT"
if [ "$n" = 1 ]; then
    printf 'google/gemma-4-31b-it:free\tGoogle: Gemma 4 31B\t262K'
else
    printf '你好世界'
fi
EOF
chmod +x "$T/bin/fuzzel"
: > "$T/count"

python3 - "$PORT" "$T/req.log" <<'PY' &
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

LOG = sys.argv[2]

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        raw = json.dumps({"data": [
            {"id": "google/gemma-4-31b-it:free", "name": "Google: Gemma 4 31B",
             "context_length": 262144,
             "pricing": {"prompt": "0", "completion": "0"},
             "architecture": {"output_modalities": ["text"]}},
        ]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_LOG(self):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        with open(LOG, "a") as f:
            f.write(json.dumps(body) + "\n")
        raw = json.dumps({"choices": [{"message": {"content": "Hello world"}}]}).encode()
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
openrouter_api_key = "k"
source_lang = "zh"
target_lang = "en"
model = ""
models_ttl_secs = 0
base_url = "http://127.0.0.1:$PORT"
EOF

HOME="$T/home" FZ_COUNT="$T/count" PATH="$T/bin:$PATH" \
  HT_CONFIG="$T/cfg.toml" ./hotkey-translation > "$T/out.txt"

fail() { echo "FAIL: $1" >&2; exit 1; }

[ "$(cat "$T/out.txt")" = "Hello world" ] || fail "output: $(cat "$T/out.txt")"
[ "$(cat "$T/count")" = "2" ] || fail "expected two window rounds, got $(cat "$T/count")"
[ "$(cat "$T/home/.cache/hotkey-translation/last_model")" = "google/gemma-4-31b-it:free" ] \
  || fail "model pick not persisted"
python3 - "$T/req.log" <<'PY' || fail "request used the wrong model or text"
import json, sys
req = json.loads(open(sys.argv[1]).readlines()[-1])
assert req["model"] == "google/gemma-4-31b-it:free", req["model"]
assert req["messages"][-1]["content"] == "你好世界", req["messages"][-1]
PY
echo "PASS: one window, model row switches model, text row translates"
