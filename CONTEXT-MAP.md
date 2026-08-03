# Context Map

## Contexts

- [Homelab flake](./CONTEXT.md) - multi-host NixOS configuration (hosts, services, tailnet)
- [Baby-shower invitation app](./apps/baby-shower/CONTEXT.md) - one-off invitation/RSVP app for one combined baby-shower + gender-reveal event

## Relationships

- **Baby-shower app → Homelab flake**: the app is packaged and deployed by the flake (nix-built OCI image, podman on hostinger, Caddy vhost `baby.veracoechea.com`)
