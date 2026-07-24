#!/bin/sh
set -eu

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/etc/caddy"
printf 'import %s\n' "$TEST_DIR/etc/caddy/remote.caddy" > "$TEST_DIR/etc/caddy/Caddyfile"
printf '@allowed remote_ip 127.0.0.1\n' > "$TEST_DIR/source.caddy"

cat > "$TEST_DIR/bin/curl" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
	if [ "$1" = "--output" ]; then
		cp "$TEST_REMOTE_SOURCE" "$2"
		exit 0
	fi
	shift
done
exit 1
EOF

cat > "$TEST_DIR/bin/caddy" <<'EOF'
#!/bin/sh
[ "${TEST_CADDY_FAIL:-0}" -eq 0 ]
EOF

cat > "$TEST_DIR/bin/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_SYSTEMCTL_LOG"
EOF
chmod +x "$TEST_DIR/bin/curl" "$TEST_DIR/bin/caddy" "$TEST_DIR/bin/systemctl"

cat > "$TEST_DIR/config" <<EOF
REMOTE_URL='https://example.test/allowed.caddy'
TARGET_FILE='$TEST_DIR/etc/caddy/remote.caddy'
CADDYFILE='$TEST_DIR/etc/caddy/Caddyfile'
CADDY_BIN='$TEST_DIR/bin/caddy'
CADDY_SERVICE='caddy'
MAX_BYTES='1024'
EOF

export PATH="$TEST_DIR/bin:$PATH"
export TEST_REMOTE_SOURCE="$TEST_DIR/source.caddy"
export TEST_SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
export CADDY_REMOTE_WHITELIST_CONFIG="$TEST_DIR/config"

"$REPO_DIR/install.sh" update
cmp "$TEST_DIR/source.caddy" "$TEST_DIR/etc/caddy/remote.caddy"
grep -Fxq 'reload caddy' "$TEST_DIR/systemctl.log"

: > "$TEST_DIR/systemctl.log"
"$REPO_DIR/install.sh" update
[ ! -s "$TEST_DIR/systemctl.log" ]

printf '@allowed remote_ip 192.0.2.10\n' > "$TEST_DIR/source.caddy"
export TEST_CADDY_FAIL=1
if "$REPO_DIR/install.sh" update; then
	printf 'Expected validation failure.\n' >&2
	exit 1
fi
grep -Fxq '@allowed remote_ip 127.0.0.1' "$TEST_DIR/etc/caddy/remote.caddy"

printf 'All tests passed.\n'
