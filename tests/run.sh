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
auth_seen=0
output=
while [ "$#" -gt 0 ]; do
	case "$1" in
		--header)
			if [ "$2" = "Authorization: Bearer ${TEST_EXPECT_AUTH_TOKEN:-}" ]; then
				auth_seen=1
			fi
			shift 2
			;;
		--output)
			output=$2
			shift 2
			;;
		*) shift ;;
	esac
done
if [ "${TEST_EXPECT_AUTH:-0}" -eq 1 ] && [ "$auth_seen" -ne 1 ]; then
	exit 2
fi
[ -n "$output" ] || exit 1
cp "$TEST_REMOTE_SOURCE" "$output"
EOF

cat > "$TEST_DIR/bin/caddy" <<'EOF'
#!/bin/sh
[ "${TEST_CADDY_FAIL:-0}" -eq 0 ]
EOF

cat > "$TEST_DIR/bin/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_SYSTEMCTL_LOG"
EOF

cat > "$TEST_DIR/bin/id" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-u" ]; then
	printf '0\n'
	exit 0
fi
exec /usr/bin/id "$@"
EOF
chmod +x "$TEST_DIR/bin/curl" "$TEST_DIR/bin/caddy" "$TEST_DIR/bin/systemctl" "$TEST_DIR/bin/id"

cat > "$TEST_DIR/config" <<EOF
REMOTE_URL='https://example.test/allowed.caddy'
TARGET_FILE='$TEST_DIR/etc/caddy/remote.caddy'
CADDYFILE='$TEST_DIR/etc/caddy/Caddyfile'
CADDY_BIN='$TEST_DIR/bin/caddy'
CADDY_SERVICE='caddy'
GITHUB_TOKEN='test-token'
MAX_BYTES='1024'
EOF

export PATH="$TEST_DIR/bin:$PATH"
export TEST_REMOTE_SOURCE="$TEST_DIR/source.caddy"
export TEST_SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
export CADDY_REMOTE_WHITELIST_CONFIG="$TEST_DIR/config"
export TEST_EXPECT_AUTH=1
export TEST_EXPECT_AUTH_TOKEN=test-token

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

unset TEST_CADDY_FAIL
unset TEST_EXPECT_AUTH
unset TEST_EXPECT_AUTH_TOKEN
mkdir -p "$TEST_DIR/docker"
printf '@allowed remote_ip 127.0.0.1\n' > "$TEST_DIR/source.caddy"

cat > "$TEST_DIR/bin/docker" <<'EOF'
#!/bin/sh
command=$1
shift
case "$command" in
	exec)
		container=$1
		shift
		[ "$container" = "test-caddy" ] || exit 1
		case "$1" in
			test)
				if [ "$3" = "/etc/caddy/Caddyfile" ]; then
					exit 0
				fi
				[ -f "$TEST_DOCKER_TARGET" ]
				;;
			chmod) chmod "$2" "$TEST_DOCKER_TARGET" ;;
			rm) rm -f "$TEST_DOCKER_TARGET" ;;
			caddy)
				case "$2" in
					validate) [ "${TEST_CADDY_FAIL:-0}" -eq 0 ] ;;
					reload) printf 'reload\n' >> "$TEST_DOCKER_LOG" ;;
					version) exit 0 ;;
					*) exit 1 ;;
				esac
				;;
			*) exit 1 ;;
		esac
		;;
	cp)
		source_file=$1
		destination=$2
		case "$source_file" in
			test-caddy:/etc/caddy/Caddyfile) cp "$TEST_DOCKER_CADDYFILE" "$destination" ;;
			test-caddy:*) cp "$TEST_DOCKER_TARGET" "$destination" ;;
			*) cp "$source_file" "$TEST_DOCKER_TARGET" ;;
		esac
		;;
	inspect)
		if [ "${1:-}" = "--format" ]; then
			printf '/etc/caddy\n'
		fi
		;;
	ps)
		printf 'test-caddy caddy:2.11.4\n'
		;;
	*) exit 1 ;;
esac
EOF
chmod +x "$TEST_DIR/bin/docker"

cat > "$TEST_DIR/docker-config" <<EOF
REMOTE_URL='https://example.test/allowed.caddy'
MODE='docker'
DOCKER_CONTAINER='test-caddy'
TARGET_FILE='/etc/caddy/remote.caddy'
CADDYFILE='/etc/caddy/Caddyfile'
CADDY_BIN='caddy'
MAX_BYTES='1024'
STATE_DIR='$TEST_DIR/docker/state'
EOF

export CADDY_REMOTE_WHITELIST_CONFIG="$TEST_DIR/docker-config"
export TEST_DOCKER_TARGET="$TEST_DIR/docker/remote.caddy"
export TEST_DOCKER_LOG="$TEST_DIR/docker/docker.log"
export TEST_DOCKER_CADDYFILE="$TEST_DIR/docker/Caddyfile"
printf 'import /etc/caddy/remote-whitelist.caddy\n' > "$TEST_DOCKER_CADDYFILE"

"$REPO_DIR/install.sh" update
cmp "$TEST_DIR/source.caddy" "$TEST_DOCKER_TARGET"
grep -Fxq 'reload' "$TEST_DOCKER_LOG"

: > "$TEST_DOCKER_LOG"
"$REPO_DIR/install.sh" update
[ ! -s "$TEST_DOCKER_LOG" ]

printf '@allowed remote_ip 198.51.100.10\n' > "$TEST_DIR/source.caddy"
export TEST_CADDY_FAIL=1
if "$REPO_DIR/install.sh" update; then
	printf 'Expected Docker validation failure.\n' >&2
	exit 1
fi
grep -Fxq '@allowed remote_ip 127.0.0.1' "$TEST_DOCKER_TARGET"

unset TEST_CADDY_FAIL
rm -f "$TEST_DOCKER_TARGET"
: > "$TEST_DOCKER_LOG"
export TEST_EXPECT_AUTH=1
export TEST_EXPECT_AUTH_TOKEN=install-token
INSTALL_BIN="$TEST_DIR/bin/installed-updater" \
CONFIG_FILE="$TEST_DIR/installed.conf" \
SYSTEMD_DIR="$TEST_DIR/systemd" \
STATE_DIR="$TEST_DIR/docker/installed-state" \
"$REPO_DIR/install.sh" --docker-container test-caddy --interval 5m --github-token install-token
grep -Fxq "MODE='docker'" "$TEST_DIR/installed.conf"
grep -Fxq "DOCKER_CONTAINER='test-caddy'" "$TEST_DIR/installed.conf"
grep -Fxq "GITHUB_TOKEN='install-token'" "$TEST_DIR/installed.conf"
grep -Fq 'ExecStart=' "$TEST_DIR/systemd/caddy-remote-whitelist.service"
grep -Fq 'OnUnitActiveSec=5m' "$TEST_DIR/systemd/caddy-remote-whitelist.timer"
grep -Fxq 'reload' "$TEST_DOCKER_LOG"

printf 'All tests passed.\n'
