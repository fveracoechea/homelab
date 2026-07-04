# homelab

A multi-host NixOS configuration managed as a flake. Two machines:

- **homelab** — physical AMD box (x86_64-linux) behind residential NAT. Runs the services (Paperless, Immich, Vaultwarden) and joins the tailnet as a Tailscale client.
- **hostinger** — VPS with a public IP. Runs the Headscale control plane, the Headplane web UI, and an embedded DERP relay.

System and user config pull reusable modules from an external [`dotfiles`](https://github.com/fveracoechea/dotfiles) flake. User config on the homelab is handled by `home-manager`.

## Architecture

```
                       Cloudflare (DNS)
                             |
            +----------------+----------------+
            |                                 |
   <control-plane fqdn>              *.<domain>
            |                          (wildcard -> tailnet IP)
            v
   +-----------------+              +-----------------------------------+
   | hostinger (VPS) |              | homelab (behind NAT, LAN subnet)  |
   |  - Headscale    |  control +   |  - Tailscale client (tailscale0)  |
   |  - Headplane    |  DERP relay  |  - Caddy (TLS, reverse proxy)     |
   |  - Tailscale    |<------------>|  - Paperless / Immich / Vaultwarden|
   +-----------------+              +-----------------------------------+
                                              ^
                                              |  LAN only
                                              v
                                    homelab LAN IP on primary NIC
```

Services on the homelab bind to its LAN IP and are reachable only from the LAN. Off-LAN clients reach them through the mesh via Caddy subdomain vhosts on `tailscale0`. The VPS only runs the control plane + DERP relay; no application services are exposed on the public IP.

See [ADR-0002](docs/adr/0002-split-plane-mesh-vpn.md) for the mesh topology rationale and [ADR-0001](docs/adr/0001-tls-via-acme-cloudflare-dns01.md) for the TLS strategy.

## Repository layout

```
/
├── flake.nix                       inputs (nixpkgs, home-manager, dotfiles, disko), nixosConfigurations
├── hosts/
│   ├── homelab/
│   │   ├── configuration.nix       system config (hardware + dotfiles + all services)
│   │   ├── hardware-configuration.nix   generated, do not hand-edit
│   │   └── home.nix                home-manager user config (dotfiles homeModule)
│   └── hostinger/
│       ├── configuration.nix       VPS system config (hardware + disko + headscale)
│       ├── hardware-configuration.nix   generated, do not hand-edit
│       ├── networking.nix         static IP, firewall (80/tcp, 443/tcp, 3478/udp)
│       └── disko-config.nix        declarative disk partitioning
└── services/
    ├── caddy.nix                   reverse proxy + ACME wildcard cert (Cloudflare DNS-01)
    ├── caddy-vps.nix               VPS reverse proxy (headscale, headplane)
    ├── paperless.nix               document management (LAN-only HTTPS)
    ├── immich.nix                  photo/video management (LAN-only HTTPS)
    ├── vaultwarden.nix             password manager (LAN-only, PostgreSQL)
    ├── headscale.nix               control plane + embedded DERP
    ├── headplane.nix               Headscale web UI
    ├── tailscale.nix               homelab client (advertises LAN subnet)
    ├── tailscale-vps.nix           VPS client (joins its own tailnet)
    └── fail2ban.nix
```

Domain language and a per-service glossary live in [CONTEXT.md](CONTEXT.md). Architectural decisions are in [docs/adr/](docs/adr/).

## Build / deploy

From the repo root:

```sh
# Test a config locally (no switch)
nixos-rebuild test --flake .#homelab
nixos-rebuild test --flake .#hostinger

# Deploy over SSH via the justfile
just deploy-homelab
just deploy-vps

# Flake sanity check
nix flake check
```

## Secrets

Secrets are kept out of the Nix store and placed in `/var/lib/<service>/` before first apply (see [ADR-0003](docs/adr/0003-secrets-in-var-lib-not-sops.md)). Create these on the relevant host before deploying:

| Host      | Path                                    | Purpose                                                  | Notes                                                        |
|-----------|-----------------------------------------|----------------------------------------------------------|--------------------------------------------------------------|
| homelab   | `/var/lib/caddy/caddy.env`              | `CLOUDFLARE_DNS_API_TOKEN` (Zone:DNS:Edit on the domain) | exact env var name required by lego                         |
| homelab   | `/var/lib/paperless/admin-password`     | Paperless initial admin password                         | owned by `paperless:paperless`, mode `600`                   |
| homelab   | `/var/lib/vaultwarden/vaultwarden.env`  | `ADMIN_TOKEN`                                            | owned by `vaultwarden:vaultwarden`, mode `640`               |
| homelab   | `/var/lib/tailscale/auth-key`           | Headscale preauth key                                    | generate with `headscale preauthkeys create -u <uid>` on VPS |
| hostinger | `/var/lib/headplane/cookie-secret`      | Headplane cookie secret                                  | exactly 32 chars: `openssl rand -hex 16`, no trailing newline |

Headplane's Headscale API key is not stored on disk — paste it into the Headplane UI at first login (API-key auth, no OIDC). See [ADR-0004](docs/adr/0004-headplane-api-key-auth-no-oidc.md).

## Notes

- `system.stateVersion` / `home.stateVersion` are pinned; do not change.
- `hardware-configuration.nix` files are generated by NixOS — do not hand-edit.
- The `dotfiles` flake is the canonical place for cross-machine reuse; this repo is host-specific.
- Headscale CLI commands require sudo (socket at `/run/headscale/headscale.sock` is owned by the `headscale` user).
- Headplane serves its UI at `/admin`, not `/` — visiting the root returns 404.
- If a node was previously joined to a different login server, run `sudo tailscale up --reset --login-server=<your-headscale-url> ...` once to reconcile state.
