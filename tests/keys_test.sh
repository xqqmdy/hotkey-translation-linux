#!/bin/sh
# Window-loop test with a stub rofi:
#   1) exits 10 (the Alt+m custom key)      -> model window opens
#   2) returns a model row                   -> model saved
#   3) returns the typed text                -> translated
set -eu
cd "$(dirname "$0")/.."

PORT=18801
T=$(mktemp -d)
trap 'kill $SRV 2>/dev/null || true; rm -rf "$T"' EXIT INT TERM

mkdir -p "$T/bin" "$T/home"
cat > "$T/bin/rofi" <<'EOF'
#!/bin/sh
cat > /dev/null
n=$(cat "$FZ_COUNT" 2>/dev/null || echo 0)
n=$((n + 1)); echo "$n" > "$FZ_COUNT"
case "$n" in
  1) exit 10 ;;
  2) printf 'NVIDIA: Nemotron 3 Nano Omni  256K  [nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free]' ;;
  *) printf '你好世界' ;;
esac
EOF
chmod +x "$T/bin/rofi"

python3 - "$PORT" "$T/req.log" <<'PY' &
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys
LOG = sys.argv[2]
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        raw = json.dumps({"data": [
            {"id": "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
             "name": "NVIDIA: Nemotron 3 Nano Omni", "context_length": 256000,
             "pricing": {"prompt": "0", "completion": "0"},
             "architecture": {"output_modalities": ["text"]}},
            {"id": "google/gemma-4-31b-it:free", "name": "Google: Gemma 4 31B",
             "context_length": 262144,
             "pricing": {"prompt": "0", "completion": "0"},
             "architecture": {"output_modalities": ["text"]}},
        ]}).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(raw)))
        self.end_headers(); self.wfile.write(raw)
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        with open(LOG, "a") as f:
            f.write(json.dumps(body) + "\n")
        raw = json.dumps({"choices": [{"message": {"content": "Hello world"}}]}).encode()
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
[ "$(cat "$T/count")" = "3" ] || fail "expected 3 window rounds, got $(cat "$T/count")"
[ "$(cat "$T/home/.cache/hotkey-translation/last_model")" = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free" ] \
  || fail "model pick not persisted"
python3 - "$T/req.log" <<'PY' || fail "request used the wrong model or text"
import json, sys
req = json.loads(open(sys.argv[1]).readlines()[-1])
assert req["model"] == "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free", req["model"]
assert req["messages"][-1]["content"] == "你好世界", req["messages"][-1]
PY
echo "PASS: Alt+m opens models, pick returns to the text window, text translates"
