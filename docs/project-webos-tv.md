# Project: LG webOS TV integration for Home Assistant

## Context

The homelab's Home Assistant instance (`services/home-assistant.nix`) manages BLE sensors, TP-Link smart plugs, ESPHome devices, and weather. This project adds control of an LG webOS TV: media playback, source selection, volume, on-screen notifications, and power-on via Wake-on-LAN.

Unlike the Z-Wave/Zigbee project, this needs no new hardware and no extra NixOS services. The `webostv` HA integration talks directly to the TV over the local network (TCP 3000/3001) using the `aiowebostv` Python library, which nixpkgs auto-resolves from the HA component package set.

## What changed in Nix

### `services/home-assistant.nix`

One line added to `extraComponents`:

```nix
"webostv" # LG webOS TV media player, notifications, and pairing
```

That is the entire Nix change. nixpkgs auto-resolves the Python dependency (`aiowebostv`, transitively `websockets`) via `home-assistant.getPackages` - no `extraPackages` entry needed. Verified against `nixpkgs#legacyPackages.x86_64-linux.home-assistant` (HA 2026.6.4): `webostv` is in `availableComponents`, and `getPackages "webostv"` returns `ps: with ps; [ aiowebostv ]`.

No new NixOS service, no secrets file, no firewall change. The integration connects outbound to the TV; the NixOS firewall allows outbound by default. Wake-on-LAN magic packets are outbound UDP to the subnet broadcast (port 9), also allowed.

### Companion components already in place

- `"default_config"` (line 10) - includes `ssdp`, so the TV is auto-discovered on the network via SSDP. No manual IP entry needed if discovery works.
- `"wake_on_lan"` (line 30) - provides the `wake_on_lan.send_magic_packet` action used by the turn-on automation (see below).

## TV-side setup (one-time, on the LG TV)

1. **Settings > Network > LG Connect Apps** - enable. This exposes the webOS API that HA talks to. Without it, pairing will not trigger a prompt on the TV.
2. **For Wake-on-LAN power-on** (webOS 3.0+): **Settings > General > Mobile TV On > Turn On Via WiFi** - enable. Reliable WoL needs the TV on **Ethernet**, not WiFi. WiFi WoL is flaky on many models. If the TV must be on WiFi, expect power-on to be unreliable and consider a smart plug with power-state sensing instead.
3. Give the TV a static DHCP lease / reserved IP (in your router or AdGuard Home) so the integration's host entry stays valid across reboots.
4. Note the TV's MAC address - needed for the WoL automation action below.

## HA integration path

### Step 1 - Rebuild (user does this)

```bash
nixos-rebuild test --flake .#homelab
```

The `webostv` component loads on next HA restart. No new NixOS service to verify - HA just gains the integration.

### Step 2 - Add the integration in HA UI

1. **Settings > Devices & services > Add Integration > LG webOS TV**.
2. If SSDP discovery found the TV, it will appear as "Discovered" - accept it. Otherwise enter the TV's IP manually.
3. A pairing prompt appears on the TV. Accept it with the remote.
4. The media_player entity is created (e.g. `media_player.lg_webos_<tv_name>`).

If pairing fails: confirm **LG Connect Apps** is enabled (TV settings), and that HA and the TV are on the same L2 network (same subnet, same VLAN). If on different subnets, add a firewall rule allowing HA -> TV on TCP 3000 and 3001.

### Step 3 - Configure sources (optional, while TV is on)

On the integration card, click **CONFIGURE** and select which sources (HDMI inputs, apps) the media player offers. If you skip this, all sources are offered.

### Step 4 - Create the turn-on automation (critical since HA 2025.11)

As of HA 2025.11, webOS TV media_player entities show as `unavailable` (not `off`) when the TV is off, unless HA knows how to turn it on. Without this automation you cannot power on from HA, and automations that key off the TV state will break. This was a breaking change that caught many users (see HA core issue #155884).

Create the automation from the UI:

1. Go to the webostv device in HA (Settings > Devices & services > LG webOS TV > <your TV>).
2. Click the **+** next to Automations, select the **"Device is requested to turn on"** trigger.
3. Add an action: **Call service > wake_on_lan.send_magic_packet** with:
   - `mac`: the TV's MAC address (e.g. `AA:BB:CC:DD:EE:FF`)
   - `broadcast_address`: your subnet broadcast (e.g. `10.0.0.255`)
   - `broadcast_port`: `9`

Equivalent YAML (for reference; create via UI to avoid hand-editing `/var/lib/hass/automations.yaml`):

```yaml
alias: Turn on LG TV (WoL)
triggers:
  - trigger: device
    domain: webostv
    device_id: <device_id>
    type: turn_on
actions:
  - action: wake_on_lan.send_magic_packet
    data:
      mac: AA:BB:CC:DD:EE:FF
      broadcast_address: 10.0.0.255
      broadcast_port: 9
```

After saving, the media_player should show `off` (not `unavailable`) when the TV is off, and the power button in the HA UI will work.

### Step 5 - Notifications (optional)

The integration creates a `notify.<tv_name>` action for on-screen popups. Example automation (laundry done, doorbell, etc.):

```yaml
action: notify.lg_webos_<tv_name>
data:
  message: "Laundry is done"
  # icon: /var/lib/hass/icons/washer.png  # optional, must be a local file HA can read
```

The icon (if used) must be a local file accessible to HA, not a web URL. The integration encodes it into the notification. Most newer firmware ignores the icon parameter and only shows the message.

## What you get

- `media_player.lg_webos_<tv_name>` - play/pause/stop, volume/mute, source selection, media info
- `notify.lg_webos_<tv_name>` - on-screen notifications
- Power on via the WoL automation
- SSDP auto-discovery on the local network

## Known issues

- **webOS 26 beta** (June 2026) broke the integration for some users (HA core issue #172703). If the TV is on a webOS 26 beta build and pairing fails, check for HA updates or downgrade the TV firmware.
- **Pairing fails, no prompt on TV** - almost always means **LG Connect Apps** is off. Re-check Settings > Network.
- **WoL does not work on WiFi** - use Ethernet. On 2017+ models also enable Settings > General > Mobile TV On > Turn On Via WiFi. If WoL is still unreliable, use a smart plug with power-state sensing and a `device is requested to turn on` automation that toggles the plug.
- **TV shows `unavailable` when off** - you missed Step 4 (the turn-on automation). Without it HA marks the entity unavailable because it has no way to power on.
- **Icon parameter ignored** - most newer firmware only shows the message text. Don't rely on custom icons.

## Non-goals / explicit exclusions

- **No HACS / custom components** - the native `webostv` integration covers media playback, notifications, and power-on. The popular `LG-WebOS-Remote-Control` HACS card (madmicio) adds a dashboard remote UI but requires setting up HACS, which this repo doesn't have today. Add later if a UI remote is wanted; it pairs cleanly with the native integration once the turn-on automation exists.
- **No new NixOS service** - unlike Z-Wave (which needs `services.zwave-js`), the webOS integration is self-contained in HA.
- **No secrets file** - the pairing key is generated at pairing time and persisted to `/var/lib/hass/.storage/`. Follows the existing HA pattern (no pre-created secrets, per ADR-0003 and CONTEXT.md line 25).
- **Never build the system config** - the user does `nixos-rebuild test --flake .#homelab` themselves (per `AGENTS.md`).

## References

- `AGENTS.md` - repo guidelines (don't build, `nix flake check`, `nixos-rebuild test`)
- `CONTEXT.md` line 25 - Home Assistant glossary entry
- `services/home-assistant.nix` - HA config with `webostv` in `extraComponents`
- `docs/adr/0003-secrets-in-var-lib-not-sops.md` - secrets pattern (HA needs none)
- HA webOS TV integration docs: https://www.home-assistant.io/integrations/webostv/
- HA 2025.11 breaking change (turn-on automation): https://github.com/home-assistant/core/issues/155884
- webOS 26 beta breakage: https://github.com/home-assistant/core/issues/172703
- HA Wake-on-LAN integration: https://www.home-assistant.io/integrations/wake_on_lan/
