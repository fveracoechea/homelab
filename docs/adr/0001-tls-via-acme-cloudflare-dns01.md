# TLS via security.acme + Cloudflare DNS-01 wildcard

The homelab sits behind Xfinity residential NAT (no inbound HTTP), so Caddy's default HTTP-01 ACME challenge can't work. We use NixOS's `security.acme` module with lego's Cloudflare DNS-01 provider to issue a wildcard cert for `*.veracoechea.com`, then have Caddy serve that cert with `auto_https off`. This avoids installing Caddy's internal root CA on every client device, works behind NAT, and covers all current and future subdomains with a single cert.

## Considered Options

- **Caddy `tls internal`** (rejected) — self-signed certs; requires installing Caddy's root CA on every client device (phones, laptops, desktops). Too much friction for multi-device access.
- **Caddy DNS plugin (`caddy-dns/cloudflare`)** (rejected) — requires a custom Caddy build with the plugin overlay; more moving parts than using NixOS's built-in `security.acme` + lego (which ships in nixpkgs with Cloudflare DNS support).
- **Tailscale HTTPS** (rejected) — valid certs but only for `*.tailnet.veracoechea.com`; would change the domain scheme and complicate LAN access.
- **`security.acme` + Cloudflare DNS-01** (chosen) — NixOS-native, no custom builds, wildcard covers all subdomains, works behind NAT, certs trusted by all browsers.

## Consequences

- Cloudflare API token (`CLOUDFLARE_DNS_API_TOKEN`) must live in `/var/lib/caddy/caddy.env` on the homelab, owned by `caddy:caddy` with `640` perms. The acme service runs as `acme:caddy` and reads this file — if perms are too tight, lego silently falls back to minica self-signed certs.
- DNS for `*.veracoechea.com` must point at the homelab's tailnet IP (`100.64.0.1`) via a Cloudflare A record (DNS only / gray cloud, not proxied). Specific subdomain records (`vpn`, `gateway`) override the wildcard for VPS-hosted services.
- Caddy's built-in ACME is fully disabled (`auto_https off`); all cert management is delegated to `security.acme`.
- Adding a new subdomain requires no cert changes — the wildcard already covers it.
