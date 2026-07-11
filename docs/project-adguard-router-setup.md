# Project: AdGuard Home + ASUS RT-BE82U router

## Context

The homelab runs AdGuard Home (`services/adguardhome.nix`) as a network-wide ad-blocking DNS server, bound to `10.0.0.2:53`. It works over the LAN (`enp8s0`) and the Tailscale mesh (`tailscale0`). Tailnet devices get ad-blocking automatically via Headscale's `nameservers.global = ["10.0.0.2"]` config.

The remaining gap is LAN devices that can't run Tailscale (smart TVs, IoT, game consoles). The Xfinity-provided gateway doesn't allow changing DHCP DNS settings, so a third-party router is needed to set the DHCP DNS to `10.0.0.2` for all LAN devices.

This document captures the router choice, the AdGuard DNS setup, and the physical + config steps to perform once the router arrives.

## Hardware

### Router: ASUS RT-BE82U

- Wi-Fi 7 (802.11be) dual-band, BE6500 (up to 6500 Mbps combined)
- **Five 2.5GbE ports**: 1x WAN + 4x LAN
- USB 3.2 Gen 1 port
- AiProtection Pro (free, no subscription), AiMesh, parental controls
- Custom DHCP DNS supported (under ASUS admin > LAN > DHCP Server)
- TAA-compliant option available

### Why this router

1. **Five 2.5GbE ports** - the homelab gets a 2.5x wired speed boost over gigabit. Future-proof without paying for 10GbE switches.
2. **Custom DHCP DNS** - required to point LAN devices at AdGuard Home (`10.0.0.2`). The Xfinity gateway can't do this.
3. **Wi-Fi 7** - future-proof for when more devices support it. Backwards compatible with Wi-Fi 6/5/4.
4. **ASUS firmware** - reliable, regularly updated, Merlin-compatible, no subscriptions for security features.

## Network topology

```
Xfinity modem (bridge mode)
  └─ ASUS RT-BE82U (router, DHCP, DNS -> 10.0.0.2)
       ├─ LAN port 1 -> homelab (10.0.0.2, static DHCP reservation)
       ├─ LAN port 2 -> other wired devices
       └─ Wi-Fi -> phones, laptops, smart TV, IoT
```

The Xfinity gateway goes into **Bridge Mode** - it becomes a plain modem, passing the public IP to the ASUS router's WAN port.

## Router settings

### LAN configuration

| Setting | Value | Notes |
|---|---|---|
| LAN IP | `10.0.0.1` | Router's gateway address |
| Subnet mask | `255.255.255.0` | Same as `10.0.0.0/24` referenced throughout the NixOS config |
| DHCP server | Enabled | |
| DHCP pool start | `10.0.0.100` | Reserve low range for static assignments |
| DHCP pool end | `10.0.0.250` | |
| Primary DNS | `10.0.0.2` | AdGuard Home on the homelab |
| Secondary DNS | `1.1.1.1` | Cloudflare fallback (if homelab is down) |

### DHCP reservation for homelab

Reserve `10.0.0.2` for the homelab's MAC address (find with `ip link show enp8s0` on the homelab). This ensures the homelab always gets the same IP that AdGuard binds to and that the Tailscale subnet route advertises.

### Wi-Fi settings

- **SSID**: same as current Xfinity network (so devices reconnect without reconfiguration) or a new name (cleaner, but requires manual reconnect)
- **2.4 GHz channel**: 1, 6, or 11 (non-overlapping)
- **5 GHz channel**: 36-48 or 149-161 (DFS channels 52-144 can cause issues with some devices)
- **Security**: WPA3-Personal (or WPA2/WPA3 mixed if older devices need it)

## AdGuard Home DNS setup (already in NixOS config)

### What's already configured

From `services/adguardhome.nix`:

| Setting | Value |
|---|---|
| DNS bind address | `10.0.0.2:53` |
| Web UI | `127.0.0.1:8082` (proxied by Caddy at `adguard.veracoechea.com`) |
| Upstream DNS (DoT) | `1.1.1.1#cloudflare-dns.com`, `1.0.0.1#cloudflare-dns.com`, `9.9.9.9#dns.quad9.net`, `149.112.112.112#dns.quad9.net` |
| Bootstrap DNS | `1.1.1.1`, `9.9.9.9` |
| Filtering | Enabled (protection + ad blocking) |
| Starter blocklists | AdGuard HostlistsRegistry filters 9 (malware) and 11 (malicious URLs) |
| Mutable settings | `true` (web UI changes persist in `/var/lib/adguardhome/`) |
| Firewall | `53/udp` open on `enp8s0` and `tailscale0` |

### Tailnet DNS (already configured)

From `services/headscale.nix`:

| Setting | Value |
|---|---|
| `dns.nameservers.global` | `["10.0.0.2"]` (was `["1.1.1.1"]`) |

All tailnet devices automatically use AdGuard Home for DNS. Tailscale's local proxy (`100.100.100.100`) intercepts the device's DNS and forwards to `10.0.0.2:53` through the mesh.

### Homelab self-DNS exclusion (already configured)

From `services/tailscale.nix`:

| Setting | Value |
|---|---|
| `extraUpFlags` | `["--login-server=https://vpn.veracoechea.com" "--accept-dns=false"]` |

The homelab does NOT use AdGuard as its system DNS. This avoids a boot-order dependency where DNS resolution fails until AdGuard Home starts.

## DNS flow after setup

### LAN device (smart TV, laptop on WiFi)

```
device -> DHCP DNS (10.0.0.2) -> AdGuard Home (enp8s0, 53/udp)
  -> filters ads -> forwards to Cloudflare/Quad9 (DoT)
```

### Phone on cellular (Tailscale connected)

```
phone -> 100.100.100.100 (Tailscale local proxy)
  -> Tailscale daemon forwards to 10.0.0.2:53 (via mesh tunnel)
  -> AdGuard Home (tailscale0, 53/udp)
  -> filters ads -> forwards to Cloudflare/Quad9 (DoT)
```

### Phone on home WiFi (Tailscale connected)

```
phone -> 100.100.100.100 (Tailscale shadows DHCP DNS)
  -> Tailscale daemon forwards to 10.0.0.2:53 (via mesh tunnel, local)
  -> AdGuard Home (tailscale0, 53/udp)
  -> filters ads -> forwards to Cloudflare/Quad9 (DoT)
```

AdGuard is hit exactly once in every scenario. No double-querying.

## Action plan

Strictly ordered. The user rebuilds/tests the system themselves - never build the system config (per `AGENTS.md`).

### Step 1 - NixOS config (DONE)

The following files have been committed:

- `services/adguardhome.nix` - AdGuard Home service, Caddy vhost, firewall rules
- `hosts/homelab/configuration.nix` - import added
- `services/headscale.nix` - `nameservers.global` changed to `["10.0.0.2"]`
- `services/tailscale.nix` - `--accept-dns=false` added to `extraUpFlags`
- `CONTEXT.md` - glossary, layout, and notes updated

`nix flake check` passes. Commit: `b88cf83 add adguard home DNS ad-blocker with tailscale and lan support`.

### Step 2 - Rebuild homelab and VPS (user does this)

```bash
# On the homelab
nixos-rebuild test --flake .#homelab

# On the hostinger VPS
nixos-rebuild test --flake .#hostinger
```

Verify on the homelab:
- `systemctl status adguardhome` is active
- `ss -ulnp | grep ':53'` shows AdGuard listening on `10.0.0.2:53`
- Visit `https://adguard.veracoechea.com` - you should see the AdGuard onboarding wizard
- Complete the wizard: set admin username and password

Verify on the VPS:
- `systemctl status headscale` is active
- Headscale config reflects `nameservers.global = ["10.0.0.2"]`

### Step 3 - Physical router setup (user does this once router arrives)

1. **Put Xfinity gateway in Bridge Mode**
   - Go to `http://10.0.0.1`
   - Log in (admin / password on the router sticker)
   - Gateway > At a Glance > Bridge Mode > Enable
   - Wait for the gateway to reboot (2-3 min)

2. **Connect the ASUS router**
   - Plug an Ethernet cable from the Xfinity gateway's Ethernet port to the ASUS router's WAN port (the 2.5G WAN port)
   - Power on the ASUS router
   - Wait for it to boot (power LED solid, ~2 min)

3. **Log into the ASUS router**
   - Connect a device to the ASUS router (via Wi-Fi or Ethernet)
   - Open `http://router.asus.com` or `http://192.168.50.1` (default ASUS LAN IP)
   - Walk through the initial setup wizard (set admin password)

### Step 4 - Configure ASUS router LAN + DNS (user does this)

In the ASUS admin interface:

1. **LAN > LAN IP**
   - Set LAN IP to `10.0.0.1`
   - Subnet mask: `255.255.255.0`

2. **LAN > DHCP Server**
   - Enable DHCP server
   - IP pool start: `10.0.0.100`
   - IP pool end: `10.0.0.250`
   - **DNS Server 1: `10.0.0.2`** (AdGuard Home)
   - DNS Server 2: `1.1.1.1` (fallback)
   - Apply

3. **DHCP reservation for homelab**
   - Find the homelab's MAC address: `ip link show enp8s0` on the homelab (look for `link/ether`)
   - In ASUS admin: Network Map > Client List > click the homelab > enable "Bind MAC to IP" and set IP to `10.0.0.2`
   - Alternatively: LAN > DHCP Server > Manual Assignment > add MAC -> `10.0.0.2`

4. **Verify the homelab gets the right IP**
   - On the homelab: `ip addr show enp8s0` - should show `10.0.0.2`
   - If not, reboot the homelab or run `sudo nmcli connection reload` to get a new DHCP lease

### Step 5 - Configure Wi-Fi (user does this)

In the ASUS admin interface:

1. **General > Wireless**
   - Set SSID (use the same SSID as your old Xfinity network for zero-reconnect, or a new name for a clean start)
   - 2.4 GHz: set security to WPA2/WPA3 Mixed
   - 5 GHz: set security to WPA2/WPA3 Mixed

2. **Channels**
   - 2.4 GHz: pick 1, 6, or 11
   - 5 GHz: pick 36-48 or 149-161 (avoid DFS channels 52-144)

3. Apply and let the router reboot the radios

### Step 6 - Verify AdGuard is receiving queries (user does this)

1. **From a LAN device** (phone on WiFi, laptop on Ethernet):
   ```bash
   nslookup google.com
   ```
   Should resolve via `10.0.0.2` (AdGuard). Check the AdGuard query log at `https://adguard.veracoechea.com` - you should see the query appear.

2. **Test ad-blocking**:
   ```bash
   nslookup doubleclick.net 10.0.0.2
   ```
   Should return `0.0.0.0` (blocked by AdGuard).

3. **Check the AdGuard dashboard**
   - Go to `https://adguard.veracoechea.com`
   - Dashboard should show queries coming in from LAN devices
   - Query log should show a mix of "Processed" and "Blocked" entries

4. **From a tailnet device** (phone on cellular with Tailscale on):
   ```bash
   nslookup google.com
   ```
   Should resolve via `100.100.100.100` -> `10.0.0.2`. Check the AdGuard query log - the query should appear from the `tailscale0` interface.

### Step 7 - Add more blocklists (user does this in AdGuard web UI)

The Nix config includes two starter blocklists (malware + malicious URLs). For actual ad-blocking, add more via the AdGuard web UI:

1. Go to `https://adguard.veracoechea.com` > Filters > DNS blocklists
2. Click "Add blocklist"
3. Recommended starter blocklists:
   - **AdGuard DNS filter** - `https://adguardteam.github.io/AdGuardDNSFilter/Filters/filter.txt` (the main AdGuard filter, blocks ads + trackers)
   - **Haase filter** - `https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt` (general ads)
   - **Dan Pollock's hosts file** - `https://someonewhocares.org/hosts/zero/hosts` (ads + tracking + telemetry)
   - **StevenBlack Unified** - `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` (ads + malware + fakenews)
4. These persist across restarts via `mutableSettings = true` - they live in `/var/lib/adguardhome/` and aren't overwritten by Nix on rebuild

## Non-goals / explicit exclusions

- **Do not open port 53 on the public internet** - AdGuard DNS is reachable only via LAN (`enp8s0`) and tailnet (`tailscale0`). The homelab is behind Xfinity NAT regardless.
- **Do not change the homelab's system DNS** - `--accept-dns=false` in `services/tailscale.nix` prevents the homelab from using AdGuard as its own resolver, avoiding a boot-order dependency.
- **Do not use DoH (DNS-over-HTTPS) via Caddy** - Option B was considered but Option A (direct DNS via Tailscale) is simpler and automatic for all tailnet devices.
- **Do not use the router's built-in VPN** - the homelab already has Tailscale for remote access. The ASUS router's VPN server/client features are redundant.
- **Never build the system config** - the user does `nixos-rebuild test --flake .#homelab` and `nixos-rebuild test --flake .#hostinger` themselves (per `AGENTS.md`).

## Suggested skills

- `diagnosing-bugs` - if DNS queries don't reach AdGuard, or the router's DHCP DNS doesn't propagate to devices
- `grilling` - if the user wants to stress-test this plan before the router arrives (e.g., "what if the homelab doesn't get 10.0.0.2?", "what if bridge mode doesn't work on the Xfinity gateway?")
- `domain-modeling` - update `CONTEXT.md` glossary with router terms (`ASUS RT-BE82U`, `bridge mode`, `DHCP DNS`) if this becomes a recurring reference

## References

- `AGENTS.md` - repo guidelines (don't build, kebab-case files, `nix flake check`, `nixos-rebuild test`)
- `CONTEXT.md` - AdGuard Home glossary entry, layout, and notes (lines 28-29, 47, 72)
- `services/adguardhome.nix` - AdGuard Home service config
- `services/headscale.nix` - Headscale DNS config (`nameservers.global`)
- `services/tailscale.nix` - `--accept-dns=false` flag
- ASUS RT-BE82U tech specs: https://www.asus.com/us/networking-iot-servers/wifi-routers/asus-wifi-routers/rt-be82u/techspec/
- ASUS RT-BE82U product page: https://www.asus.com/us/networking-iot-servers/wifi-routers/asus-wifi-routers/rt-be82u/
- NixOS AdGuard Home wiki: https://wiki.nixos.org/wiki/Adguard_Home
- AdGuard Home configuration docs: https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration
