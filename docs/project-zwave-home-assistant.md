# Project: Z-Wave integration for Home Assistant

## Context

The homelab's Home Assistant instance (`services/home-assistant.nix`) currently manages BLE sensors, TP-Link smart plugs, ESPHome devices, and weather - but has no Z-Wave capability. The user has a Honeywell T6 Pro TH6320ZW Z-Wave thermostat that needs to be integrated. This document captures the research, protocol decision, and action plan for adding Z-Wave to the NixOS homelab.

The thermostat is the immediate driver, but the setup should support future Z-Wave devices (locks, switches, sensors) without rework.

## Hardware

### Thermostat: Honeywell T6 Pro TH6320ZW
- Z-Wave 500-series (ZM5202AU chipset), S2 unauthenticated encryption
- Two sub-models exist:
  - **TH6320ZW2003** (older) - S0 security, no SmartStart
  - **TH6320ZW2007** (newer) - S2 unauthenticated + SmartStart (QR code on back/box)
- User should check which model they have (label on thermostat or box) - affects pairing method
- Battery-powered (3x AA) or C-wire (24 VAC). If battery-only, it's a Listening Sleeping Slave (no mesh repeating). If C-wire, it's an Always On Slave (repeats Z-Wave traffic)
- Controls up to 3H/2C heat pump or 2H/2C conventional; reports indoor humidity (display only, no humidification control)
- Onboard schedule cannot be changed via Z-Wave - automate in HA instead

### Controller stick: Aeotec Z-Stick 7 (not yet purchased)
- Model ZWA010, ASIN B094NW5B68
- Amazon: https://www.amazon.com/Controller-SmartStart-Raspberry-Compatible-Assistant/dp/B094NW5B68
- ~$50.99 new / $35.99 used (as of Jul 2026)
- Z-Wave 700-series, S2 security, SmartStart, Z-Wave Plus V2 certified
- Built-in chip antenna (no external antenna needed)
- USB; works with Linux/Raspberry Pi/Home Assistant
- 4.5/5 stars, 255 reviews

## Protocol decision: Z-Wave (not Zigbee or Matter/Thread)

Research concluded Z-Wave is the right protocol for this setup. Rationale:

1. **Thermostat locks the choice** - the TH6320ZW is Z-Wave-only hardware. No firmware update adds Matter or Zigbee. The protocol decision is made by the existing device.

2. **908.42 MHz US-exclusive spectrum** - the FCC allocated this sub-GHz band specifically for Z-Wave. No Wi-Fi, Bluetooth, or Zigbee competition. This matters in a GA detached home where the 2.4 GHz band is already crowded with Wi-Fi, Bluetooth, and USB 3 noise.

3. **GA construction (wood frame + drywall)** - Z-Wave's sub-GHz signal penetrates 3+ walls reliably at 30-100m per hop. Zigbee/Thread (2.4 GHz) typically die after 1-2 walls and need a denser mesh of repeaters.

4. **NixOS module maturity** - `services.zwave-js` is native nixpkgs, well-tested, with clean options for serial port, secrets, and settings. The `openthread-border-router` module (for Matter/Thread) merged in March 2026 (nixpkgs PR #502388) and is still bleeding edge, requiring IPv6 forwarding config and a Thread border router dongle.

5. **HVAC reliability matters** - Z-Wave's stricter certification (cross-vendor interoperability testing required before retail) means fewer "my thermostat stopped responding" surprises. The thermostat is a device you want to "just work."

6. **Insurance discounts** - State Farm, Allstate, and Liberty Mutual offer 5-15% discounts for monitored Z-Wave security (relevant if locks/sensors are added later).

### Future protocols (not in scope now)

- **Zigbee** - worth adding later for cheap sensors/lights ($8-25 vs $40-80 per Z-Wave device). Different frequency (2.4 GHz) so coexists with Z-Wave. Would need a $20 SONOFF Zigbee dongle alongside the Z-Stick 7.
- **Matter/Thread** - the future direction, but not production-ready for this NixOS setup in 2026. Device ecosystem is 1/4 the size of Z-Wave, requires IPv6 (19% of US ISP routers still block it per FCC 2026 data), and the NixOS OTBR module is too new. Revisit in 2027-2028.

## NixOS `services.zwave-js` module

Key nixpkgs options (confirmed via nix-mcp):

| Option | Type | Default | Notes |
|---|---|---|---|
| `services.zwave-js.enable` | bool | `false` | Enable zwave-js-server on boot |
| `services.zwave-js.serialPort` | absolute path | (none) | Use `/dev/serial/by-id/...` not `/dev/ttyUSB0` for reboot stability |
| `services.zwave-js.port` | uint16 | `3000` | WebSocket port for the server |
| `services.zwave-js.secretsConfigFile` | absolute path | (none) | JSON file with security keys. Must NOT be in nix store (world-readable) |
| `services.zwave-js.settings` | JSON submodule | `{}` | Non-secret config, combined with secretsConfigFile |
| `services.zwave-js.package` | package | (nixpkgs) | The zwave-js-server package |
| `services.zwave-js.extraFlags` | list of string | `[]` | Extra CLI flags |

### Secrets file format

`services.zwave-js.secretsConfigFile` expects a JSON file with this shape:

```json
{
  "securityKeys": {
    "S0_Legacy": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "S2_Unauthenticated": "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
    "S2_Authenticated": "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
    "S2_AccessControl": "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"
  }
}
```

Generate keys with: `< /dev/urandom tr -dc A-F0-9 | head -c32 ;echo` (one per key, 32 hex chars each).

This file must live outside the nix store (which is world-readable). Recommended path: `/var/lib/zwave-js/secrets.json`, consistent with the existing pattern of secrets under `/var/lib/<service>/` (see `CONTEXT.md` notes).

## HA integration path

Unlike the HAOS add-on flow (which bundles the Z-Wave JS server), NixOS runs `services.zwave-js` as a standalone server process. HA connects to it over WebSocket.

1. NixOS runs `services.zwave-js` on port 3000 (default)
2. In HA web UI: Settings > Devices & Services > Add Integration > Z-Wave
3. **Uncheck** "Use the Z-Wave add-on" (we're not on HAOS)
4. Enter WebSocket URL: `ws://localhost:3000`
5. HA detects the server, creates the integration
6. Add the thermostat via Z-Wave JS panel:
   - If TH6320ZW2007 (SmartStart): scan the QR code on the back of the thermostat
   - If TH6320ZW2003: put thermostat in inclusion mode (MENU > Z-WAVE SETUP > START INCLUDING), then click "Add Node" in HA

### HA component

`zwave_js` is part of `default_config` (already enabled in `services/home-assistant.nix:10`), but it should be explicitly added to `extraComponents` to ensure it's bundled even if `default_config` changes. This is a one-line addition.

## Known issues with TH6320ZW in Home Assistant

From GitHub issues on home-assistant/core:

1. **Set temperature attribute not updating** (issue #77579) - Z-Wave JS 0.1.66-0.1.68 had a bug where the setpoint attribute stayed stale after changing it via HA. Fixed in HA 2022.9 (zwave-js-server-python PR #480). Current HA versions are unaffected.

2. **AC mains disconnected sensor** (issue #160029) - The `binary_sensor.t6_pro_..._ac_mains_disconnected` fires even when the thermostat is on 24V C-wire. Community consensus: this sensor is unreliable for this device. Ignore it or suppress it in HA.

3. **Mode not updating from panel to app** (issue #161075) - Changing mode (heat/off/cool) at the thermostat panel sometimes doesn't reflect in the HA UI immediately. Usually a polling/interview issue - re-interview the node in Z-Wave JS settings. Standby users report the T6 works fine; this was a support issue, not a code bug.

4. **Split setpoints** - HA may represent heat and cool setpoints as separate entities rather than a single combined climate entity. This is normal for Z-Wave thermostats - control them individually or use HA automations to coordinate.

5. **Onboard schedule** - cannot be changed via Z-Wave. Use HA automations (schedule helper + input_number helpers for temperatures) instead.

## Action plan

Strictly ordered. The user rebuilds/tests the system themselves - never build the system config (per `AGENTS.md`).

### Step 1 - Hardware setup (user does this)

- Buy Aeotec Z-Stick 7 (ASIN B094NW5B68)
- Plug into homelab box via a USB extension cable (3-6 ft) to move the stick away from the metal case and Wi-Fi interference
- Identify the stable device path:
  ```
  ls -l /dev/serial/by-id/
  ```
  Look for a symlink like `usb-0658_0200-if00` (Aeotec Gen5 vendor/product) or similar. The Z-Stick 7 (700-series) may use a different vendor/product ID - check with:
  ```
  dmesg | grep tty
  udevadm info -a -n /dev/ttyACM0 | grep '{idVendor}\|{idProduct}'
  ```
- Record the full `/dev/serial/by-id/usb-...` path for the NixOS config

### Step 2 - Generate Z-Wave security keys (user does this on the host)

```bash
mkdir -p /var/lib/zwave-js
cat > /var/lib/zwave-js/secrets.json << 'EOF'
{
  "securityKeys": {
    "S0_Legacy": "$(head -c16 /dev/urandom | xxd -p)",
    "S2_Unauthenticated": "$(head -c16 /dev/urandom | xxd -p)",
    "S2_Authenticated": "$(head -c16 /dev/urandom | xxd -p)",
    "S2_AccessControl": "$(head -c16 /dev/urandom | xxd -p)"
  }
}
EOF
chmod 600 /var/lib/zwave-js/secrets.json
```

Or generate each key individually: `< /dev/urandom tr -dc A-F0-9 | head -c32 ;echo` (32 hex chars = 16 bytes).

File must NOT be in the nix store (world-readable). `/var/lib/zwave-js/secrets.json` follows the existing pattern (see `CONTEXT.md` notes for other secrets under `/var/lib/<service>/`).

### Step 3 - NixOS config changes (agent does this, user builds)

Edit `services/home-assistant.nix` to add the Z-Wave JS server alongside the existing HA config:

- Add `services.zwave-js.enable = true;`
- Add `services.zwave-js.serialPort = "/dev/serial/by-id/usb-...";` (actual by-id path from step 1)
- Add `services.zwave-js.secretsConfigFile = "/var/lib/zwave-js/secrets.json";`
- Add `"zwave_js"` to `services.home-assistant.extraComponents` (ensure it's bundled even if default_config changes)

Optional (if device permissions are an issue):
- Add a udev rule in `hosts/homelab/configuration.nix` to set stable permissions on the serial device. Only needed if the zwave-js user can't access the device by default. The `services.zwave-js` module should handle this, but if not:
  ```
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0658", ATTRS{idProduct}=="0200", MODE="0660", GROUP="dialout", SYMLINK+="zwave0"
  '';
  ```
  (Adjust vendor/product IDs for the Z-Stick 7 if different from Gen5's `0658:0200`)

Verify:
- `nix flake check` passes
- User runs `nixos-rebuild test --flake .#homelab`
- Confirm `systemctl status zwave-js` is active
- Confirm the server is listening: `ss -tlnp | grep 3000`

### Step 4 - HA UI setup (user does this in web UI)

- Go to Settings > Devices & Services > Add Integration > Z-Wave
- Uncheck "Use the Z-Wave add-on"
- Enter WebSocket URL: `ws://localhost:3000`
- HA detects the server and creates the integration

### Step 5 - Pair the thermostat (user does this)

- If TH6320ZW2007 (SmartStart): scan the QR code on the back of the thermostat using the HA Z-Wave JS panel's SmartStart scanner
- If TH6320ZW2003: put thermostat in inclusion mode:
  - On thermostat: MENU > Z-WAVE SETUP > START INCLUDING
  - In HA: Z-Wave JS panel > Add Node
- Wait for inclusion to complete (the thermostat should appear as a node in the Z-Wave JS panel)
- Re-interview the node if entities don't populate immediately

### Step 6 - Verify

- Thermostat should appear as a climate entity in HA
- Test temperature setpoint changes in both directions:
  - Change setpoint in HA - verify it changes on the thermostat's physical display
  - Change setpoint on the thermostat - verify HA reflects the change (may take a few seconds for battery-powered devices)
- Test mode changes (heat/cool/off/auto) from HA UI
- Verify humidity sensor entity appears (TH6320ZW reports indoor relative humidity)
- If setpoint or mode sync is flaky, re-interview the node in Z-Wave JS settings

## Non-goals / explicit exclusions

- **Do not add Zigbee or Matter/Thread** in this project. Those are future enhancements with their own research. Adding them now complicates the Z-Wave setup and introduces 2.4 GHz channel planning that isn't needed yet.
- **Do not buy a Z-Wave Long Range (800-series) stick** unless the thermostat is far from the server. The 700-series Z-Stick 7 covers a typical GA home. LR sticks (Zooz ZST39) are $10 more and the LR star topology doesn't mesh - every device must reach the stick directly.
- **Do not use the HA Z-Wave JS add-on** - that's HAOS-only. NixOS uses `services.zwave-js` as a standalone server.
- **Never build the system config** - the user does `nixos-rebuild test --flake .#homelab` themselves (per `AGENTS.md`).
- **Do not commit the security keys to git** - the secrets file lives at `/var/lib/zwave-js/secrets.json` on the host, not in the repo. If sops-nix migration happens (see `handoff-sops-nix-migration.md`), the keys can be moved there later.

## Suggested skills

- `diagnosing-bugs` - if the thermostat doesn't pair or shows the known setpoint-update bug after setup
- `codebase-design` - if considering how to structure the zwave-js config (secrets file location, udev rules, module organization)
- `grilling` - if the user wants to stress-test this plan before executing (e.g., "what if the stick isn't detected?", "what if S2 pairing fails?")
- `to-issues` - this action plan could be broken into 6 GitHub issues (one per step) if the user wants to track execution in the issue tracker
- `domain-modeling` - update `CONTEXT.md` glossary with Z-Wave terms (`zwave-js-server`, `by-id serial path`, `S2 security keys`, `SmartStart inclusion`) once the integration lands

## References

- `AGENTS.md` - repo guidelines (don't build, kebab-case files, `nix flake check`, `nixos-rebuild test`)
- `CONTEXT.md` line 25 - Home Assistant glossary entry (current state, no Z-Wave)
- `CONTEXT.md` lines 62-70 - notes on secret provisioning pattern under `/var/lib/<service>/`
- `services/home-assistant.nix` - current HA config (no Z-Wave yet)
- `hosts/homelab/configuration.nix:13` - where `services/home-assistant.nix` is imported
- `docs/handoff-sops-nix-migration.md` - if secrets later move to sops-nix, the Z-Wave keys can be included
- Honeywell T6 Pro Z-Wave install guide: https://device.report/manual/16270819
- HA Z-Wave JS integration docs: https://www.home-assistant.io/integrations/zwave_js/
- NixOS OpenThread wiki (future Matter/Thread reference): https://wiki.nixos.org/wiki/Openthread
- nixpkgs PR #502388 (openthread-border-router module): https://github.com/NixOS/nixpkgs/pull/502388
