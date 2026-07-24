# Caddy Remote Whitelist

[简体中文](README.zh-CN.md)

This repository also includes the Codex skill
[`centralize-caddy-whitelist`](skills/centralize-caddy-whitelist/SKILL.md) for
auditing and migrating existing, inconsistent Caddy allowlists without merging
distinct access-policy groups.

Install the skill by placing `skills/centralize-caddy-whitelist` in your Codex
skills directory, then invoke it with a request such as:

```text
Use $centralize-caddy-whitelist to audit my current Caddyfile and migrate its
allowlists to this project without changing access permissions.
```

Keep one Caddy whitelist fragment at an HTTPS URL and synchronize it safely to
multiple servers. Each server caches the last valid copy, validates the full
Caddy configuration, and reloads Caddy only when the fragment changes.

## Remote fragment

Publish a plain-text file like this at an HTTPS URL:

```caddyfile
@allowed remote_ip 192.0.2.10 198.51.100.0/24 203.0.113.25
```

## Caddyfile

Replace the IP list in the local reusable snippet with one import:

```caddyfile
(restricted_clients) {
	import /etc/caddy/remote-whitelist.caddy
}
```

Existing protected sites can continue using the same matcher:

```caddyfile
http://example.com:8317 {
	import restricted_clients

	handle @allowed {
		reverse_proxy 127.0.0.1:8817
	}

	handle {
		respond 403
	}
}
```

## Install

Clone the repository and run:

```bash
sudo ./install.sh \
  --interval 5m
```

Or, after the GitHub repository is published:

```bash
curl -fsSL https://raw.githubusercontent.com/shuguangnet/caddy-remote-whitelist/main/install.sh \
  -o /tmp/caddy-remote-whitelist-install.sh
sudo sh /tmp/caddy-remote-whitelist-install.sh \
  --interval 5m
```

For a private whitelist data repository, pass a GitHub token during the same
one-line install flow:

```bash
curl -fsSL https://raw.githubusercontent.com/shuguangnet/caddy-remote-whitelist/main/install.sh \
  -o /tmp/caddy-remote-whitelist-install.sh
sudo GITHUB_TOKEN="$GITHUB_TOKEN" sh /tmp/caddy-remote-whitelist-install.sh \
  --interval 5m
```

By default the installer uses:

```text
https://raw.githubusercontent.com/shuguangnet/caddy-whitelist-data/main/allowed-clients.caddy
```

Pass `--url` to use a different HTTPS fragment.

### Private GitHub repository

If the whitelist data repository is private, provide a GitHub token with read
access to the repository contents:

```bash
sudo sh /tmp/caddy-remote-whitelist-install.sh \
  --interval 5m \
  --github-token "$GITHUB_TOKEN"
```

The installer stores the token in `/etc/caddy-remote-whitelist.conf`, which is
created with mode `0600`. Future timer runs automatically use the token when
downloading the fragment.

You can also pass the token through the environment:

```bash
sudo GITHUB_TOKEN="$GITHUB_TOKEN" ./install.sh \
  --interval 5m
```

Use a fine-grained GitHub token scoped only to the whitelist data repository
with `Contents: Read-only`.

### Docker and 1Panel

The installer automatically selects Docker mode when it finds exactly one
running Caddy container. A container can also be selected explicitly:

```bash
sh /tmp/caddy-remote-whitelist-install.sh \
  --docker-container 1Panel-caddy-5mTH \
  --interval 5m
```

Docker mode uses `/etc/caddy/Caddyfile` and
`/etc/caddy/remote-whitelist.caddy` inside the container by default. It updates
the fragment with `docker cp`, then runs `caddy validate` and `caddy reload`
inside the container. The installer warns when the target is not under a
Docker volume or bind mount because it would be lost on container recreation.

The installer accepts custom paths and service names:

```bash
sudo ./install.sh \
  --url https://config.example.com/allowed.caddy \
  --interval 1m \
  --target /etc/caddy/shared/allowed.caddy \
  --caddyfile /etc/caddy/Caddyfile \
  --service caddy
```

Run `./install.sh --help` for all options. Settings are stored in
`/etc/caddy-remote-whitelist.conf` with mode `0600`.

## Behavior

- HTTPS is required.
- The downloaded file must be non-empty and no larger than 1 MiB by default.
- An unchanged file does not reload Caddy.
- A failed download keeps the last working file.
- A failed `caddy validate` restores the previous file in systemd and Docker modes.
- A systemd timer synchronizes the file every five minutes by default.

Useful commands:

```bash
systemctl status caddy-remote-whitelist.timer
systemctl start caddy-remote-whitelist.service
journalctl -u caddy-remote-whitelist.service
```

## Uninstall

```bash
sudo ./uninstall.sh
```

The cached whitelist is intentionally preserved so an existing Caddy import
does not break.

## Security

Anyone who can modify the remote fragment can change access to every connected
server. Use HTTPS, protect the publishing account, and avoid URLs controlled by
third parties. For private GitHub repositories, prefer a fine-grained read-only
token scoped to the whitelist data repository. Passing a token as a command-line
argument may leave it in shell history; the `GITHUB_TOKEN` environment variable
is preferable for interactive installs. URL query credentials are stored locally
in a root-only file but may still appear in server logs; an authorization header
is preferable.

## License

MIT
