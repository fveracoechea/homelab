# Handoff: Migrate `/var/lib` secrets to sops-nix

## Context

The `homelab` NixOS flake currently provisions ~7 secrets as plain files under `/var/lib` on two hosts (`homelab`, `hostinger`), created manually out-of-band. This is not reproducible from the flake and doesn't scale. The user wants to migrate these to **sops-nix** so secrets are committed (encrypted) and provisioned declaratively on rebuild.

The original trigger was a question about not committing the VPS public IP (`168.231.68.183`) to git. After discussion we agreed **the IP is not actually a secret** (it's in DNS A records, ADR-0002, Cloudflare, and visible to anyone port-scanning the /24) and should stay plaintext in `hosts/hostinger/networking.nix`. The real secrets are the auth keys and env files under `/var/lib`.

## Decision: sops-nix over agenix

Chosen because:
- `vaultwarden.env` and `caddy.env` are multi-line env files → sops-nix's `sops.templates` assembles them from individual encrypted keys cleanly, vs agenix's one-opaque-file-per-secret model
- One `.sops.yaml` with age keys per host → one rekey when adding hosts, vs agenix's per-file reencryption
- `cookie_secret_path`, `authKeyFile`, `passwordFile`, `environmentFile` all map directly to `sops.secrets.<name>.path` — same NixOS options, just sourced from encrypted files

agenix would also work; the difference is small at this scale. sops-nix's template support is the deciding factor.

## Risk analysis

The migration **can** break the setup. Three risk tiers, in order of lockout severity:

### 1. Networking address (highest risk — full VPS lockout)
If the static IP in `hosts/hostinger/networking.nix:14,22,28` were gated behind a sops secret that fails to decrypt at boot, the interface never gets its address → no SSH on public IP → no tailnet → VPS is a brick. Recovery requires Hostinger VNC/rescue console.

**Mitigation: do not migrate the IP into sops.** Leave it plaintext. The user confirmed that disabling DHCP (i.e. `networking.useDHCP = true`) did not work in the past, so the static config must stay. The IP is not sensitive.

### 2. Tailscale auth key (medium risk — tailnet-only lockout)
If `services/tailscale-vps.nix:5` (`authKeyFile = "/var/lib/tailscale/auth-key"`) is repointed to a sops path that isn't populated, `tailscaled` starts unauthenticated → VPS drops off the tailnet → homelab and clients lose DERP relay and control plane. Public IP SSH still works, so not a full lockout, but the mesh degrades.

**Mitigation: two-path cutover.** Keep the existing `/var/lib/tailscale/auth-key` working while sops writes to a new path, swap the Nix option, rebuild, verify `tailscale status` on the VPS shows it authenticated, *then* delete the old file.

### 3. Headplane cookie / Headscale DB (low risk — control plane degrades, mesh survives)
Already-authenticated Tailscale clients cache node credentials and keep working for hours/days without reaching Headscale. New node joins and key expirations fail, but nothing breaks immediately.

**Mitigation: migrate headplane/cookie-secret last, after tailnet stuff is proven.** Leave `headscale/db.sqlite` alone — it's data, not a secret.

### General footgun
sops-nix decryption runs as a systemd path (`sops-nix.service`) before services that declare `sops.secrets.<x>.neededForBoot`. If you forget that flag on a boot-critical secret (tailscale key on the VPS), the first reboot bricks it. Same caveat applies to agenix's `neededForBoot`.

## Current state of secrets

All currently live as plain files under `/var/lib`, referenced from Nix modules:

| Secret | Path | Referenced in | Host(s) | Notes |
|---|---|---|---|---|
| Cloudflare API token | `/var/lib/caddy/caddy.env` | `services/caddy.nix:12`, `services/caddy-vps.nix:12` | both | env file, `CLOUDFLARE_DNS_API_TOKEN=...` |
| Tailscale auth key | `/var/lib/tailscale/auth-key` | `services/tailscale.nix:5`, `services/tailscale-vps.nix:5` | both | generated via `headscale preauthkeys create` on VPS |
| Paperless admin password | `/var/lib/paperless/admin-password` | `services/paperless.nix:5` | homelab | owned `paperless:paperless`, `600` |
| Vaultwarden env (ADMIN_TOKEN etc.) | `/var/lib/vaultwarden/vaultwarden.env` | `services/vaultwarden.nix:6` | homelab | owned `vaultwarden:vaultwarden`, `640` |
| Headplane cookie secret | `/var/lib/headplane/cookie-secret` | `services/headplane.nix:26` | hostinger | exactly 32 hex chars, no trailing newline |
| Headscale API key | (not on disk — pasted into Headplane UI) | — | hostinger | not a migration target |
| Headscale SQLite DB | `/var/lib/headscale/db.sqlite` | `services/headscale.nix:17` | hostinger | **data, not a secret — do not migrate** |

Per-host context for provisioning (perms, ownership, generation commands) is captured in `CONTEXT.md` lines 56-61 — do not duplicate, reference that file.

## Action plan

Strictly ordered to minimize lockout risk. Do not reorder. The user rebuilds/tests the system themselves — never build the system config (per `AGENTS.md`).

### Step 1 — Wire up sops-nix into the flake (no service changes)
- Add `sops-nix` flake input to `flake.nix`, following `nixpkgs`
- Add `sops-nix.nixosModules.sops` to the `modules` list for **both** `homelab` and `hostinger` nixosConfigurations
- Generate age keypairs on each host: `nix shell nixpkgs#age -c age-keygen -o /var/lib/sops-nix/age-keys.txt` (do this on the hosts, not in the repo)
- Create `.sops.yaml` at repo root with age public keys for each host, keyed by hostname. Use `creation_rules` matching per-host secret paths so each host can only decrypt its own secrets
- Add `/var/lib/sops-nix/age-keys.txt` to a `.gitignore`-style note in CONTEXT.md (it's on the hosts, not in the repo, but document it)
- Verify: `nix flake check` passes; user runs `nixos-rebuild test --flake .#homelab` and `.#hostinger`; confirm `systemctl status sops-nix` is active and `/run/secrets` exists (even if empty)
- **No secrets migrated yet.** This step only proves the decryption path works.

### Step 2 — Migrate low-risk homelab secrets first
Order within this step:
1. `paperless/admin-password` → `sops.secrets.paperless-admin-password.owner = "paperless"; mode = "0600"`; update `services/paperless.nix:5` to `passwordFile = config.sops.secrets.paperless-admin-password.path`
2. `vaultwarden/vaultwarden.env` → use `sops.templates.vaultwarden-env` if the env file has multiple keys, or a plain `sops.secrets.vaultwarden-env` if it's a single opaque blob; update `services/vaultwarden.nix:6` to `environmentFile = config.sops.templates.vaultwarden-env.path` (or the secret path)
3. `caddy/caddy.env` on homelab → `sops.secrets.caddy-env`; update `services/caddy.nix:12`
- For each: create the encrypted entry in `secrets/homelab.yaml` (or wherever the sops file lives), with content copied from the existing `/var/lib/...` file on the host
- Verify after each: `nixos-rebuild test --flake .#homelab`, restart the relevant service, confirm it comes up healthy (e.g. `systemctl status paperless`, `curl` the vhost)
- **Do not delete the old `/var/lib` files yet.** Two-path cutover until proven.

### Step 3 — Migrate homelab tailscale auth key
- `tailscale/auth-key` on homelab → `sops.secrets.tailscale-auth-key.neededForBoot = true` (homelab is reachable via LAN/physical, so lower risk than VPS)
- Update `services/tailscale.nix:5` to `authKeyFile = config.sops.secrets.tailscale-auth-key.path`
- Verify: `nixos-rebuild test --flake .#homelab`, `tailscale status` shows homelab authenticated to `vpn.veracoechea.com`
- Keep old `/var/lib/tailscale/auth-key` in place until verified

### Step 4 — Migrate hostinger low-risk secrets
- `caddy/caddy.env` on hostinger → `sops.secrets.caddy-env` in `secrets/hostinger.yaml`; update `services/caddy-vps.nix:12`
- `headplane/cookie-secret` → `sops.secrets.headplane-cookie-secret` (preserve exact format: 32 hex chars, no trailing newline — sops preserves file content as-is, but verify after decrypt); update `services/headplane.nix:26`
- Verify: `nixos-rebuild test --flake .#hostinger`, `systemctl status caddy headplane`, `curl https://network.veracoechea.com/admin` from a tailnet client
- Keep old files in place

### Step 5 — Migrate hostinger tailscale auth key (highest remaining risk)
- `tailscale/auth-key` on hostinger → `sops.secrets.tailscale-auth-key.neededForBoot = true` in `secrets/hostinger.yaml`
- Update `services/tailscale-vps.nix:5` to `authKeyFile = config.sops.secrets.tailscale-auth-key.path`
- Verify **before** deleting old file: `nixos-rebuild test --flake .#hostinger`, then `tailscale status` on the VPS shows it authenticated to `vpn.veracoechea.com`, then from a tailnet client confirm the VPS node is still visible and DERP relay is reachable
- Only after verification: delete `/var/lib/tailscale/auth-key` on hostinger

### Step 6 — Cleanup
- Delete all migrated `/var/lib/<service>/<secret>` files on both hosts (after step 2-5 are each verified in production for at least one reboot cycle)
- Update `CONTEXT.md` lines 56-61 to reflect that secrets are now in sops, not manually provisioned under `/var/lib`. Note the age key location (`/var/lib/sops-nix/age-keys.txt` on each host) and the `.sops.yaml` location
- Consider an ADR (`docs/adr/0003-secrets-via-sops-nix.md`) recording the decision and the boot-timing caveat

## Non-goals / explicit exclusions

- **Do not migrate the VPS public IP** (`168.231.68.183` and gateway/IPv6 in `hosts/hostinger/networking.nix`). It is not a secret; DHCP was tried and didn't work; gating it behind sops adds lockout risk for no benefit.
- **Do not migrate `headscale/db.sqlite`** — it's application data, not a secret.
- **Do not migrate the Headscale API key** — it's not stored on disk (pasted into Headplane UI).
- **Never build the system config** — the user does `nixos-rebuild test --flake .#<host>` themselves (per `AGENTS.md`).

## Suggested skills

- `tdd` — not applicable (NixOS config, no test harness beyond `nixos-rebuild test` and `nix flake check`)
- `domain-modeling` — consider updating `CONTEXT.md` glossary with sops-nix terms (`sops.secrets`, `sops.templates`, `age keypair`, `neededForBoot`) once the migration lands
- `grilling` — if the user wants to stress-test this plan before executing, the `grill-me` skill can pressure-test the migration order and risk analysis
- `to-issues` — this action plan could be broken into 6 GitHub issues (one per step) if the user wants to track execution in the issue tracker

## References

- `AGENTS.md` — repo guidelines (don't build, kebab-case files, `nix flake check`)
- `CONTEXT.md` lines 56-61 — current secret provisioning notes (perms, ownership, generation commands)
- `docs/adr/0002-split-plane-mesh-vpn.md` — mesh topology, why the VPS public IP exists
- `hosts/hostinger/networking.nix:14,22,28` — the static IP config that stays plaintext
- `services/tailscale.nix:5`, `services/tailscale-vps.nix:5` — tailscale auth key references
- `services/caddy.nix:12`, `services/caddy-vps.nix:12` — caddy env file references
- `services/paperless.nix:5` — paperless password file reference
- `services/vaultwarden.nix:6` — vaultwarden env file reference
- `services/headplane.nix:26` — headplane cookie secret reference
- `services/headscale.nix:17` — headscale DB path (not migrated)
