#!/bin/sh
# Clipboard fallback: when the Wayland tools fail, the X11 tools must be used
# for both read and write. Stubs stand in for both families.
set -eu
cd "$(dirname "$0")/.."

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/bin"

cat > "$T/bin/wl-paste" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$T/bin/wl-copy" <<'EOF'
#!/bin/sh
cat > /dev/null
exit 1
EOF
cat > "$T/bin/xclip" <<'EOF'
#!/bin/sh
case "$*" in
  *" -o") cat "$XCLIP_BUF" ;;
  *) cat > "$XCLIP_BUF" ;;
esac
EOF
chmod +x "$T/bin/wl-paste" "$T/bin/wl-copy" "$T/bin/xclip"
export XCLIP_BUF="$T/buf"

printf '%s' '你好世界' > "$XCLIP_BUF"
READ=$(PATH="$T/bin:$PATH" XCLIP_BUF="$XCLIP_BUF" python3 - <<'PY'
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('ht', 'hotkey-translation').load_module()
print(m.read_clipboard())
PY
)
[ "$READ" = "你好世界" ] || { echo "FAIL: read returned [$READ]" >&2; exit 1; }

PATH="$T/bin:$PATH" XCLIP_BUF="$T/buf" python3 - <<'PY'
from importlib.machinery import SourceFileLoader
m = SourceFileLoader('ht', 'hotkey-translation').load_module()
m.write_clipboard("Hello world")
PY
[ "$(cat "$XCLIP_BUF")" = "Hello world" ] || { echo "FAIL: write did not use xclip" >&2; exit 1; }

echo "PASS: clipboard falls back to xclip when the Wayland tools fail"
