# Project: Z-Wave + Zigbee integration for Home Assistant

## Context

The homelab's Home Assistant instance (`services/home-assistant.nix`) manages BLE sensors, TP-Link smart plugs, ESPHome devices, and weather - but has no Z-Wave or Zigbee capability. The user has a Honeywell T6 Pro TH6320ZW Z-Wave thermostat that needs to be integrated. This document captures the research, protocol decision, and action plan for adding both Z-Wave and Zigbee to the NixOS homelab via a single dual-radio USB stick.

The thermostat is the immediate driver for Z-Wave. Zigbee is enabled alongside it for future cheap sensors/lights with zero additional hardware.

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

### Controller stick: Aeotec Z-Stick 10 Pro (not yet purchased)
- Model ZWA060-A, ASIN B0DV9RFSR9
- Amazon: https://www.amazon.com/dp/B0DV9RFSR9
- ~$59.99 new (as of Jul 2026)
- **Dual radio** in one USB stick:
  - Z-Wave 800 series (EFR32ZG23) with Long Range support (up to 1 mile)
  - Zigbee 3.0 (EFR32MG21)
- S2 security (Z-Wave), SmartStart
- Shows up as **two serial ports** via a Silicon Labs CP2105 Dual USB to UART Bridge Controller
- by-id paths will look like:
  - `/dev/serial/by-id/usb-Silicon_Labs_CP2105_Dual_USB_to_UART_Bridge_Controller_<SERIAL>-if00-port0` (Zigbee)
  - `/dev/serial/by-id/usb-Silicon_Labs_CP2105_Dual_USB_to_UART_Bridge_Controller_<SERIAL>-if01-port0` (Z-Wave)
- `<SERIAL>` is unique per stick (e.g., `00F4C829`). The `if00`/`if01` suffix differentiates the two UART interfaces.
- Per Aeotec docs: `if01-port0` is typically Z-Wave, `if00-port0` is typically Zigbee, but this can vary - try the other if the first doesn't work.
- No external antenna needed - built-in chip antenna. USB extension cable recommended to avoid metal case / Wi-Fi interference.

## Protocol decision: Z-Wave + Zigbee (not Matter/Thread)

Research concluded Z-Wave is the right protocol for the thermostat, and Zigbee is worth enabling alongside it since the Z-Stick 10 Pro includes both radios at no extra cost.

### Why Z-Wave for the thermostat

1. **Thermostat locks the choice** - the TH6320ZW is Z-Wave-only hardware. No firmware update adds Matter or Zigbee.
2. **908.42 MHz US-exclusive spectrum** - FCC allocated this sub-GHz band specifically for Z-Wave. No Wi-Fi, Bluetooth, or Zigbee competition. This matters in a GA detached home where 2.4 GHz is already crowded.
3. **GA construction (wood frame + drywall)** - Z-Wave's sub-GHz signal penetrates 3+ walls reliably at 30-100m per hop. Zigbee/Thread (2.4 GHz) typically die after 1-2 walls.
4. **NixOS module maturity** - `services.zwave-js` is native nixpkgs, well-tested.
5. **HVAC reliability matters** - Z-Wave's stricter certification means fewer "my thermostat stopped responding" surprises.
6. **Insurance discounts** - State Farm, Allstate, Liberty Mutual offer 5-15% for monitored Z-Wave security.

### Why Zigbee for future sensors/lights

1. **No extra hardware** - the Z-Stick 10 Pro already has a Zigbee 3.0 radio. Enabling it is just a config change.
2. **Cheapest device ecosystem** - Zigbee sensors average $8-25 vs $40-80 for Z-Wave. Aqara, Sonoff, IKEA, Third Reality.
3. **Different frequency from Z-Wave** - Zigbee (2.4 GHz) and Z-Wave (908 MHz) coexist without interference. The two protocols complement each other: Z-Wave for backbone (thermostat, locks, switches), Zigbee for scale (sensors, bulbs).
4. **ZHA in Home Assistant** - built-in integration, no MQTT broker needed, configured in HA UI.

### Why not Matter/Thread (yet)

- Device ecosystem is 1/4 the size of Z-Wave (1,000 vs 4,000+ certified products)
- NixOS `openthread-border-router` module merged March 2026 (nixpkgs PR #502388) - still bleeding edge, requires IPv6 forwarding
- Thread uses same 2.4 GHz band as Zigbee - no frequency advantage
- Requires IPv6 (19% of US ISP routers still block it per FCC 2026 data)
- Revisit in 2027-2028 when device ecosystem matures and NixOS support stabilizes

## NixOS config (already applied)

### What changed in `services/home-assistant.nix`

1. **`services.zwave-js` block added** - standalone Z-Wave JS server, enabled with placeholder serial port and secrets file path
2. **`"zwave_js"` added to `extraComponents`** - HA Z-Wave JS integration (connects to the server via WebSocket)
3. **`"zha"` added to `extraComponents`** - HA Zigbee Home Automation (uses the Z-Stick 10 Pro's Zigbee radio; serial port configured in HA UI)

### `services.zwave-js` module options

| Option | Type | Default | Notes |
|---|---|---|---|
| `services.zwave-js.enable` | bool | `false` | Enable zwave-js-server on boot |
| `services.zwave-js.serialPort` | absolute path | (none) | Use `/dev/serial/by-id/...` not `/dev/ttyUSB0` for reboot stability |
| `services.zwave-js.port` | uint16 | `3000` | WebSocket port for the server |
| `services.zwave-js.secretsConfigFile` | absolute path | (none) | JSON file with security keys. Must NOT be in nix store (world-readable) |
| `services.zwave-js.settings` | JSON submodule | `{}` | Non-secret config, combined with secretsConfigFile |
| `services.zwave-js.package` | package | (nixpkgs) | The zwave-js-server package |
| `services.zwave-js.extraFlags` | list of string | `[]` | Extra CLI flags |

Current config uses a placeholder serial port (`REPLACE_ME`) that the user must replace with the actual by-id path after plugging in the stick. The zwave-js service will fail to start until this is done - that's expected.

### Secrets file format

`services.zwave-js.secretsConfigFile` expects a JSON file:

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

Generate keys with: `< /dev/urandom tr -dc A-F0-9 | head -c32 ;echo` (one per key, 32 hex chars = 16 bytes).

File lives at `/var/lib/zwave-js/secrets.json` (not in the nix store, which is world-readable). Follows the existing pattern of secrets under `/var/lib/<service>/` (see `CONTEXT.md` notes).

## HA integration path

### Z-Wave (via `services.zwave-js`)

NixOS runs `services.zwave-js` as a standalone server. HA connects to it over WebSocket.

1. NixOS runs `services.zwave-js` on port 3000 (default)
2. In HA web UI: Settings > Devices & Services > Add Integration > Z-Wave
3. **Uncheck** "Use the Z-Wave add-on" (we're not on HAOS)
4. Enter WebSocket URL: `ws://localhost:3000`
5. HA detects the server, creates the integration
6. Add the thermostat via Z-Wave JS panel:
   - If TH6320ZW2007 (SmartStart): scan the QR code on the back of the thermostat
   - If TH6320ZW2003: put thermostat in inclusion mode (MENU > Z-WAVE SETUP > START INCLUDING), then click "Add Node" in HA

### Zigbee (via ZHA)

ZHA is built into HA. The serial port is configured in the HA UI, not in NixOS.

1. In HA web UI: Settings > Devices & Services > Add Integration > ZHA
2. Select the Zigbee serial port (the `if00-port0` by-id path)
3. Configure ZHA network settings (use channel 25 or 26 to avoid Wi-Fi overlap)
4. Add Zigbee devices via the ZHA panel

No MQTT broker needed. No separate NixOS service needed. The `"zha"` component in `extraComponents` is sufficient.

## Known issues with TH6320ZW in Home Assistant

1. **Set temperature attribute not updating** (issue #77579) - Fixed in HA 2022.9. Current versions unaffected.
2. **AC mains disconnected sensor** (issue #160029) - `binary_sensor.t6_pro_..._ac_mains_disconnected` fires even on 24V C-wire. Unreliable for this device. Ignore or suppress.
3. **Mode not updating from panel to app** (issue #161075) - Usually a polling/interview issue. Re-interview the node in Z-Wave JS settings.
4. **Split setpoints** - HA may represent heat/cool setpoints as separate entities. Normal for Z-Wave thermostats.
5. **Onboard schedule** - cannot be changed via Z-Wave. Use HA automations instead.

## Action plan

Strictly ordered. The user rebuilds/tests the system themselves - never build the system config (per `AGENTS.md`).

### Step 1 - NixOS config (DONE)

The `services/home-assistant.nix` file has been edited to add:
- `services.zwave-js` block (enable, serialPort placeholder, secretsConfigFile)
- `"zwave_js"` and `"zha"` in `extraComponents`

`nix flake check` passes. The zwave-js service will fail to start until the serial port placeholder is replaced with the actual path.

### Step 2 - Hardware setup (user does this)

- Buy Aeotec Z-Stick 10 Pro (ASIN B0DV9RFSR9, ~$59.99)
- Plug into homelab box via a USB extension cable (3-6 ft) to move the stick away from the metal case and Wi-Fi interference
- Identify the two serial ports:
  ```
  ls -l /dev/serial/by-id/
  ```
  Look for two symlinks containing `Silicon_Labs_CP2105_Dual_USB_to_UART_Bridge_Controller`:
  - `...if00-port0` = Zigbee (for ZHA, configured in HA UI)
  - `...if01-port0` = Z-Wave (for `services.zwave-js.serialPort` in NixOS)
- If unsure which is which, check with: `udevadm info -a -n /dev/ttyACM0 | grep '{interface}'`
- Record the full by-id paths

### Step 3 - Replace the serial port placeholder (user does this)

In `services/home-assistant.nix`, replace `REPLACE_ME` in the `services.zwave-js.serialPort` line with the actual serial number from the by-id path. The path should look like:
```
/dev/serial/by-id/usb-Silicon_Labs_CP2105_Dual_USB_to_UART_Bridge_Controller_00F4C829-if01-port0
```
(Where `00F4C829` is the actual serial number of your stick)

If the Z-Wave radio is on `if00` instead of `if01`, use that. Aeotec docs say it can vary.

### Step 4 - Generate Z-Wave security keys (user does this on the host)

```bash
mkdir -p /var/lib/zwave-js
cat > /var/lib/zwave-js/secrets.json << EOF
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

File must NOT be in the nix store (world-readable). `/var/lib/zwave-js/secrets.json` follows the existing pattern (see `CONTEXT.md` notes).

### Step 5 - Apply and verify (user does this)

```bash
nixos-rebuild test --flake .#homelab
```

Verify:
- `systemctl status zwave-js` is active (not failed)
- `ss -tlnp | grep 3000` shows the server listening
- If zwave-js fails: check `journalctl -u zwave-js` for serial port errors - most likely the by-id path is wrong or the stick isn't plugged in

### Step 6 - HA UI: Z-Wave setup (user does this in web UI)

- Go to Settings > Devices & Services > Add Integration > Z-Wave
- Uncheck "Use the Z-Wave add-on"
- Enter WebSocket URL: `ws://localhost:3000`
- HA detects the server and creates the integration

### Step 7 - HA UI: Zigbee setup (user does this in web UI)

- Go to Settings > Devices & Services > Add Integration > ZHA
- Select the Zigbee serial port (the `if00-port0` by-id path)
- Choose Zigbee channel 25 or 26 (avoids Wi-Fi channels 1, 6, 11 overlap)
- ZHA creates the Zigbee network

### Step 8 - Pair the thermostat (user does this)

- If TH6320ZW2007 (SmartStart): scan the QR code on the back of the thermostat using the HA Z-Wave JS panel's SmartStart scanner
- If TH6320ZW2003: put thermostat in inclusion mode:
  - On thermostat: MENU > Z-WAVE SETUP > START INCLUDING
  - In HA: Z-Wave JS panel > Add Node
- Wait for inclusion to complete
- Re-interview the node if entities don't populate immediately

### Step 9 - Verify

- Thermostat should appear as a climate entity in HA
- Test temperature setpoint changes in both directions
- Test mode changes (heat/cool/off/auto) from HA UI
- Verify humidity sensor entity appears (TH6320ZW reports indoor relative humidity)
- If setpoint or mode sync is flaky, re-interview the node in Z-Wave JS settings
- Add a Zigbee device (e.g., a $10 Aqara door sensor) to verify the Zigbee radio works

## Non-goals / explicit exclusions

- **Do not add Matter/Thread** in this project. The NixOS OTBR module is too new, requires IPv6, and the device ecosystem is small. Revisit in 2027-2028.
- **Do not use Zigbee2MQTT** - ZHA is simpler (no MQTT broker needed) and sufficient for this setup. Switch to Zigbee2MQTT later only if device compatibility issues arise.
- **Do not use the HA Z-Wave JS add-on** - that's HAOS-only. NixOS uses `services.zwave-js` as a standalone server.
- **Never build the system config** - the user does `nixos-rebuild test --flake .#homelab` themselves (per `AGENTS.md`).
- **Do not commit the security keys to git** - the secrets file lives at `/var/lib/zwave-js/secrets.json` on the host, not in the repo. If sops-nix migration happens (see `docs/handoff-sops-nix-migration.md`), the keys can be moved there later.

## Suggested skills

- `diagnosing-bugs` - if the thermostat doesn't pair or shows the known setpoint-update bug after setup
- `codebase-design` - if considering how to structure the zwave-js config (secrets file location, udev rules, module organization)
- `grilling` - if the user wants to stress-test this plan before executing (e.g., "what if the stick isn't detected?", "what if S2 pairing fails?", "what if if00/if01 are swapped?")
- `domain-modeling` - update `CONTEXT.md` glossary with Z-Wave + Zigbee terms (`zwave-js-server`, `ZHA`, `by-id serial path`, `S2 security keys`, `SmartStart inclusion`, `CP2105 dual UART`) once the integration lands

## References

- `AGENTS.md` - repo guidelines (don't build, kebab-case files, `nix flake check`, `nixos-rebuild test`)
- `CONTEXT.md` line 25 - Home Assistant glossary entry (current state, no Z-Wave/Zigbee)
- `CONTEXT.md` lines 62-70 - notes on secret provisioning pattern under `/var/lib/<service>/`
- `services/home-assistant.nix` - HA config with `services.zwave-js` and `zha` component (already edited)
- `hosts/homelab/configuration.nix:13` - where `services/home-assistant.nix` is imported
- `docs/handoff-sops-nix-migration.md` - if secrets later move to sops-nix, the Z-Wave keys can be included
- Aeotec Z-Stick 10 Pro user guide: https://aeotec.freshdesk.com/support/solutions/articles/6000274575-z-stick-10-pro-user-guide
- Aeotec Z-Stick 10 Pro Z-Wave JS setup: https://aeotec.freshdesk.com/support/solutions/articles/6000274641-setup-z-wavejs-ui-with-home-asstant-z-stick-10-pro
- Aeotec Z-Stick 10 Pro specs: https://aeotec.freshdesk.com/support/solutions/articles/6000274576-z-stick-10-pro-technical-specifications
- Honeywell T6 Pro Z-Wave install guide: https://device.report/manual/16270819
- HA Z-Wave JS integration docs: https://www.home-assistant.io/integrations/zwave_js/
- HA ZHA integration docs: https://www.home-assistant.io/integrations/zha/
- NixOS OpenThread wiki (future Matter/Thread reference): https://wiki.nixos.org/wiki/Openthread
- nixpkgs PR #502388 (openthread-border-router module): https://github.com/NixOS/nixpkgs/pull/502388
