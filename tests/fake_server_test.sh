#!/bin/sh
# End to end test with a fake OpenRouter server. No key, no network.
# Bypasses both fuzzel prompts via ZH2EN_TEXT/ZH2EN_MODEL, runs zh2en-hotkey
# against the fake, asserts clipboard holds the English result.
set -eu
cd "$(dirname "$0")/.."

PORT=18731
TMPDIR_FIX=$(mktemp -d)
trap 'rm -rf "$TMPDIR_FIX"; kill $SRV_PID 2>/dev/null || true' EXIT INT TERM

cat > "$TMPDIR_FIX/cfg.toml" <<EOF
openrouter_api_key = "test-key"
model = "test-model"
models = ["test-model", "other-model:free"]
timeout_secs = 10
base_url = "http://127.0.0.1:$PORT"
EOF

python3 - "$PORT" <<'PY' &
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        assert body.get("model") == "test-model", body
        msgs = body.get("messages", [])
        assert any(m.get("role") == "system" for m in msgs), body
        assert msgs[-1].get("content") == "你好世界", body
        out = {"choices": [{"message": {"content": "Hello world"}}]}
        raw = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
    def log_message(self, *a):
        pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
SRV_PID=$!
sleep 0.5

wl-copy --clear; wl-copy --primary --clear
sleep 0.3
ZH2EN_CONFIG="$TMPDIR_FIX/cfg.toml" ZH2EN_TEXT="你好世界" ZH2EN_MODEL="test-model" \
  ./zh2en-hotkey > "$TMPDIR_FIX/out.txt"
GOT=$(wl-paste --no-newline)
if [ "$GOT" = "Hello world" ]; then
    echo "PASS: clipboard holds English result: $GOT"
else
    echo "FAIL: clipboard = [$GOT], script out = [$(cat "$TMPDIR_FIX/out.txt")]" >&2
    exit 1
fi
