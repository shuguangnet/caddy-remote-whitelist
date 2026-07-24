#!/bin/sh
set -eu

PROGRAM_NAME="caddy-remote-whitelist"
INSTALL_BIN="${INSTALL_BIN:-/usr/local/sbin/$PROGRAM_NAME}"
CONFIG_FILE="${CONFIG_FILE:-/etc/caddy-remote-whitelist.conf}"

if [ "$(id -u)" -ne 0 ]; then
	printf 'Run this uninstaller as root.\n' >&2
	exit 1
fi

systemctl disable --now "$PROGRAM_NAME.timer" 2>/dev/null || true
rm -f "/etc/systemd/system/$PROGRAM_NAME.timer"
rm -f "/etc/systemd/system/$PROGRAM_NAME.service"
rm -f "$INSTALL_BIN" "$CONFIG_FILE"
systemctl daemon-reload

printf 'Removed the updater. The cached whitelist was preserved.\n'
