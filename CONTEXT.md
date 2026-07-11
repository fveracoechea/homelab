# Context

Domain language for the `homelab` NixOS flake. Skills should use these terms verbatim in output; add new terms here as they get pinned down.

## What this is

A multi-host NixOS configuration managed as a flake. Two physical/virtual machines:
- **homelab** — a physical AMD machine (x86_64-linux) running services for personal use, behind Xfinity residential NAT.
- **hostinger** — a VPS (x86_64-linux) at Hostinger with a public IP, running the Headscale control plane.

User-level config on homelab is delegated to `home-manager`; both system and user config pull reusable modules from an external `dotfiles` flake.

## Glossary

- **Host** — a NixOS machine defined under `nixosConfigurations`. Currently two: `homelab` and `hostinger`. Build/test with `nixos-rebuild test --flake .#<hostname>`.
- **Host settings** — the per-host config bundle under `hosts/<hostname>/`: `configuration.nix` (system), `hardware-configuration.nix` (generated, do not hand-edit), optional `home.nix` (home-manager), and host-specific files (e.g. `networking.nix`, `disko-config.nix`).
- **Service** — a self-contained NixOS module under `services/` that enables one application (e.g. `paperless.nix`, `immich.nix`, `caddy.nix`, `headscale.nix`, `tailscale.nix`). Imported into a host's `modules` list via the host's `configuration.nix`.
- **Dotfiles module** — a reusable module from the external `github:fveracoechea/dotfiles` flake. System modules are applied via `inputs.dotfiles.nixosModules.default`; home modules via `inputs.dotfiles.homeManagerModules.default`. Both are toggled with `dotfiles.<feature>.enable`.
- **dotfilesPkgs** — the package overlay exposed by the `dotfiles` flake, passed into hosts via `specialArgs`.
- **System version** — pinned by `system.stateVersion` / `home.stateVersion`; do not change.
- **Headscale** — the self-hosted Tailscale coordination server running on the hostinger VPS (`services/headscale.nix`). NixOS-native, SQLite, embedded DERP relay. Domain: `vpn.veracoechea.com`.
- **Headplane** — the web UI for Headscale running on the hostinger VPS (`services/headplane.nix`). NixOS-native (built-in nixpkgs module). API key auth (no OIDC). Domain: `network.veracoechea.com`.
- **Tailscale client** — the mesh VPN client running on the homelab (`services/tailscale.nix`). Joins the tailnet managed by Headscale, advertises the `10.0.0.0/24` LAN subnet as a network route. Uses official Tailscale clients on all devices.
- **Ollama** — the local LLM server running on the homelab (`services/ollama.nix`). NixOS-native (`services.ollama`) using `ollama-rocm` for AMD GPU acceleration. Pinned to the dedicated RX 7600 (gfx1102, 8GB VRAM) via `ROCR_VISIBLE_DEVICES=0` (the Ryzen iGPU at renderD129/gfx1036 is left idle), with `HSA_OVERRIDE_GFX_VERSION=11.0.0` (`services.ollama.rocmOverrideGfx`) since the bundled ROCm officially targets gfx1100/gfx1101 and the RX 7600 needs to masquerade as gfx1100. Listens on `127.0.0.1:11434` (localhost only - no Caddy vhost, reach it via SSH port forwarding or Tailscale). Auto-pulls `qwen3.5:9b` and `minicpm-v4.5` on first start via `services.ollama.loadModels`.
- **Home Assistant** — the smart-home automation platform running on the homelab (`services/home-assistant.nix`). NixOS-native (`services.home-assistant`). Listens on `127.0.0.1:8123`; Caddy vhost at `home.veracoechea.com`. No pre-created secrets required - admin user, home location, timezone, and integration credentials are all set through the onboarding wizard in the web UI and stored in `/var/lib/hass/.storage/`. Nix manages only the base config: `default_config` (enables the standard integration bundle) and `http` (reverse proxy settings for Caddy via `use_x_forwarded_for` + `trusted_proxies`). All automations, integrations, scripts, and dashboards are managed through the web UI. Bluetooth is enabled on the host (`hardware.bluetooth.enable`) for BLE device discovery; requires a Bluetooth adapter (built-in or USB dongle).
- **Paperless-gpt** — the AI-powered document enhancement service running on the homelab (`services/paperless-gpt.nix`). Uses LLMs and LLM Vision (OCR) to generate better document titles, tags, correspondents, and custom fields for paperless-ngx. Runs as a podman OCI container (`ghcr.io/icereed/paperless-gpt:latest`) with host networking. Uses Ollama as the LLM provider (`qwen3.5:9b` for text, `minicpm-v4.5` for vision OCR). Listens on `127.0.0.1:8080`; Caddy vhost at `ai-docs.veracoechea.com`. Has NO built-in authentication - relies on network-level access control (LAN + tailnet only). Paperless API token lives at `/var/lib/paperless-gpt/paperless-gpt.env` (not the Nix store).
- **Podman** — the OCI container runtime enabled on the homelab (`services/paperless-gpt.nix`). Daemonless, rootless-capable, drop-in replacement for docker. Used by `virtualisation.oci-containers` (which defaults to the podman backend). First container service in the repo.
- **Mesh interface** — the WireGuard interface created by the Tailscale client on the homelab. Named `tailscale0`. Caddy serves subdomain virtualHosts on this interface; firewall opens 443 only on `tailscale0` and `enp8s0`.
- **DERP relay** — Tailscale's fallback relay for NAT traversal when direct peer-to-peer fails. Embedded in Headscale on the VPS (STUN on `3478/udp`). Uses Tailscale's public DERP network as additional fallback (disabled — self-contained).
- **MagicDNS** — Tailscale's built-in DNS that resolves `*.tailnet.veracoechea.com` to tailnet IPs for joined devices. Configured via Headscale to use `10.0.0.2` (AdGuard Home) as the global nameserver, so all tailnet devices get ad-blocking DNS automatically.
- **AdGuard Home** — the network-wide ad-blocking DNS server running on the homelab (`services/adguardhome.nix`). NixOS-native (`services.adguardhome`). DNS listener bound to `10.0.0.2:53`, reachable from both `enp8s0` (LAN) and `tailscale0` (tailnet). Web UI on `127.0.0.1:8082`; Caddy vhost at `dns.veracoechea.com`. Upstream DNS via Cloudflare (1.1.1.1, 1.0.0.1) and Quad9 (9.9.9.9, 149.112.112.112). Mutable settings (hybrid config): Nix provides the base config (upstream DNS, bind address, filtering toggles, starter blocklists); web UI changes (additional blocklists, clients, rewrites, query log settings) persist in `/var/lib/adguardhome/` between restarts. Firewall opens `53/udp` on `enp8s0` and `tailscale0` only - not exposed to the public internet (homelab is behind Xfinity NAT).

## Layout

```
/
├── flake.nix                      ← inputs (nixpkgs, home-manager, dotfiles, disko), nixosConfigurations
├── hosts/
│   ├── homelab/
│   │   ├── configuration.nix      ← system config (imports hardware + dotfiles + all services)
│   │   ├── hardware-configuration.nix  ← generated, do not hand-edit
│   │   └── home.nix               ← home-manager user config (imports dotfiles homeModule)
│   └── hostinger/
│       ├── configuration.nix      ← VPS system config (imports hardware + disko + headscale)
│       ├── hardware-configuration.nix  ← generated, do not hand-edit
│       ├── networking.nix         ← static IP, firewall (80/tcp, 443/tcp, 3478/udp)
│       └── disko-config.nix       ← declarative disk partitioning
└── services/
    ├── adguardhome.nix             ← network-wide ad-blocking DNS (dns.veracoechea.com, 10.0.0.2:53, Cloudflare+Quad9 DoT upstream)
    ├── caddy.nix                  ← reverse proxy + security.acme wildcard cert (Let's Encrypt via Cloudflare DNS-01)
    ├── paperless.nix              ← document management (docs.veracoechea.com, 10.0.0.2:28981)
    ├── immich.nix                 ← photo/video management (photos.veracoechea.com, 10.0.0.2:2283)
    ├── vaultwarden.nix            ← password manager (passwords.veracoechea.com, LAN-only HTTPS, PostgreSQL via configurePostgres)
    ├── headscale.nix              ← Tailscale control plane on VPS (vpn.veracoechea.com, NixOS-native + SQLite + embedded DERP)
    ├── headplane.nix              ← Headscale web UI on VPS (network.veracoechea.com, NixOS-native, API key auth)
    ├── tailscale.nix              ← Tailscale client on homelab (joins tailnet via Headscale, advertises 10.0.0.0/24)
    ├── ollama.nix                 ← Local LLM server on homelab (localhost:11434, ROCm on RX 7600 gfx1102)
    ├── paperless-gpt.nix          ← AI document enhancement for paperless-ngx (podman container, ai-docs.veracoechea.com)
    └── home-assistant.nix         ← Smart-home automation (home.veracoechea.com, hybrid config: Nix base + web UI)
```

## Notes

- Services are bound to the homelab's LAN IP `10.0.0.2` and firewall ports are opened only on `enp8s0`, so they are reachable only from `10.0.0.0/24` via LAN. Mesh clients reach them via Caddy subdomain virtualHosts on the `tailscale0` interface. See ADR-0001 for TLS strategy, ADR-0002 for mesh VPN topology.
- TLS for homelab vhosts is provided by a wildcard Let's Encrypt cert for `*.veracoechea.com`, issued via `security.acme` using DNS-01 challenge against Cloudflare (`services/caddy.nix`). Caddy serves the cert from `/var/lib/acme/veracoechea.com/`; no client-side CA installation needed. The Cloudflare API token lives at `/var/lib/caddy/caddy.env` (not the Nix store) — create it before first apply (Cloudflare API token with `Zone:DNS:Edit` on `veracoechea.com`, file content `CLOUDFLARE_DNS_API_TOKEN=...` — must be this exact env var name for lego).
- Paperless reads its initial admin password from `/var/lib/paperless/admin-password` (not the Nix store) via `services.paperless.passwordFile`. Create it before first apply; the superuser (`admin`) is created automatically on startup. File must be owned by `paperless:paperless` with `600` perms.
- Vaultwarden uses PostgreSQL via `services.vaultwarden.configurePostgres = true` — the module auto-creates the `vaultwarden` database/role and sets `DATABASE_URL`. The `ADMIN_TOKEN` secret lives in `/var/lib/vaultwarden/vaultwarden.env` (not the Nix store) — create it before first apply. File must be owned by `vaultwarden:vaultwarden` with `640` perms.
- Tailscale auth key lives in `/var/lib/tailscale/auth-key` (not the Nix store). Generate it via `sudo headscale preauthkeys create -u <user-id>` on the VPS after Headscale is running (the `-u` flag takes a numeric user ID, not a username — find it with `sudo headscale users list`), then place it at this path before applying the homelab config. The `--login-server` flag must be in `extraUpFlags` (passed to `tailscale up`), not `extraSetFlags` (passed to `tailscale set`). If a node was previously joined to a different login server, run `sudo tailscale up --reset --login-server=https://vpn.veracoechea.com ...` once to reconcile state.
- Headplane secrets live in `/var/lib/headplane/` (not the Nix store): `cookie-secret` (exactly 32 characters — headplane validates the length strictly; use `openssl rand -hex 16` with no trailing newline, do NOT use base64). The Headscale API key is not stored on disk — it is pasted into the Headplane web UI at login (API-key auth, no OIDC). Generate it via `sudo headscale apikeys create` on the VPS after Headscale is running. Headplane serves its UI at `/admin`, not `/` — visiting the root returns 404.
- Paperless-gpt has NO built-in authentication. Its web UI and `/api/*` endpoints are open to anyone who can reach the port. It is bound to `127.0.0.1:8080` and exposed only via the Caddy vhost `ai-docs.veracoechea.com` (LAN + tailnet). The Paperless API token lives at `/var/lib/paperless-gpt/paperless-gpt.env` (content: `PAPERLESS_API_TOKEN=...`, not the Nix store) - generate it in paperless-ngx admin (My Profile > API Token) before first apply. Create the directories `/var/lib/paperless-gpt/{prompts,config,data}` before first apply.
- Headscale CLI commands require sudo — the socket at `/run/headscale/headscale.sock` is owned by the `headscale` user.
- AdGuard Home has a first-run onboarding wizard at `https://dns.veracoechea.com` — set the admin password there on first launch. The Nix-defined `settings` (DNS bind address, upstream resolvers, filtering toggles, starter blocklists) are merged on every restart and take precedence over web UI changes for those keys. Anything added only in the web UI (additional blocklists, client configs, DNS rewrites, query log settings) persists in `/var/lib/adguardhome/` via `mutableSettings = true`. LAN devices use AdGuard by setting the router's DHCP DNS to `10.0.0.2`; tailnet devices use it automatically via Headscale's `nameservers.global = ["10.0.0.2"]`. The homelab itself does NOT use AdGuard as its system DNS (`--accept-dns=false` in `services/tailscale.nix`) to avoid a boot-order dependency where DNS resolution fails until AdGuard Home starts.
- The `dotfiles` flake is the canonical place for cross-machine reuse; this repo is host-specific.
