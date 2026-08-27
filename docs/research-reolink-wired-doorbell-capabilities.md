# Research: Reolink wired-doorbell local capabilities

Research date: 2026-08-23

Installed-camera update: 2026-08-27

Issue: [#16](https://github.com/fveracoechea/homelab/issues/16)

## Decision

The always-on Reolink Video Doorbell PoE and Video Doorbell WiFi families are suitable for a local-first Home Assistant design. They provide authenticated LAN streams, camera-native person and visitor detection, local event delivery, and local recording without a cloud account. Use Home Assistant's direct Reolink integration for local events and streams. Do not treat Reolink mobile-app push as an offline path. Confirm the exact model, color, hardware number, firmware, and connection topology before design or implementation because package detection, webhook support, and standalone access depend on these facts.

## Scope

This report covers the two always-on wired families that Reolink calls **Video Doorbell PoE** (`D340P`) and **Video Doorbell WiFi** (`D340W`), in black and white variants. The Wi-Fi model is wired for power but uses Wi-Fi or its 100 Mbps LAN port for data. The PoE model uses Ethernet for data and either PoE or separate 12-24 VAC / 24 VDC power. [S1][S2][S3]

This report does not apply its conclusions to the Battery Doorbell families. The Battery Doorbell 2nd Gen can use wired power, but it is a different product family with different direct RTSP, ONVIF, and Home Assistant limits. [S1]

## Installed-camera result

The user identified the purchased unit as the **Reolink Battery Video Doorbell (2nd Gen)**. It is not one of the always-on `D340P` or `D340W` families assessed below, so the wired-family decision does not apply to this installation.

Reolink currently requires a Home Hub for this battery doorbell's CGI, RTSP, ONVIF, and Home Assistant paths. Its model FAQ says standalone RTSP/ONVIF in Wired Power Mode is planned for a future firmware update. Reolink also documents an at-most-five-minute RTSP preview session for battery Wi-Fi cameras through a Home Hub or NVR, and currently does not allow a Home Hub-connected 2nd Gen doorbell to enter Wired Power Mode. Therefore neither the standalone camera nor a Home Hub provides a documented continuous Frigate stream today. [S13][S14][S15]

If continuous local NVR integration is required while the return option remains open, use a plug-in Reolink Video Doorbell WiFi or PoE model with documented standalone protocols. Otherwise, wait for released firmware and verify the installed version before implementation.

Record the return deadline, installed hardware number, firmware version, power mode, and local address before that decision. Do not buy a Home Hub solely for Frigate under the currently documented five-minute stream behavior.

## Family matrix

| Capability | Video Doorbell PoE / D340P | Video Doorbell WiFi / D340W | Inventory-dependent fact |
|---|---|---|---|
| Always-on operation | Yes | Yes | Confirm power source and network path. |
| Direct local stream | RTSP, RTMP, ONVIF; H.264 main and substreams | RTSP, RTMP, ONVIF; H.264 main and substreams | Confirm that protocol ports are enabled in the installed firmware. |
| Direct Home Assistant integration | Reolink lists both black and white as tested | Reolink lists both black and white as tested and Works with Home Assistant certified | Confirm that the doorbell is directly addressable or identify the NVR/Home Hub topology. |
| Camera-native person detection | Yes | Yes | Confirm available detection types in the device UI after firmware update. |
| Doorbell press event | Yes, exposed as visitor/ring | Yes, exposed as visitor/ring | Confirm firmware and NVR compatibility if routed through an NVR. |
| Package detection | White variant only | White variant only | Color is a functional hardware distinction, not only a cosmetic choice. |
| Local webhook | Listed for black and white hardware IDs on latest firmware; standalone only | Listed for black and white hardware IDs on latest firmware; standalone only | Exact hardware ID, latest matching firmware, standalone mode, and available payload event types must be checked. |
| Camera storage | microSD up to 256 GB | microSD up to 256 GB | Confirm card presence, health, and configured schedule. |
| Other local recording | Reolink NVR, Home Hub, FTP server | Reolink NVR, Home Hub, FTP server | Confirm recorder model, network reachability, capacity, retention, and credentials. |
| Continuous recording | 24/7, scheduled, or motion-triggered | 24/7, scheduled, or motion-triggered | Confirm destination and recording schedule. |
| Reolink Cloud | Not listed for PoE | Supported for plug-in Wi-Fi | Cloud is optional and is not needed for the local-first path. |
| Reolink rich mobile push | Image-rich push is not listed; email is the documented alternative | Supported | This is an Internet-dependent Reolink service, not local event push. |

Sources: family comparison and model descriptions [S1], product specifications [S2][S3], webhook hardware table [S4], and Home Assistant tested-model list [S5].

## Findings

### Local stream

- Both wired families publish H.264 video and list RTSP, RTMP, and ONVIF support. The product specifications expose main and substream frame-rate and bit-rate controls. [S2][S3]
- Reolink documents direct LAN RTSP URLs in the form `rtsp://<user>:<password>@<camera-ip>/Preview_01_main` and `..._sub`. Port 554 is the default. Protocol ports can be disabled, so enabled ports on the installed device are the final authority. [S6]
- Home Assistant can use RTSP, RTMP, or FLV and creates fluent, balanced, clear, and snapshot camera entities when the model supports them. FLV is the lowest-load option; RTSP is the normal interoperable choice. [S5]
- Home Assistant lists direct testing for both PoE colors and both Wi-Fi colors. This is stronger evidence than a generic protocol claim, but the installed firmware still controls the final behavior. [S5]

Decision impact: a separate cloud relay is not required for Home Assistant live view. Keep the doorbell and Home Assistant mutually reachable on the LAN and permit only the required local ports.

### Event push

There are two different meanings of push. They must not be combined:

1. **Local integration push:** Home Assistant exposes visitor, person, motion, and model-supported package binary sensors. It selects the fastest available event method in this order: Reolink TCP push, ONVIF push, ONVIF long polling, then five-second fast polling. Direct cameras are also polled every 60 seconds for redundancy. The integration declares the Local Push IoT class. [S5]
2. **Reolink mobile-app push:** Reolink requires the device to be added to the phone by UID, requires remote access to work, and on Android requires access to Google services. This path depends on Internet and Reolink/P2P/mobile notification infrastructure. [S7]

Reolink also has a camera-native webhook test feature. Current official documentation lists these wired-doorbell hardware IDs:

| Marketing/model name | Hardware ID |
|---|---|
| Video Doorbell WiFi / D340W, black | `DB_566128M5MP_W` |
| Video Doorbell WiFi / D340W, white | `DB_566128M5MP_W_W` |
| Video Doorbell PoE / D340P, black | `DB_566128M5MP_P` |
| Video Doorbell PoE / D340P, white | `DB_566128M5MP_P_W` |

The webhook sends an HTTP POST with JSON to an HTTP or HTTPS URL. Reolink says the listed cameras need the latest Download Center firmware and must run standalone. NVR-connected cameras cannot use this webhook. Reolink describes it as a test version and does not clearly enumerate person, visitor, and package as separate webhook payload guarantees. Treat webhook event granularity as unverified until tested on the exact unit. [S4]

Decision impact: prefer Home Assistant's direct local event path because it has explicit visitor and AI-person entities and tested wired-doorbell support. A camera-native webhook can be a useful alternative only after exact hardware and firmware verification.

### Camera-native person detection

- Reolink's PoE and Wi-Fi product specifications list motion detection, person detection, and visitor notification. Reolink states that smart detection is available without a subscription. [S2][S3]
- Home Assistant consumes AI person detection as a camera event. Detection therefore occurs before Home Assistant receives the event; Home Assistant does not need to run person inference to obtain this binary sensor. [S5]
- White wired variants add package detection. Official sources do not claim package detection for black wired variants. [S1][S2][S3]
- Some current Wi-Fi marketing text also mentions vehicle and animal detection, while its formal specification table lists motion, person, package on white, and visitor. Do not make vehicle or animal detection a requirement until the exact unit exposes those controls and entities. [S3]

Decision impact: camera-native person detection is safe to use as the initial automation trigger. Keep an independent video recording around the event so false positive and false negative behavior can be measured.

### Recording and upload

- Both wired families support continuous, scheduled, and motion-triggered recording. Both have a microSD slot with a documented 256 GB maximum and support Reolink NVR and Home Hub recording. [S1][S2][S3]
- Both list FTP as a protocol and Reolink states that recordings can be stored on an FTP server. A LAN FTP destination can remain local. Reolink product text uses the combined phrase "FTP/NAS server"; confirm the actual server protocol rather than assuming SMB or NFS support. [S1][S2][S3]
- The Wi-Fi family can also use Reolink Cloud. The PoE family is not listed for cloud storage in the family comparison. Neither cloud path is needed for local operation. [S1]
- Home Assistant can browse recordings on camera SD storage or an NVR/Home Hub for up to one month in its media browser. This is playback access, not the primary recording destination. [S5]
- Event email can include text, a picture, or a video clip. Internet-hosted SMTP is not an offline path. [S8]

Decision impact: the smallest robust local design is camera microSD plus Home Assistant event handling. Use an NVR/Home Hub or a LAN FTP target when a second copy, longer retention, or storage inside the house is required.

### Authentication and network exposure

- Local access uses device-local credentials, not a Reolink cloud account. Reolink recommends IP-address login on the LAN. Home Assistant asks for the device IP/host, device username, and device password. [S5][S9]
- Initial setup creates a password for the built-in `admin` account. Reolink devices can create additional Administrator and User accounts. A User can view but cannot change device settings. Home Assistant currently requires an account with admin privileges for full integration operation. [S5][S10][S11]
- RTSP URLs include the device username and password. Do not place a real URL in Git, logs, dashboards, or issue comments. Home Assistant restricts supported password characters because stream URL encoding can fail for other characters. [S5][S6]
- HTTPS is listed, but RTSP itself is not an encrypted transport. Keep local camera protocols on trusted LAN paths or controlled VLAN paths. Do not forward camera ports to the public Internet. [S2][S3][S6]
- UID/P2P remote access is optional on these non-battery families and can be disabled if only local access is required. Reolink says UID uses P2P and random UDP ports. [S12]

Decision impact: use a dedicated local administrator credential for Home Assistant if the exact firmware supports it, store it only in Home Assistant storage, disable UID when Reolink remote access and native mobile push are not required, and restrict camera traffic at the network boundary.

### Offline behavior

The following behavior has direct source support:

- Home Assistant states that Reolink cameras can operate fully locally and that the Home Assistant integration and Reolink app/client continue to work when Internet access to the camera is blocked. [S5]
- LAN access by device IP is an official Reolink access method. [S9]
- Local streams, device AI event state, SD recording, NVR/Home Hub recording, and a reachable LAN FTP target do not require a cloud account in the documented design. [S1][S2][S3][S5]
- UID can be disabled when only local access is needed. [S12]

The following functions do not survive a complete Internet outage, or depend on another service:

- Reolink native mobile-app push requires UID remote access and mobile notification services. [S7]
- Reolink Cloud, remote UID/P2P live view, firmware checks/downloads, and Internet-hosted email need Internet.
- Home Assistant mobile notifications away from the LAN need a working remote path to Home Assistant and the phone notification service. Local Home Assistant automations and local event sensors do not.
- FTP and webhook delivery continue only while their destination is reachable. A LAN destination can continue during a WAN outage.

The official sources do not define all failure details. Verify timekeeping after a long WAN outage, queued/retried FTP or webhook behavior, recovery after link loss, and whether a Wi-Fi doorbell maintains local operation when its configured DNS or NTP servers are unavailable.

## Replacement-camera inventory

Collect these values from **Device Info** and the physical installation for any replacement wired model before implementation. The current battery model remains blocked as described above. Do not record passwords, UID values, Wi-Fi credentials, or webhook secrets in Git or GitHub.

| Inventory item | Why it matters |
|---|---|
| Exact model name and model number (`D340P`, `D340W`, or another family) | Prevents applying wired-family claims to a Battery Doorbell. |
| Black or white variant | White wired variants have package detection and a different 3:4 field of view. |
| Hardware number | Must match the webhook support table; firmware packages are hardware-specific. |
| Firmware version and build | Determines webhook availability and event/protocol behavior. |
| Direct standalone, NVR channel, or Home Hub topology | Webhooks require standalone operation; credentials, stream channels, and controls change behind a recorder. |
| Network transport and camera IP | Distinguishes PoE, Ethernet with separate power, and Wi-Fi paths; needed for direct local access. |
| Enabled HTTP/HTTPS, RTSP, ONVIF, RTMP, and server ports | Disabled ports prevent local integrations even when the family supports the protocol. |
| Available detection types in the current UI | Confirms person, visitor, package, vehicle, and animal behavior on this unit. |
| Installed microSD model/capacity and health | Confirms local recording is real, not only supported. |
| NVR/Home Hub model, hardware, firmware, and channel, if present | Recorder compatibility and event controls vary by hardware and firmware. |
| UID enabled/disabled state | Determines Reolink remote access and native app push exposure. Do not record the UID itself. |
| Chime model/version and pairing | Confirms local audible alert behavior. |

## Verification tests after inventory

These are research follow-ups, not implementation steps:

1. Block WAN access for the doorbell while keeping LAN access. Ring the bell and trigger person detection. Confirm Home Assistant visitor/person events, local live view, and recording.
2. Confirm the event transport reported in Home Assistant diagnostics: TCP push, ONVIF push, ONVIF long polling, or fast polling.
3. Confirm main and substream authentication and latency without exposing credentials in command history or logs.
4. Confirm 24/7 and event recordings at the selected destination, including pre-recording and playback after a reboot.
5. If using webhook, confirm exact event types, JSON body, secret validation, timeout, retry behavior, and operation during WAN loss.
6. Leave WAN blocked long enough to test clock drift, DNS/NTP failure, storage rollover, and recovery after WAN and LAN interruptions.

## Risks and open facts

- **Incomplete installed-unit inventory:** The product family is known, but hardware number, firmware version, power mode, and return deadline are still required. Continuous local integration remains blocked regardless under the currently documented firmware behavior.
- **Webhook is a test feature:** Reolink requires latest matching firmware, standalone mode, and specific hardware IDs. Event granularity and delivery guarantees are not fully documented. [S4]
- **Marketing and formal specifications differ:** The Wi-Fi marketing section lists more AI classes than its formal specification table. The device capability response is the final authority. [S3]
- **Connection limits:** Home Assistant warns that Reolink cameras have a limited number of simultaneous connections. Home Assistant, Frigate, Blue Iris, Scrypted, or a second ONVIF client can cause short unavailability. [S5]
- **ONVIF callback networking:** ONVIF push needs a local HTTP callback address reachable by the camera. Home Assistant can fall back to TCP push or polling, but the observed transport must be verified. [S5]

## Sources

Sources were accessed on 2026-08-23 unless a source states 2026-08-27. Reolink pages are first-party product or support documents. Home Assistant's official integration document is primary documentation for the integration; it states that the integration is officially authorized by Reolink and built with Reolink official resources.

- **[S1]** Reolink, [Introduction to Reolink Video Doorbell Cameras](https://support.reolink.com/articles/16929500357657-Introduction-to-Reolink-Video-Doorbell-Cameras/). Family boundaries, power, AI classes, recording destinations, package-detection variants, RTSP/ONVIF, direct Home Assistant, and cloud comparison.
- **[S2]** Reolink, [Reolink Video Doorbell PoE product and specifications](https://reolink.com/product/reolink-video-doorbell-poe/). Stream codec, protocols, person/visitor detection, recording modes, storage, and power.
- **[S3]** Reolink, [Reolink Video Doorbell WiFi product and specifications](https://reolink.com/product/reolink-video-doorbell-wifi/). Stream codec, protocols, AI claims, recording modes, storage, rich notifications, networking, and power.
- **[S4]** Reolink, [Overview of Webhook in Reolink Cameras](https://support.reolink.com/articles/46238508855193-Overview-of-Webhook-in-Reolink-Cameras/). Supported hardware IDs, latest-firmware requirement, standalone restriction, HTTP POST, and JSON body.
- **[S5]** Home Assistant, [Reolink integration](https://www.home-assistant.io/integrations/reolink/). Local operation, credentials, direct tested models, streams, event transport order, event entities, recording playback, connection limits, and ONVIF callback conditions.
- **[S6]** Reolink, [Introduction to RTSP](https://support.reolink.com/articles/900000630706-Introduction-to-RTSP/). LAN RTSP URL, main/substreams, credentials, port, and recorder channel differences.
- **[S7]** Reolink, [Reolink Push Notifications Operation Failed](https://support.reolink.com/articles/360013551553-Reolink-Push-Notifications-Operation-Failed/). UID, remote access, and mobile-service requirements for native app push.
- **[S8]** Reolink, [How to Set up Visitor Alerts for Reolink Video Doorbell Cameras](https://support.reolink.com/articles/16938270669593-How-to-Set-up-Visitor-Alerts-for-Reolink-Video-Doorbell-Cameras/). Ring versus person events, push, email attachments, FTP mention, NVR differences, and rich-notification scope.
- **[S9]** Reolink, [How to Access Reolink Products](https://support.reolink.com/articles/360014672773-How-to-Access-Reolink-Products/). IP-based LAN access and device credentials.
- **[S10]** Reolink, [Introduction to the Default User and Password](https://support.reolink.com/articles/900000603563-Introduction-to-the-Default-User-and-Password-of-Reolink-Cameras-NVRs/). Initial local admin credential setup.
- **[S11]** Reolink, [How to Add Admin/User Accounts to Reolink Cameras](https://support.reolink.com/articles/360011355734-How-to-Add-Admin-User-Accounts-to-Reolink-Cameras/). Device-local account roles and permissions.
- **[S12]** Reolink, [How to Enable UID for Reolink Products](https://support.reolink.com/articles/360013481134-How-to-Enable-UID-for-Reolink-Products/). Optional UID/P2P remote access, default state, random UDP use, and local-only disablement.
- **[S13]** Reolink, [Which Reolink Products Support CGI/RTSP/ONVIF](https://support.reolink.com/articles/900000617826-Which-Reolink-Products-Support-CGI-RTSP-ONVIF/). Battery-camera protocol requirements. Accessed 2026-08-27.
- **[S14]** Reolink, [FAQs for Reolink Video Doorbell (2nd Gen)](https://support.reolink.com/articles/60553722670617-FAQs-for-Reolink-Video-Doorbell-2nd-Gen/) and [Power Modes](https://support.reolink.com/articles/56608051231129-Introduction-to-Power-Modes-of-Reolink-Battery-Video-Doorbells-Dual-Power-Support/). Current Wired Power Mode, Home Hub, RTSP, ONVIF, and Home Assistant limits. Accessed 2026-08-27.
- **[S15]** Reolink, [Introduction to RTSP](https://support.reolink.com/articles/900000630706-Introduction-to-RTSP/). Home Hub/NVR stream URLs and battery-camera preview-session limits. Accessed 2026-08-27.
