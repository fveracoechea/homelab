# Context

Domain language for the `homelab` NixOS flake. Skills should use these terms verbatim in output; add new terms here as they get pinned down.

## What this is

A single-host NixOS configuration managed as a flake. The host is a physical AMD machine (`homelab`, x86_64-linux) running services for personal use. User-level config is delegated to `home-manager`, and both system and user config pull reusable modules from an external `dotfiles` flake.

## Glossary

- **Host** — a NixOS machine defined under `nixosConfigurations`. Currently one: `homelab`. Build/test with `nixos-rebuild test --flake .#homelab`.
- **Host settings** — the per-host config bundle under `host-settings/`: `configuration.nix` (system), `hardware-configuration.nix` (generated, do not hand-edit), `home.nix` (the user's home-manager config).
- **Service** — a self-contained NixOS module under `services/` that enables one application (e.g. `paperless.nix`, `immich.nix`, `caddy.nix`). Imported into a host's `modules` list in `flake.nix`.
- **Dotfiles module** — a reusable module from the external `github:fveracoechea/dotfiles` flake. System modules are applied via `inputs.dotfiles.nixosModules.default`; home modules via `inputs.dotfiles.homeManagerModules.default`. Both are toggled with `dotfiles.<feature>.enable`.
- **dotfilesPkgs** — the package overlay exposed by the `dotfiles` flake, passed into the host via `specialArgs`.
- **System version** — pinned by `system.stateVersion` / `home.stateVersion` (currently `26.05`); do not change.

## Layout

```
/
├── flake.nix                 ← inputs, nixosConfigurations.homelab
├── host-settings/
│   ├── configuration.nix     ← system config (imports hardware + dotfiles nixosModule)
│   ├── hardware-configuration.nix  ← generated, do not hand-edit
│   └── home.nix              ← home-manager user config (imports dotfiles homeModule)
└── services/
    ├── caddy.nix             ← reverse proxy, internal TLS for LAN-only HTTPS (10.0.0.2:443)
    ├── paperless.nix         ← document management (LAN-only, 10.0.0.2:28981)
    ├── immich.nix            ← photo/video management (LAN-only, 10.0.0.2:2283)
    └── vaultwarden.nix       ← password manager (behind Caddy, LAN-only HTTPS)
```

## Notes

- Services are bound to the host's LAN IP `10.0.0.2` and firewall ports are opened only on `enp8s0`, so they are reachable only from `10.0.0.0/24`.
- Paperless ships no default admin password (`passwordFile = null`); create one with `paperless-manage createsuperuser` after first apply.
- Vaultwarden fronts via Caddy with `tls internal` (self-signed internal CA). Trust Caddy's root CA on each client device once (root cert at `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`). The `ADMIN_TOKEN` secret lives in `/var/lib/vaultwarden/vaultwarden.env` (not the Nix store) — create it before first apply.
- NetBird was evaluated and deferred: self-hosting the control plane needs a public domain + open ports (breaks LAN-only), and the SaaS-client path was declined. Revisit if remote-access VPN is later needed.
- The `dotfiles` flake is the canonical place for cross-machine reuse; this repo is host-specific.
