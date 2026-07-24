# Migration Patterns

## Single policy group

Use this when all protected routes intentionally share the same client set.

Remote fragment:

```caddyfile
@allowed remote_ip 192.0.2.10 198.51.100.0/24 127.0.0.1 ::1
```

Local Caddyfile:

```caddyfile
(restricted_clients) {
	import /etc/caddy/remote-whitelist.caddy
}
```

Keep each site importing `restricted_clients` and handling `@allowed` as before.

## Multiple policy groups

Use this when routes have different client populations. Import the remote file once at top level and let it define the reusable snippets.

Remote fragment:

```caddyfile
(restricted_clients) {
	@allowed remote_ip 192.0.2.10 127.0.0.1 ::1
}

(migrated_nginx_allowed_clients) {
	@allowed remote_ip 198.51.100.20 203.0.113.0/24 127.0.0.1 ::1
}
```

Local Caddyfile:

```caddyfile
import /etc/caddy/remote-whitelist.caddy

http://example.com:8317 {
	import restricted_clients
	# Existing handlers remain here.
}

http://example.com:8082 {
	import migrated_nginx_allowed_clients
	# Existing handlers remain here.
}
```

Remove the old local definitions only after the imported fragment exists and validates. Do not import the same file repeatedly inside both snippets because that would redefine both snippets.

## Migration checks

Compare these values before and after:

- Each snippet's exact IP/CIDR set
- IPv4 and IPv6 loopback entries
- RFC1918 networks and other intentionally broad ranges
- Site blocks importing each snippet
- Matcher names referenced by `handle`, `route`, `respond`, or `reverse_proxy`
- Final fallback behavior for non-allowed clients

Use `caddy adapt --config <Caddyfile> --pretty` when textual imports make the effective structure difficult to review.
