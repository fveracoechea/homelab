# Split-plane mesh VPN: Headscale on VPS, Tailscale client on homelab

The homelab is behind Xfinity residential NAT — no public IP, no inbound connectivity. A VPS at Hostinger provides the public endpoint. We run Headscale (self-hosted Tailscale control plane) on the VPS and the Tailscale client on the homelab. The homelab joins the tailnet and advertises the `10.0.0.0/24` LAN subnet as a route, so tailnet clients can reach both the homelab's tailnet IP and LAN devices. The VPS also runs an embedded DERP relay for NAT traversal fallback.

## Considered Options

- **Tailscale SaaS** (rejected) — works but depends on Tailscale's cloud control plane; we wanted full self-hosted control over the tailnet, user accounts, and node lifecycle.
- **Expose services directly on the VPS** (rejected) — the VPS is a lightweight Hostinger box; running Paperless, Immich, Vaultwarden there would strain resources and put all eggs in one public basket. Keeping services on the homelab (behind NAT, reachable via mesh) is more secure and cost-effective.
- **WireGuard manual mesh** (rejected) — no MagicDNS, no embedded DERP, no web UI for node management. Headscale gives us the Tailscale client experience (automatic NAT traversal, MagicDNS, key rotation) without the SaaS dependency.
- **Split-plane: Headscale on VPS, services on homelab** (chosen) — VPS only runs the control plane + DERP relay (lightweight); homelab runs all services and joins via Tailscale client. Best of both: public reachability via VPS, compute stays on the homelab.

## Consequences

- The VPS must always be up for new nodes to join the tailnet (existing nodes keep working if the control plane is briefly down, but new joins and key rotations need it).
- DNS: `vpn.veracoechea.com` and `network.veracoechea.com` point at the VPS public IP; `*.veracoechea.com` (wildcard) points at the homelab's tailnet IP `100.64.0.1` via Cloudflare. The wildcard catches all homelab services; explicit records override it for VPS-hosted endpoints.
- The homelab's Tailscale config uses `extraUpFlags` for `--login-server` (passed to `tailscale up`) and `extraSetFlags` for `--advertise-routes` (passed to `tailscale set`). These are not interchangeable — `--login-server` is not a valid `tailscale set` flag.
- If a node was previously joined to a different login server (e.g., Tailscale SaaS), a one-time `sudo tailscale up --reset --login-server=https://vpn.veracoechea.com ...` is needed to reconcile state.
