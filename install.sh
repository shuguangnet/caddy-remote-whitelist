#!/bin/sh
set -eu

PROGRAM_NAME="caddy-remote-whitelist"
INSTALL_BIN="${INSTALL_BIN:-/usr/local/sbin/$PROGRAM_NAME}"
CONFIG_FILE="${CONFIG_FILE:-${CADDY_REMOTE_WHITELIST_CONFIG:-/etc/caddy-remote-whitelist.conf}}"
DEFAULT_REMOTE_URL="https://raw.githubusercontent.com/shuguangnet/caddy-whitelist-data/main/allowed-clients.caddy"

usage() {
	cat <<'EOF'
Usage: sudo ./install.sh [options]

Options:
  --url URL             Remote fragment (default: shuguangnet/caddy-whitelist-data)
  --interval DURATION   Sync interval, for example 1m, 5m, 1h (default: 5m)
  --target FILE         Local cached fragment
  --caddyfile FILE      Main Caddyfile
  --caddy-bin PATH      Caddy executable or command name
  --service NAME        Caddy systemd service name
  --max-bytes NUMBER    Maximum downloaded size (default: 1048576)
  -h, --help            Show this help

The same settings may be supplied through uppercase environment variables.
EOF
}

shell_quote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

update_whitelist() {
	if [ ! -r "$CONFIG_FILE" ]; then
		printf 'Configuration file is not readable: %s\n' "$CONFIG_FILE" >&2
		exit 1
	fi

	# The installer writes this root-owned file using shell-quoted values.
	# shellcheck disable=SC1090
	. "$CONFIG_FILE"

	: "${REMOTE_URL:?REMOTE_URL is required}"
	: "${TARGET_FILE:=/etc/caddy/remote-whitelist.caddy}"
	: "${CADDYFILE:=/etc/caddy/Caddyfile}"
	: "${CADDY_BIN:=caddy}"
	: "${CADDY_SERVICE:=caddy}"
	: "${MAX_BYTES:=1048576}"

	target_dir=$(dirname "$TARGET_FILE")
	mkdir -p "$target_dir"
	temp_file=$(mktemp "$target_dir/.remote-whitelist.XXXXXX")
	backup_file=$(mktemp "$target_dir/.remote-whitelist-backup.XXXXXX")
	had_target=0

	# shellcheck disable=SC2317,SC2329
	cleanup() {
		rm -f "$temp_file" "$backup_file"
	}
	trap cleanup EXIT HUP INT TERM

	curl --fail --silent --show-error --location \
		--proto '=https' --tlsv1.2 \
		--connect-timeout 10 --max-time 30 \
		--output "$temp_file" "$REMOTE_URL"

	if [ ! -s "$temp_file" ]; then
		printf 'Downloaded whitelist is empty; keeping the current file.\n' >&2
		exit 1
	fi

	file_size=$(wc -c < "$temp_file" | tr -d ' ')
	if [ "$file_size" -gt "$MAX_BYTES" ]; then
		printf 'Downloaded whitelist is too large (%s bytes; maximum %s).\n' "$file_size" "$MAX_BYTES" >&2
		exit 1
	fi

	if [ -f "$TARGET_FILE" ] && cmp -s "$temp_file" "$TARGET_FILE"; then
		printf 'Whitelist is unchanged.\n'
		exit 0
	fi

	if [ -f "$TARGET_FILE" ]; then
		cp -p "$TARGET_FILE" "$backup_file"
		had_target=1
	fi

	chmod 0644 "$temp_file"
	mv "$temp_file" "$TARGET_FILE"

	if ! "$CADDY_BIN" validate --config "$CADDYFILE"; then
		if [ "$had_target" -eq 1 ]; then
			mv "$backup_file" "$TARGET_FILE"
		else
			rm -f "$TARGET_FILE"
		fi
		printf 'Caddy validation failed; restored the previous whitelist.\n' >&2
		exit 1
	fi

	if command -v systemctl >/dev/null 2>&1; then
		systemctl reload "$CADDY_SERVICE"
	else
		"$CADDY_BIN" reload --config "$CADDYFILE"
	fi

	printf 'Whitelist updated and Caddy reloaded.\n'
}

if [ "${1:-}" = "update" ]; then
	shift
	if [ "$#" -ne 0 ]; then
		printf 'The update command does not accept arguments.\n' >&2
		exit 2
	fi
	update_whitelist
	exit 0
fi

TARGET_FILE="${TARGET_FILE:-/etc/caddy/remote-whitelist.caddy}"
CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
CADDY_BIN="${CADDY_BIN:-caddy}"
CADDY_SERVICE="${CADDY_SERVICE:-caddy}"
INTERVAL="${INTERVAL:-5m}"
REMOTE_URL="${REMOTE_URL:-$DEFAULT_REMOTE_URL}"
MAX_BYTES="${MAX_BYTES:-1048576}"

while [ "$#" -gt 0 ]; do
	case "$1" in
		--url) REMOTE_URL=$2; shift 2 ;;
		--interval) INTERVAL=$2; shift 2 ;;
		--target) TARGET_FILE=$2; shift 2 ;;
		--caddyfile) CADDYFILE=$2; shift 2 ;;
		--caddy-bin) CADDY_BIN=$2; shift 2 ;;
		--service) CADDY_SERVICE=$2; shift 2 ;;
		--max-bytes) MAX_BYTES=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
	esac
done

if [ "$(id -u)" -ne 0 ]; then
	printf 'Run this installer as root.\n' >&2
	exit 1
fi

case "$REMOTE_URL" in
	https://*) ;;
	*) printf 'Only HTTPS URLs are accepted.\n' >&2; exit 2 ;;
esac

if ! printf '%s\n' "$INTERVAL" | grep -Eq '^[1-9][0-9]*[smhd]$'; then
	printf 'Invalid interval: %s\n' "$INTERVAL" >&2
	exit 2
fi

case "$MAX_BYTES" in
	''|*[!0-9]*) printf 'Invalid maximum size: %s\n' "$MAX_BYTES" >&2; exit 2 ;;
esac

if ! command -v curl >/dev/null 2>&1; then
	printf 'curl is required.\n' >&2
	exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
	printf 'systemd is required.\n' >&2
	exit 1
fi
if ! command -v "$CADDY_BIN" >/dev/null 2>&1; then
	printf 'Caddy executable not found: %s\n' "$CADDY_BIN" >&2
	exit 1
fi
if [ ! -f "$CADDYFILE" ]; then
	printf 'Caddyfile not found: %s\n' "$CADDYFILE" >&2
	exit 1
fi

install -m 0755 "$0" "$INSTALL_BIN"

umask 077
{
	printf 'REMOTE_URL=%s\n' "$(shell_quote "$REMOTE_URL")"
	printf 'TARGET_FILE=%s\n' "$(shell_quote "$TARGET_FILE")"
	printf 'CADDYFILE=%s\n' "$(shell_quote "$CADDYFILE")"
	printf 'CADDY_BIN=%s\n' "$(shell_quote "$CADDY_BIN")"
	printf 'CADDY_SERVICE=%s\n' "$(shell_quote "$CADDY_SERVICE")"
	printf 'MAX_BYTES=%s\n' "$(shell_quote "$MAX_BYTES")"
} > "$CONFIG_FILE"
chmod 0600 "$CONFIG_FILE"

cat > "/etc/systemd/system/$PROGRAM_NAME.service" <<EOF
[Unit]
Description=Update Caddy remote whitelist
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$INSTALL_BIN update
EOF

cat > "/etc/systemd/system/$PROGRAM_NAME.timer" <<EOF
[Unit]
Description=Periodically update Caddy remote whitelist

[Timer]
OnBootSec=30s
OnUnitActiveSec=$INTERVAL
RandomizedDelaySec=20s
Persistent=true
Unit=$PROGRAM_NAME.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload

if ! grep -Fq "$TARGET_FILE" "$CADDYFILE"; then
	cat >&2 <<EOF

The Caddyfile does not appear to import the downloaded fragment yet.
Add this inside your reusable whitelist snippet:

    import $TARGET_FILE

Then run:

    $INSTALL_BIN update
    systemctl enable --now $PROGRAM_NAME.timer
EOF
	exit 3
fi

"$INSTALL_BIN" update
systemctl enable --now "$PROGRAM_NAME.timer"

printf '\nInstalled successfully. Sync interval: %s\n' "$INTERVAL"
printf 'Configuration: %s\n' "$CONFIG_FILE"
printf 'Timer status: systemctl status %s.timer\n' "$PROGRAM_NAME"
