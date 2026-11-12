#!/bin/sh
# Language direction test: fake /chat/completions logs the system prompt, so
# we can assert source_lang/target_lang land in it. No rofi, no key.
set -eu
cd "$(dirname "$0")/.."

PORT=18761
T=$(mktemp -d)
trap 'kill $SRV 2>/dev/null || true; rm -rf "$T"' EXIT INT TERM

python3 - "$PORT" "$T/req.log" <<'PY' &
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

LOG = sys.argv[2]

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        with open(LOG, "a") as f:
            f.write(json.dumps(body) + "\n")
        raw = json.dumps({"choices": [{"message": {"content": "ok"}}]}).encode()
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

run() { # src dst text
    cat > "$T/cfg.toml" <<EOF
openrouter_api_key = "k"
source_lang = "$1"
target_lang = "$2"
model = "m"
base_url = "http://127.0.0.1:$PORT"
EOF
    HT_CONFIG="$T/cfg.toml" HT_TEXT="$3" ./hotkey-translation >/dev/null
}

fail() { echo "FAIL: $1" >&2; exit 1; }

: > "$T/req.log"
run ja en "こんにちは"
SYSTEM=$(python3 -c "import json; print(json.loads(open('$T/req.log').readlines()[-1])['messages'][0]['content'])")
echo "$SYSTEM" | grep -q "Japanese" || fail "ja source missing: $SYSTEM"
echo "$SYSTEM" | grep -q "idiomatic English" || fail "en target missing: $SYSTEM"

run en zh "hello"
SYSTEM=$(python3 -c "import json; print(json.loads(open('$T/req.log').readlines()[-1])['messages'][0]['content'])")
echo "$SYSTEM" | grep -q "user's English text" || fail "en source missing: $SYSTEM"
echo "$SYSTEM" | grep -q "idiomatic Chinese" || fail "zh target missing: $SYSTEM"

# Defaults when unset: zh -> en
cat > "$T/cfg.toml" <<EOF
openrouter_api_key = "k"
model = "m"
base_url = "http://127.0.0.1:$PORT"
EOF
HT_CONFIG="$T/cfg.toml" HT_TEXT="你好" ./hotkey-translation >/dev/null
SYSTEM=$(python3 -c "import json; print(json.loads(open('$T/req.log').readlines()[-1])['messages'][0]['content'])")
echo "$SYSTEM" | grep -q "user's Chinese text" || fail "default source not zh: $SYSTEM"
echo "$SYSTEM" | grep -q "idiomatic English" || fail "default target not en: $SYSTEM"

echo "PASS: source/target language configurable, defaults zh -> en"
