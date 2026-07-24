#!/bin/sh
set -eu

PROGRAM_NAME="caddy-remote-whitelist"
INSTALL_BIN="${INSTALL_BIN:-/usr/local/sbin/$PROGRAM_NAME}"
CONFIG_FILE="${CONFIG_FILE:-${CADDY_REMOTE_WHITELIST_CONFIG:-/etc/caddy-remote-whitelist.conf}}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
DEFAULT_REMOTE_URL="https://raw.githubusercontent.com/shuguangnet/caddy-whitelist-data/main/allowed-clients.caddy"

usage() {
	cat <<'EOF'
Usage: sudo ./install.sh [options]

Options:
  --url URL                 Remote fragment (default: managed whitelist repo)
  --interval DURATION       Sync interval, for example 1m, 5m, 1h (default: 5m)
  --mode MODE               auto, systemd, or docker (default: auto)
  --docker-container NAME   Caddy container name; implies Docker mode
  --target FILE             Fragment path on host or inside container
  --caddyfile FILE          Caddyfile path on host or inside container
  --caddy-bin PATH          Caddy executable or container command
  --service NAME            Caddy systemd service name
  --max-bytes NUMBER        Maximum downloaded size (default: 1048576)
  -h, --help                Show this help

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
	: "${MODE:=systemd}"
	: "${DOCKER_CONTAINER:=}"
	: "${TARGET_FILE:=/etc/caddy/remote-whitelist.caddy}"
	: "${CADDYFILE:=/etc/caddy/Caddyfile}"
	: "${CADDY_BIN:=caddy}"
	: "${CADDY_SERVICE:=caddy}"
	: "${MAX_BYTES:=1048576}"
	: "${STATE_DIR:=}"

	if [ "$MODE" = "docker" ]; then
		state_dir=${STATE_DIR:-/var/lib/caddy-remote-whitelist}
	else
		state_dir=$(dirname "$TARGET_FILE")
	fi
	mkdir -p "$state_dir"
	temp_file=$(mktemp "$state_dir/.remote-whitelist.XXXXXX")
	backup_file=$(mktemp "$state_dir/.remote-whitelist-backup.XXXXXX")
	had_target=0

	# shellcheck disable=SC2317,SC2329
	cleanup() {
		rm -f "$temp_file" "$backup_file"
	}
	trap cleanup EXIT HUP INT TERM

	target_exists() {
		if [ "$MODE" = "docker" ]; then
			docker exec "$DOCKER_CONTAINER" test -f "$TARGET_FILE"
		else
			[ -f "$TARGET_FILE" ]
		fi
	}

	copy_target_to() {
		destination=$1
		if [ "$MODE" = "docker" ]; then
			docker cp "$DOCKER_CONTAINER:$TARGET_FILE" "$destination"
		else
			cp -p "$TARGET_FILE" "$destination"
		fi
	}

	install_target() {
		source_file=$1
		chmod 0644 "$source_file"
		if [ "$MODE" = "docker" ]; then
			docker cp "$source_file" "$DOCKER_CONTAINER:$TARGET_FILE"
			docker exec "$DOCKER_CONTAINER" chmod 0644 "$TARGET_FILE"
		else
			mv "$source_file" "$TARGET_FILE"
		fi
	}

	remove_target() {
		if [ "$MODE" = "docker" ]; then
			docker exec "$DOCKER_CONTAINER" rm -f "$TARGET_FILE"
		else
			rm -f "$TARGET_FILE"
		fi
	}

	validate_caddy() {
		if [ "$MODE" = "docker" ]; then
			docker exec "$DOCKER_CONTAINER" "$CADDY_BIN" validate --config "$CADDYFILE"
		else
			"$CADDY_BIN" validate --config "$CADDYFILE"
		fi
	}

	reload_caddy() {
		if [ "$MODE" = "docker" ]; then
			docker exec "$DOCKER_CONTAINER" "$CADDY_BIN" reload --config "$CADDYFILE"
		elif command -v systemctl >/dev/null 2>&1; then
			systemctl reload "$CADDY_SERVICE"
		else
			"$CADDY_BIN" reload --config "$CADDYFILE"
		fi
	}

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

	if target_exists; then
		copy_target_to "$backup_file"
		had_target=1
		if cmp -s "$temp_file" "$backup_file"; then
			printf 'Whitelist is unchanged.\n'
			exit 0
		fi
	fi

	install_target "$temp_file"

	if ! validate_caddy; then
		if [ "$had_target" -eq 1 ]; then
			install_target "$backup_file"
		else
			remove_target
		fi
		printf 'Caddy validation failed; restored the previous whitelist.\n' >&2
		exit 1
	fi

	reload_caddy
	printf 'Whitelist updated and Caddy reloaded (%s mode).\n' "$MODE"
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
DOCKER_CONTAINER="${DOCKER_CONTAINER:-}"
MODE="${MODE:-auto}"
INTERVAL="${INTERVAL:-5m}"
REMOTE_URL="${REMOTE_URL:-$DEFAULT_REMOTE_URL}"
MAX_BYTES="${MAX_BYTES:-1048576}"

while [ "$#" -gt 0 ]; do
	case "$1" in
		--url) REMOTE_URL=$2; shift 2 ;;
		--interval) INTERVAL=$2; shift 2 ;;
		--mode) MODE=$2; shift 2 ;;
		--docker-container) DOCKER_CONTAINER=$2; MODE=docker; shift 2 ;;
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

case "$MODE" in
	auto|systemd|docker) ;;
	*) printf 'Invalid mode: %s\n' "$MODE" >&2; exit 2 ;;
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
	printf 'systemd is required for the synchronization timer.\n' >&2
	exit 1
fi

if [ "$MODE" = "auto" ] && command -v "$CADDY_BIN" >/dev/null 2>&1 && [ -f "$CADDYFILE" ]; then
	MODE=systemd
fi

if [ "$MODE" = "auto" ]; then
	if ! command -v docker >/dev/null 2>&1; then
		printf 'Caddy was not found on the host and Docker is unavailable.\n' >&2
		exit 1
	fi
	containers=$(docker ps --format '{{.Names}} {{.Image}}' | awk 'tolower($1 " " $2) ~ /caddy/ {print $1}')
	container_count=$(printf '%s\n' "$containers" | awk 'NF {count++} END {print count+0}')
	if [ "$container_count" -eq 1 ]; then
		DOCKER_CONTAINER=$containers
		MODE=docker
	elif [ "$container_count" -eq 0 ]; then
		printf 'No running Caddy container was found.\n' >&2
		exit 1
	else
		printf 'Multiple Caddy containers were found; use --docker-container NAME:\n%s\n' "$containers" >&2
		exit 1
	fi
fi

if [ "$MODE" = "systemd" ]; then
	if ! command -v "$CADDY_BIN" >/dev/null 2>&1; then
		printf 'Caddy executable not found: %s\n' "$CADDY_BIN" >&2
		exit 1
	fi
	if [ ! -f "$CADDYFILE" ]; then
		printf 'Caddyfile not found: %s\n' "$CADDYFILE" >&2
		exit 1
	fi
else
	if ! command -v docker >/dev/null 2>&1; then
		printf 'Docker is required for Docker mode.\n' >&2
		exit 1
	fi
	if [ -z "$DOCKER_CONTAINER" ]; then
		printf '%s\n' '--docker-container is required in Docker mode.' >&2
		exit 1
	fi
	if ! docker inspect "$DOCKER_CONTAINER" >/dev/null 2>&1; then
		printf 'Caddy container not found: %s\n' "$DOCKER_CONTAINER" >&2
		exit 1
	fi
	if ! docker exec "$DOCKER_CONTAINER" test -f "$CADDYFILE"; then
		printf 'Caddyfile not found inside container %s: %s\n' "$DOCKER_CONTAINER" "$CADDYFILE" >&2
		exit 1
	fi
	if ! docker exec "$DOCKER_CONTAINER" "$CADDY_BIN" version >/dev/null 2>&1; then
		printf 'Caddy command not available inside container %s: %s\n' "$DOCKER_CONTAINER" "$CADDY_BIN" >&2
		exit 1
	fi
	persistent_target=0
	for mount_destination in $(docker inspect --format '{{range .Mounts}}{{println .Destination}}{{end}}' "$DOCKER_CONTAINER"); do
		case "$TARGET_FILE" in
			"$mount_destination"|"$mount_destination"/*) persistent_target=1 ;;
		esac
	done
	if [ "$persistent_target" -eq 0 ]; then
		printf 'Warning: %s is not under a Docker mount and may be lost when container %s is recreated.\n' "$TARGET_FILE" "$DOCKER_CONTAINER" >&2
	fi
fi

install -m 0755 "$0" "$INSTALL_BIN"

umask 077
{
	printf 'REMOTE_URL=%s\n' "$(shell_quote "$REMOTE_URL")"
	printf 'MODE=%s\n' "$(shell_quote "$MODE")"
	printf 'DOCKER_CONTAINER=%s\n' "$(shell_quote "$DOCKER_CONTAINER")"
	printf 'TARGET_FILE=%s\n' "$(shell_quote "$TARGET_FILE")"
	printf 'CADDYFILE=%s\n' "$(shell_quote "$CADDYFILE")"
	printf 'CADDY_BIN=%s\n' "$(shell_quote "$CADDY_BIN")"
	printf 'CADDY_SERVICE=%s\n' "$(shell_quote "$CADDY_SERVICE")"
	printf 'MAX_BYTES=%s\n' "$(shell_quote "$MAX_BYTES")"
} > "$CONFIG_FILE"
chmod 0600 "$CONFIG_FILE"

mkdir -p "$SYSTEMD_DIR"
cat > "$SYSTEMD_DIR/$PROGRAM_NAME.service" <<EOF
[Unit]
Description=Update Caddy remote whitelist
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$INSTALL_BIN update
EOF

cat > "$SYSTEMD_DIR/$PROGRAM_NAME.timer" <<EOF
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

inspection_file=$(mktemp)
trap 'rm -f "$inspection_file"' EXIT HUP INT TERM
if [ "$MODE" = "docker" ]; then
	docker cp "$DOCKER_CONTAINER:$CADDYFILE" "$inspection_file"
else
	cp "$CADDYFILE" "$inspection_file"
fi

if ! grep -Fq "$TARGET_FILE" "$inspection_file"; then
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

rm -f "$inspection_file"
trap - EXIT HUP INT TERM

"$INSTALL_BIN" update
systemctl enable --now "$PROGRAM_NAME.timer"

printf '\nInstalled successfully. Mode: %s; sync interval: %s\n' "$MODE" "$INTERVAL"
if [ "$MODE" = "docker" ]; then
	printf 'Caddy container: %s\n' "$DOCKER_CONTAINER"
fi
printf 'Configuration: %s\n' "$CONFIG_FILE"
printf 'Timer status: systemctl status %s.timer\n' "$PROGRAM_NAME"
