
This is a NixOS homelab config flake

## Guidelines
- Never build system config, the user should do it 
- Naming: Use descriptive function names, kebab-case for file names
- Comments: Minimal inline comments, prefer self-documenting code
- Test config: `nixos-rebuild test --flake .#homelab` 
- Check flake: `nix flake check`
