# Secrets in /var/lib files, not sops-nix or agenix

Secrets (API tokens, admin passwords, cookie secrets) are stored as plain files under `/var/lib/<service>/` on each host, referenced via NixOS options like `passwordFile`, `environmentFile`, `authKeyFile`, and `cookie_secret_path`. They are never committed to the Nix store or the git repo.

## Considered Options

- **sops-nix / agenix** (rejected) — adds a dependency on a secrets manager (SOPS, age/GPG keys, a master key on each host). For a two-host homelab with ~6 secrets, the operational overhead of key management, re-keying, and learning the tooling outweighs the benefit. If the secret count grows significantly or multiple people manage the infra, revisit this.
- **Plain files in `/var/lib/`** (chosen) — simplest approach. Each secret is a file owned by the service's user with tight perms (`600` or `640`). Created once via `ssh <host> 'sudo install ...'`. Not reproducible from the flake, but the flake references the path and the service fails fast if the file is missing or wrong.

## Consequences

- Secrets are not reproducible — deploying the flake on a fresh install requires manually re-creating each secret file. See `CONTEXT.md` Notes for the full list and creation commands.
- File ownership and permissions matter: the service's systemd unit runs as a specific user (e.g., `caddy`, `vaultwarden`, `headscale`), and the secret file must be readable by that user. Wrong perms cause silent failures (e.g., lego falls back to self-signed certs, headplane rejects the cookie secret).
- If a host is rebuilt from scratch, all `/var/lib/` secrets must be re-created before the first `nixos-rebuild switch`.
- Migrating to sops-nix later is straightforward — the NixOS options (`passwordFile`, `environmentFile`) accept any path, so swapping `/var/lib/foo/plain` for `/run/secrets/foo` requires only a config change, not a rewrite.
