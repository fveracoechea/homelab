
This is a NixOS homelab config flake

## Guidelines
- Never build system config, the user should do it 
- Naming: Use descriptive function names, kebab-case for file names
- Comments: Minimal inline comments, prefer self-documenting code
- Test config: `nixos-rebuild test --flake .#homelab` or `.#hostinger`
- Check flake: `nix flake check`
- You can ssh into homelab host machine by doing "ssh homelab"

## Agent skills

### Issue tracker

Issues live as GitHub issues (uses `gh` CLI); external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout — `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
