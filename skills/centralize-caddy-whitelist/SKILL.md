---
name: centralize-caddy-whitelist
description: Inspect, deduplicate, and migrate scattered Caddy remote_ip allowlists into a centrally hosted fragment managed by caddy-remote-whitelist. Use when Codex needs to clean up an existing Caddyfile, preserve multiple access-policy groups, replace repeated IP lists with imports, onboard a server to this repository, or diagnose whitelist drift without accidentally broadening access.
---

# Centralize Caddy Whitelist

Migrate existing Caddy allowlists while preserving their current access boundaries. Treat similarly named matchers in different snippets as separate policies until inspection proves they are equivalent.

## Follow the migration workflow

1. Locate the active Caddyfile and all imported files. Determine whether Caddy runs as a systemd service or in Docker/1Panel. For Docker, inspect the container mounts and effective in-container config path before editing.
2. Back up every file that will change using a timestamped sibling copy. Do not overwrite an existing backup.
3. Run `scripts/scan_caddy_allowlists.py` against the active config tree. Review every `remote_ip` occurrence and its enclosing snippet/matcher.
4. Classify occurrences by access semantics, not merely by matcher name. Keep groups separate when their upstream, port, route, or client population differs.
5. Read [references/migration-patterns.md](references/migration-patterns.md) and select the single-group or multi-group layout.
6. Generate the proposed remote fragment and show the user a group-by-group IP diff before changing live files. Deduplicate exact IPs/CIDRs while preserving distinct networks.
7. Replace local lists with imports. Keep sensitive-path matchers, CORS handling, reverse proxies, and fallback `403` behavior unchanged.
8. Install this repository's updater with the chosen HTTPS URL and interval. Use `--docker-container NAME` for an explicit Docker target; otherwise allow auto-detection when exactly one Caddy container is running. Never place a secret token directly in a world-readable Caddyfile.
9. Run `caddy fmt --diff`, `caddy validate --config <path>`, reload Caddy, and independently test one allowed and one denied client path when feasible. Execute these commands with `docker exec` when Caddy is containerized.
10. Report the remote fragment URL, local cache path, timer status, policy groups migrated, duplicates removed, and any unclassified entries.

## Use the scanner

Run a read-only inventory:

```bash
python3 scripts/scan_caddy_allowlists.py /etc/caddy
```

Produce JSON when further processing is useful:

```bash
python3 scripts/scan_caddy_allowlists.py --json /etc/caddy
```

Emit a deduplicated single matcher only after identifying its enclosing snippet:

```bash
python3 scripts/scan_caddy_allowlists.py \
  --emit-fragment --snippet restricted_clients --matcher allowed \
  /etc/caddy
```

Treat tokens reported as `unparsed` as blockers requiring manual review. Do not silently discard placeholders, hostnames, malformed CIDRs, or Caddy special tokens.

## Preserve safety properties

- Do not merge policy groups solely because their IP sets overlap.
- Do not fetch the remote URL directly from request handling; use the local last-known-good cache installed by this repository.
- Do not reload when download or validation fails.
- Do not remove the local cached fragment during uninstall or rollback.
- Warn when a Docker target is outside every container mount because it will be lost on recreation.
- Do not claim success from `caddy validate` alone; verify the service and relevant route behavior.
- Ask before changing public/private repository visibility, remote hosting, authentication, or polling frequency when those choices are not already established.
