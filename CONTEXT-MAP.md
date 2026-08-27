# Context Map

## Contexts

- [Homelab flake](./CONTEXT.md) - multi-host NixOS configuration (hosts, services, tailnet)
- [Baby-shower invitation app](https://github.com/fveracoechea/baby-shower) - one-off invitation/RSVP app for one combined baby-shower + gender-reveal event (separate repo; glossary in its CONTEXT.md)

## Relationships

- **Baby-shower app → Homelab flake**: the app lives in `github:fveracoechea/baby-shower`; the flake packages a pinned revision of it into a nix-built OCI image (podman on hostinger, Caddy vhost `baby.veracoechea.com`)
