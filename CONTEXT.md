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
- **Headplane** — the web UI for Headscale running on the hostinger VPS (`services/headplane.nix`). NixOS-native (built-in nixpkgs module). API key auth (no OIDC). Domain: `gateway.veracoechea.com`.
- **Tailscale client** — the mesh VPN client running on the homelab (`services/tailscale.nix`). Joins the tailnet managed by Headscale, advertises the `10.0.0.0/24` LAN subnet as a network route. Uses official Tailscale clients on all devices.
- **Mesh interface** — the WireGuard interface created by the Tailscale client on the homelab. Named `tailscale0`. Caddy serves subdomain virtualHosts on this interface; firewall opens 443 only on `tailscale0` and `enp8s0`.
- **DERP relay** — Tailscale's fallback relay for NAT traversal when direct peer-to-peer fails. Embedded in Headscale on the VPS (STUN on `3478/udp`). Uses Tailscale's public DERP network as additional fallback (disabled — self-contained).
- **MagicDNS** — Tailscale's built-in DNS that resolves `*.tailnet.veracoechea.com` to tailnet IPs for joined devices.

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
    ├── caddy.nix                  ← reverse proxy: LAN (10.0.0.2:443) + mesh (tailscale0:443), tls internal
    ├── paperless.nix              ← document management (docs.veracoechea.com, 10.0.0.2:28981)
    ├── immich.nix                 ← photo/video management (photos.veracoechea.com, 10.0.0.2:2283)
    ├── vaultwarden.nix            ← password manager (passwords.veracoechea.com, LAN-only HTTPS)
    ├── headscale.nix              ← Tailscale control plane on VPS (vpn.veracoechea.com, NixOS-native + SQLite + embedded DERP)
    ├── headplane.nix              ← Headscale web UI on VPS (ui.veracoechea.com, NixOS-native, API key auth)
    └── tailscale.nix              ← Tailscale client on homelab (joins tailnet, advertises 10.0.0.0/24)
```

## Notes

- Services are bound to the homelab's LAN IP `10.0.0.2` and firewall ports are opened only on `enp8s0`, so they are reachable only from `10.0.0.0/24` via LAN. Mesh clients reach them via Caddy subdomain virtualHosts on the `tailscale0` interface.
- Paperless ships no default admin password (`passwordFile = null`); create one with `paperless-manage createsuperuser` after first apply.
- Vaultwarden fronts via Caddy with `tls internal` (self-signed internal CA). Trust Caddy's root CA on each client device once (root cert at `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`). The `ADMIN_TOKEN` secret lives in `/var/lib/vaultwarden/vaultwarden.env` (not the Nix store) — create it before first apply.
- Tailscale auth key lives in `/var/lib/tailscale/auth-key` (not the Nix store). Generate it via `headscale preauthkeys create` on the VPS after Headscale is running, then place it at this path before applying the homelab config.
- Headplane secrets live in `/var/lib/headplane/` (not the Nix store): `cookie-secret` (exactly 32 characters), `api-key` (generate via `headscale apikeys create`). Create them before first apply of the hostinger config.
- The `dotfiles` flake is the canonical place for cross-machine reuse; this repo is host-specific.
