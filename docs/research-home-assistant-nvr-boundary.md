# Home Assistant and NVR integration boundaries

Research date: 2026-08-23

Installed-camera update: 2026-08-27

Issue: [#18](https://github.com/fveracoechea/homelab/issues/18)

## Candidate boundary

If Frigate is selected as the recorder, use the official Reolink integration for camera administration, native Reolink
AI state, and a secondary direct live view. Use Frigate as the independent NVR
and the authority for recordings, object detection, review items, and event
identifiers. Use Frigate `reviews` or `events`, not a Reolink person binary
sensor, whenever an automation must open the recording for the detected person.

This is the target boundary for a camera with supported continuous local interfaces. It is not currently implementable with the purchased Reolink Battery Video Doorbell (2nd Gen). Reolink currently requires a Home Hub for this model's Home Assistant, RTSP, and ONVIF paths; standalone support in Wired Power Mode is a future firmware feature. Home Hub/NVR RTSP preview for battery cameras ends after at most five minutes, so it is not a continuous Frigate source. Replace the camera with a compatible plug-in Wi-Fi or PoE model, or wait for released and verified firmware, before implementing this boundary [S16][S17][S18].

This report does not select the recorder or authorize Service implementation. Camera disposition, recorder architecture, retention enforcement, security boundaries, and detector/runtime selection remain owned by the open decision tickets.

Keep the two paths independent after the camera:

```text
Reolink camera -- device API and stream --> Home Assistant Reolink integration
       |
       +-- main and sub streams --> Frigate/go2rtc --> recordings and reviews
                                             |              |
                                             |              +-- HTTP API --> Frigate integration
                                             +-- MQTT --> Mosquitto --> Home Assistant MQTT

User -- HTTPS --> Caddy --> Home Assistant :8123
User -- HTTPS --> Caddy --> Frigate authenticated HTTP :8971
Home Assistant -- RTSP, normally :8554 --> Frigate/go2rtc
Browser -- WebRTC, when enabled, :8555 TCP/UDP --> Frigate/go2rtc
```

Caddy is not in the camera, MQTT, or Home Assistant-to-Frigate media paths. A
Caddy failure must not stop recording or detection.

## Responsibility boundaries

| Component | Owns | Does not own |
| --- | --- | --- |
| Official Reolink integration | Local Reolink device API, camera settings and controls, native camera/NVR AI binary sensors, Reolink live camera entities, and browsing recordings stored by a Reolink camera, Hub, or NVR | Frigate recording, Frigate object detection, Frigate review/event identifiers, MQTT transport, or general remote ingress |
| Frigate | Stream ingest, go2rtc restream, recording retention, snapshots, independent object detection, review items, event IDs, exports, and its own UI/API | Reolink configuration in Home Assistant, Home Assistant authentication, or MQTT brokering |
| Mosquitto | Local MQTT message transport, client authentication, topic authorization, retained messages, and client availability delivery | Video, recording files, detection, or HTTP ingress |
| Frigate integration distributed through HACS | Adapts the Frigate HTTP API, MQTT topics, and RTSP restream into Home Assistant entities, Media Browser items, and notification proxy URLs | NVR processing or storage. HACS is only a distribution and update path; downloaded integrations run inside Home Assistant from `custom_components/` [S8] |
| `media_source` | Home Assistant Media Browser and authenticated media-source access | Indexing or transcoding. Providers such as the Frigate and Reolink integrations supply the media; clients must support its codec [S6] |
| Caddy | TLS termination and HTTP/WebSocket reverse proxy for human-facing Home Assistant and Frigate URLs | MQTT, RTSP, camera protocols, Frigate WebRTC media transport, application authorization, recording, or detection |

The official Reolink integration and Frigate can use the same camera without
calling each other. Frigate's go2rtc restream should be the shared stream source
for Frigate recording/detection and the Frigate camera entities in Home
Assistant. This reduces camera connections, but it does not replace the direct
Reolink API connection used for controls and native event sensors [S5].

## Required components

### Home Assistant

- Add the official `reolink` component to
  `services.home-assistant.extraComponents`. The current NixOS option includes
  component dependencies in the Home Assistant package, and `reolink` is an
  accepted value [N1].
- Keep `default_config`. The current repository already enables it in
  `services/home-assistant.nix`; Home Assistant says it configures
  `media_source` automatically [S6].
- Install the Frigate custom integration. The current nixpkgs unstable index
  provides `home-assistant-custom-components.frigate` 5.15.4, and
  `services.home-assistant.customComponents` is the declarative NixOS path for
  it [N2]. Prefer this package over allowing HACS to mutate the Nix-managed
  runtime. It is the same Frigate integration that upstream distributes through
  HACS, not another NVR.
- Configure the Home Assistant MQTT integration before the Frigate integration.
  The Frigate integration manifest declares `http`, `media_source`, and `mqtt`
  as dependencies, and upstream requires MQTT first [S2][S9].

### Frigate and Mosquitto

- Run Frigate as a separate NVR service with persistent database, recording,
  clip, and export storage. Installing the Home Assistant integration does not
  enable recording. Recording must be enabled in Frigate and assigned a
  retention policy [S4].
- Configure go2rtc with one camera main stream for recording and one substream
  for detection. Frigate recommends HTTP-FLV for Reolink cameras where the
  model supports it, with RTSP for older high-resolution models. A camera behind
  a Reolink NVR can be read by channel, but this makes that NVR an additional
  availability dependency [S10].
- Run Mosquitto as the shared broker. Frigate and Home Assistant must connect to
  the same broker for many Frigate entities to work [S2]. Mosquitto is not a
  video path.
- Use separate MQTT users for Home Assistant and Frigate, deny anonymous access,
  and apply topic ACLs. Mosquitto supports username/password authentication and
  per-user topic ACLs; it warns that passwords need encrypted transport when
  the network is not trusted [S7]. On this single Host, a loopback or otherwise
  private listener avoids making MQTT a Caddy endpoint.
- Persist Mosquitto state if retained messages or durable sessions are part of
  recovery. The NixOS module provides `services.mosquitto.persistence`,
  listeners, users, ACLs, and credential-file options. Its `passwordFile`
  option passes the secret as a systemd credential instead of placing it in the
  Nix store [N3].

An accelerator is an operational sizing choice, not an integration boundary.
The current nixpkgs unstable index provides Frigate 0.17.2 and its NixOS module
supports camera inputs, MQTT settings, database path, FFmpeg, and VA-API [N4].

### Caddy and network ports

- Add a separate `frigate.veracoechea.com` virtual host that proxies to
  Frigate's authenticated HTTP port `8971`. Frigate states that reverse proxies
  must use `8971`; port `5000` is unauthenticated, gives anonymous requests
  admin-equivalent access, and must remain restricted [S3].
- Terminate public TLS at Caddy and disable Frigate's internal TLS if Caddy uses
  plain HTTP to the local upstream. Frigate documents this exact Caddy pattern
  and warns that an HTTP upstream fails if Frigate TLS stays enabled [S11].
- Keep Home Assistant at `127.0.0.1:8123` and its existing
  `home.veracoechea.com` Caddy virtual host. The repository already trusts only
  loopback proxy addresses and opens ports 80/443 only on `enp8s0` and
  `tailscale0`.
- Do not expose `5000`. Bind it to loopback if the service permits, and block it
  at the firewall in all cases.
- Permit Home Assistant to reach the Frigate RTSP restream on `8554`. The
  Frigate integration's documented live camera path makes a direct connection
  from Home Assistant to this port; an HTTPS Caddy virtual host does not carry
  RTSP [S2]. go2rtc can apply RTSP username/password authentication to non-local
  clients [S5].
- Frigate's native high-quality WebRTC path uses `8555` TCP/UDP and needs a LAN
  and Mesh candidate. Caddy cannot replace this media connection. If `8555` is
  unavailable, Frigate can use MSE through its HTTP path or fall back to jsmpeg,
  with lower capability or quality [S12].
- A normal Caddy `reverse_proxy` supports WebSocket upgrades and sets the
  forwarded headers. The simple local reverse proxy is enough for Home
  Assistant and Frigate HTTP/WebSocket traffic; it must not add a second
  application authentication scheme unless there is a separate identity design
  [S13].

The nixpkgs `services.frigate.hostname` option creates an nginx virtual host and
states that only nginx is supported for direct module-managed proxying. Do not
set that option when Caddy is the repository ingress. Configure the Caddy
virtual host explicitly instead [N5].

## Authentication boundaries

| Connection | Authentication and secret owner |
| --- | --- |
| Home Assistant to Reolink camera/NVR | A Reolink device-local admin account is required. It is not a Reolink cloud account. Home Assistant stores the integration entry in its state directory [S1]. Use a dedicated device account where Reolink permits it. |
| Frigate/go2rtc to Reolink stream | Separate camera or NVR stream credentials in Frigate credentials/config. Do not reuse Home Assistant storage as a secret source. If Frigate reads an NVR channel, it authenticates to that NVR instead of the camera. |
| Home Assistant and Frigate to Mosquitto | Two broker users with the minimum read/write topic ACLs. Credentials belong in files outside the Nix store and are injected into each service. |
| Home Assistant Frigate integration to Frigate API | Prefer the authenticated `8971` API with a dedicated Frigate user. The integration supports username/password and obtains a Frigate JWT [S9]. A `viewer` role is sufficient for read-only live and historical footage; control switches need a role allowed to modify Frigate state [S3]. |
| Browser to Home Assistant | Existing Home Assistant login and session through Caddy. Frigate notification media is exposed under the Home Assistant origin at `/api/frigate/...`, so a notification does not require a separately exposed Frigate URL. Endpoint authorization is owned by the Frigate integration, not Caddy [S2]. |
| Browser to Frigate | Frigate login, JWT cookie, and role enforcement through Caddy to `8971`. Caddy supplies TLS and network reachability, not user identity [S3]. |

Frigate stores users in its own database and generates or reads a JWT secret.
That secret and camera, broker, and API passwords must remain outside this
repository [S3]. No credential value is needed in Nix source.

## Data flows

### Native Reolink state and media

1. Home Assistant logs in directly to the camera, Home Hub, or Reolink NVR.
2. Native motion/person/vehicle events arrive by the best supported TCP push,
   ONVIF push, ONVIF long poll, or five-second fast poll path. Home Assistant
   also polls for recovery [S1].
3. Home Assistant requests live streams directly with the selected RTSP, RTMP,
   or FLV protocol [S1].
4. For Reolink-owned recordings, the integration queries the device and exposes
   files by camera, resolution, and day in Home Assistant Media Browser [S1].

This path works without Frigate and Mosquitto. It stops when the selected
Reolink device or its network path is down.

### Frigate state, event media, and live view

1. go2rtc opens the camera main/substream connections. Frigate reads its local
   restream for detect and record roles, which avoids extra high-resolution
   camera connections [S5].
2. Frigate writes matching recording segments and creates object events and
   review items. `frigate/events` carries an object ID and label such as
   `person`; `frigate/reviews` carries a review ID plus the contributing
   detection IDs [S14].
3. Mosquitto transports Frigate availability, counts, state, controls, events,
   and reviews to Home Assistant. Video bytes never pass through Mosquitto.
4. The Frigate integration reads metadata and media from the Frigate HTTP API,
   creates Home Assistant entities, and exposes tracked-object recordings,
   snapshots, and time-based recordings through Media Browser [S2].
5. For the standard Frigate camera entity, Home Assistant connects to go2rtc
   RTSP on `8554`. For Frigate's own UI, the browser uses MSE or WebRTC when
   go2rtc is configured, with jsmpeg as a limited fallback [S2][S12].
6. Notification URLs under the Home Assistant origin proxy an event thumbnail,
   snapshot, preview, or clip from Frigate. This lets the phone reach Home
   Assistant without exposing the Frigate API directly [S2].

## Person-event playback

### Reolink limitation

The Reolink person entity reports current device AI state. Its documented media
browser is organized by camera, resolution, date, and video file, not by the
binary sensor transition. The integration documents no event ID or person-event
clip URL. Its rich-notification example takes a new snapshot after the sensor
changes rather than linking the corresponding stored recording [S1]. Therefore:

- A Reolink `person` transition cannot reliably open its matching Reolink
  recording in Home Assistant.
- A user can manually find the file by time, but Home Assistant only offers up
  to one month of Reolink recordings even if the appliance retains more [S1].
- A timestamp-correlation automation between Reolink and Frigate would combine
  two independent detectors and clocks. It cannot guarantee a matching Frigate
  event and should not become the security-event contract.

### Frigate event-linked playback

Frigate supplies stable object and review identifiers. Its upstream guidance
recommends triggering Home Assistant notifications from `frigate/reviews`
because the payload contains detection IDs needed to fetch thumbnails,
snapshots, and clips [S15]. Use that data flow for person alerts that need
playback.

This still has limits:

- The low-latency Frigate occupancy binary sensors use fewer false-positive
  checks. Frigate explicitly recommends `frigate/events` or `frigate/reviews`
  when filtering matters [S2].
- A clip exists only when Frigate recording is enabled and retained for that
  event. Early MQTT updates can report `has_clip: false`; use the final event or
  a review/detection ID and handle media that is not ready [S4][S14].
- The Home Assistant Media Browser supports tracked-object recordings and
  thumbnails, but it is a browser, not the complete Frigate Review timeline.
  Use the Frigate UI when review grouping, history scrubbing, exports, or event
  management is required [S2][S4].
- Casting a Frigate clip requires an audio track, including for cameras without
  useful audio [S2].

## Live-view and codec limits

- Reolink enables the low-resolution Fluent stream by default. High-resolution
  Clear streams are often H.265, which does not play on all Home Assistant
  browsers or Companion App devices. Fluent is H.264 and is the compatible
  fallback [S1].
- Frigate records without re-encoding. Its H.265 recordings are documented as
  playable only in Chrome 108+, Edge, and Safari, with an additional Apple
  compatibility option for some streams. H.264 is the safe cross-client choice
  [S4]. `media_source` does not transcode unsupported media [S6].
- Frigate without go2rtc uses jsmpeg at the detect stream resolution and no
  audio. With go2rtc, MSE provides native frame rate/resolution and audio when
  codecs are compatible. WebRTC needs direct candidate connectivity and is
  required for two-way talk [S12].
- H.264 video, AAC audio, and an I-frame interval equal to the frame rate are
  Frigate's broad-compatibility recommendations. Reolink calls the last setting
  `Interframe Space 1x` [S10][S12].
- Frigate smart streaming shows a periodic still image while idle and starts a
  live stream on activity. A dashboard is therefore not necessarily continuous
  video unless continuous streaming is selected, which increases bandwidth and
  client load [S12].
- The Home Assistant Frigate camera entity depends on Home Assistant reaching
  RTSP `8554`. A working Caddy page or Frigate API does not prove that live
  camera entities can connect [S2].

## Availability coupling

| Failure | Continues | Stops or degrades |
| --- | --- | --- |
| Home Assistant | Frigate recording/detection/UI, Mosquitto, Reolink onboard recording | Home Assistant dashboards, automations, Frigate entities, and Home Assistant notifications |
| Official Reolink integration only | Frigate NVR path and Frigate person-event playback | Reolink controls, native AI sensors, and Reolink Media Browser |
| Frigate | Official Reolink entities/live/device playback, Home Assistant, Mosquitto | New independent recordings/detections/reviews, Frigate live, and Frigate media; already stored Frigate media is unavailable until Frigate returns |
| Mosquitto | Frigate recording/detection and direct UI/API; official Reolink path | MQTT event delivery, Frigate availability/control entities, and MQTT-triggered notifications. HTTP media may remain reachable, but many integration entities do not function [S2] |
| Caddy | All backend processing and Home Assistant-to-Frigate internal traffic if internal URLs bypass Caddy | Branded HTTPS access to Home Assistant and Frigate; browser MSE/WebSocket paths through those names |
| `media_source` | Frigate NVR/UI, MQTT state, basic entities | Home Assistant Media Browser presentation for Frigate and other media providers [S2][S6] |
| Frigate RTSP `8554` path | Frigate recording and API if local restream remains healthy | Home Assistant Frigate camera live view |
| Frigate WebRTC `8555` path | MSE through HTTPS and jsmpeg fallback | Frigate WebRTC and two-way talk; high-quality low-latency behavior may degrade [S12] |
| Reolink camera | Stored Frigate recordings and metadata; unrelated services | Both new direct Reolink data and new Frigate ingest for that camera |
| Reolink NVR used as Frigate source | Existing Frigate recordings | Both Reolink integration channels and Frigate ingest from those channels. Direct camera ingest avoids this added coupling [S10] |

This design does not make Home Assistant, Caddy, or Mosquitto a recording
dependency. It does make Frigate the required service for event-linked person
playback, by design.

## Repository fit

The current Host already has the right ingress shape:

- `services/home-assistant.nix` runs Home Assistant on `127.0.0.1:8123`, trusts
  only loopback reverse proxies, and defines the Caddy virtual host.
- `services/caddy.nix` uses the wildcard ACME certificate and opens HTTPS only
  on the LAN interface and Mesh interface.
- `hosts/homelab/configuration.nix` composes Services as separate NixOS modules.

A later implementation should add separate `services/frigate.nix` and
`services/mosquitto.nix` Services, extend the Home Assistant Service with the
two integration packages, and add the Frigate Caddy virtual host. It should not
put camera, broker, Frigate, or JWT credentials in the repository. This note
does not select storage capacity, detector hardware, camera models, or a final
retention policy.

## Sources

Primary product and project sources were accessed 2026-08-23 unless a source states 2026-08-27:

- [S1] Home Assistant, [Reolink integration](https://www.home-assistant.io/integrations/reolink/), including prerequisites, push/poll behavior, streams, Media Browser, rich notifications, and codec limits.
- [S2] Frigate, [Home Assistant integration](https://docs.frigate.video/integrations/home-assistant/), including MQTT requirement, entities, Media Browser, notification API, RTSP, and casting.
- [S3] Frigate, [Authentication](https://docs.frigate.video/configuration/authentication/), including ports, JWT, proxy trust, and roles.
- [S4] Frigate, [Recording](https://docs.frigate.video/configuration/record/), including storage, retention, event recording, export, and codecs.
- [S5] Frigate, [Restream](https://docs.frigate.video/configuration/restream/), including go2rtc, RTSP authentication, and connection reduction.
- [S6] Home Assistant, [Media source integration](https://www.home-assistant.io/integrations/media_source/), including authentication and lack of transcoding.
- [S7] Eclipse Mosquitto, [`mosquitto.conf` manual](https://mosquitto.org/man/mosquitto-conf-5.html), including listeners, authentication, ACLs, persistence, and transport warning.
- [S8] HACS, [Integration repositories](https://hacs.xyz/docs/use/repositories/type/integration/), including `custom_components/` installation.
- [S9] Frigate integration source, [manifest](https://github.com/blakeblackshear/frigate-hass-integration/blob/master/custom_components/frigate/manifest.json), [configuration flow](https://github.com/blakeblackshear/frigate-hass-integration/blob/master/custom_components/frigate/config_flow.py), and [API client](https://github.com/blakeblackshear/frigate-hass-integration/blob/master/custom_components/frigate/api.py).
- [S10] Frigate, [Reolink camera configuration](https://docs.frigate.video/configuration/camera_specific/#reolink-cameras).
- [S11] Frigate, [Reverse proxy guide](https://docs.frigate.video/guides/reverse_proxy/).
- [S12] Frigate, [Live View](https://docs.frigate.video/configuration/live/).
- [S13] Caddy, [`reverse_proxy`](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy), including WebSocket and forwarded-header behavior.
- [S14] Frigate, [MQTT topics](https://docs.frigate.video/integrations/mqtt/), including availability, event IDs, review IDs, detection IDs, and clip state.
- [S15] Frigate, [Home Assistant notifications](https://docs.frigate.video/guides/ha_notifications/).
- [S16] Reolink, [Which Reolink Products Support CGI/RTSP/ONVIF](https://support.reolink.com/articles/900000617826-Which-Reolink-Products-Support-CGI-RTSP-ONVIF/), accessed 2026-08-27.
- [S17] Reolink, [FAQs for Reolink Video Doorbell (2nd Gen)](https://support.reolink.com/articles/60553722670617-FAQs-for-Reolink-Video-Doorbell-2nd-Gen/) and [Power Modes](https://support.reolink.com/articles/56608051231129-Introduction-to-Power-Modes-of-Reolink-Battery-Video-Doorbells-Dual-Power-Support/), accessed 2026-08-27.
- [S18] Reolink, [Introduction to RTSP](https://support.reolink.com/articles/900000630706-Introduction-to-RTSP/), accessed 2026-08-27.

Nix facts were queried through nix-mcp against its live nixpkgs unstable index
and the repository flake inputs on 2026-08-23:

- [N1] `services.home-assistant.extraComponents`: includes packaged component dependencies and accepts `reolink`.
- [N2] `services.home-assistant.customComponents`; package `home-assistant-custom-components.frigate` 5.15.4.
- [N3] `services.mosquitto` listener/user/ACL/persistence options and `services.mosquitto.listeners.*.users.<name>.passwordFile`; Mosquitto 2.1.2.
- [N4] `services.frigate` options and Frigate 0.17.2; Home Assistant 2026.8.2.
- [N5] `services.frigate.hostname`, whose option text states that it configures nginx and only nginx is supported for direct upstream module proxying; Caddy 2.11.4.
