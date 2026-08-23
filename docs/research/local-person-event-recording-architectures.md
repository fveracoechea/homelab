# Local Person-Event Recording Architectures

Research date: 2026-08-23

## Question

Which architectures can ingest the Reolink doorbell locally, preserve a temporary pre-event buffer, persist only confirmed person events for 14 days, remain independent of Home Assistant, and scale to four cameras?

## Comparison result

Frigate is the assessed architecture with documented controls for local stream ingestion, bounded pre-capture, review-item retention, and operation without Home Assistant. This is a comparison finding, not a selection. Later grilling tickets own the choice of primary recorder and its operational policy.

For a strict person-only Frigate policy, an implementation must configure all of these separate controls, subject to camera-level scope where needed:

- `objects.track: [person]` limits object tracking to people. In 0.17.2, this is the default, but it must be explicit if the policy must resist later configuration changes [F2, F3].
- `review.alerts.labels: [person]` limits alert review items to people. Frigate 0.17.2 defaults include `person` and `car` alerts; therefore car alerts occur by default unless tracked/review labels are restricted to `person` [F2, F4].
- `review.detections.labels: []` prevents non-alert review items. Otherwise, detections default to tracked labels that are not alerts [F2].
- `record.continuous.days: 0`, `record.motion.days: 0`, `record.alerts.retain.days: 14`, and `record.detections.retain.days: 0` prevent continuous, motion, and detection retention while retaining alert-overlapping segments for 14 days [F1, F5]. `record.alerts.retain.mode: all` is needed if every segment overlapping an alert, rather than only motion/activity segments, must persist [F1].
- Alert `pre_capture` and `post_capture` values are separate recording controls. Pre-capture supports up to 60 seconds in 0.17.2 and must be measured against each installed camera [F3, F5].
- Frigate writes new recording segments to a temporary cache and moves matching segments to recording storage. Its cleanup uses review-item `end_time` and normally runs at the configured `expire_interval`, which defaults to 60 minutes [F1, F5, F6].
- Official examples show that Frigate can run with MQTT disabled. Thus, Home Assistant is not in the recording path [F7].
- Frigate classifies one to six cameras with occasional motion as a low simultaneous-activity system that can use one entry-level accelerator [F8]. Four cameras are in this range.

Reolink camera-native person-event recording to microSD can be an independent second copy. Reolink documents pre-motion recording, person-specific schedules, and local operation. However, microSD overwrite is capacity-based, not age-based. FTP can use a server-side 14-day deletion policy, but Reolink states that FTP pre-motion frames can be lost when network conditions are poor [R1, R2, R3, R6, H2].

Home Assistant-triggered `camera.record` has useful lookback, but lookback needs an active HLS stream, clip lengths are approximate, retention needs separate automation, and the complete path depends on Home Assistant [H1, H2].

Agent DVR is an alternative with local AI, alert-only recording, a pre-record buffer, and age-based storage cleanup. Its built-in local AI needs a license or active subscription, and its storage and detector behavior has more independent controls to coordinate than the Frigate policy [A1, A2, A3].

No assessed architecture can guarantee deletion at the exact instant that a clip becomes 14 days old. Frigate's default cleanup interval permits normal deletion up to about one hour after the cutoff. Storage pressure can delete footage earlier. Treat "14 days" as a policy target: retain for at least 14 days during normal operation, then delete on the next cleanup pass. Provide enough storage so emergency cleanup does not violate the target [F1, F3, F6].

## Fact and assessment method

The terms in this report have these meanings:

- **Documented:** The cited project or vendor states the behavior in official documentation or implements it in official source.
- **Assessment:** An architectural conclusion from documented behavior. It is not a vendor guarantee.
- **Unknown:** The available official material does not establish the behavior for the installed model and firmware.

"Confirmed person event" means that the selected detector classifies a tracked object as `person` and the event passes configured zones and filters. It does not mean a human reviewed the event. All automated object detectors can produce false positives and false negatives.

## Criteria matrix

| Architecture | Fully local data path | Temporary pre-roll | Persists only person events | 14-day age policy | Independent of Home Assistant | Four-camera fit | Assessment |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Reolink camera to microSD | Yes for supported models | Yes on mains-powered PoE and plug-in WiFi models | Yes when the model exposes person-specific record schedules | No exact age control; overwrite is capacity-based | Yes | Good; work is distributed across cameras | Independent copy possible; not an age-policy store |
| Reolink camera to local FTP | Yes when the FTP host is local | Supported, but Reolink says network quality can cause loss of pre-motion frames | Yes when the model exposes person-specific FTP schedules | Yes only with a separate FTP-host deletion job | Yes | Good; central FTP is simple at four cameras | Viable simple design after device test |
| Home Assistant person event to `camera.record` | Yes when all components are local | Conditional; lookback needs an active HLS stream | Yes, by automation trigger | Separate file cleanup is required | No | Technically possible, but adds four always-active HLS buffers and automation coordination | Does not meet the HA-independence requirement |
| Frigate detection and recording | Yes; MQTT and cloud services are optional | Yes; temporary segment cache plus 0-60 second configured pre-capture | Yes, with explicit person-only tracking, alert, detection, and retention controls | Native day setting; cleanup interval means not instant | Yes when run as its own Service with MQTT disabled | Strong; official planning class covers 1-6 low-activity cameras | Meets documented mechanics; selection is deferred |
| Agent DVR local AI and alert recording | Yes for local streams and local AI | Yes; camera recording buffer is written when recording starts | Yes through local person AI, alert action, and Alert recording mode | Native maximum age in hours; cleanup timing and size limits apply | Yes | Credible; exact capacity must be measured on the selected model and hardware | Meets mechanics with license and load-test gates |
| Scrypted NVR | Local recording and detection are possible | Continuous recording inherently contains pre-event video | No; official NVR design records 24/7 | Storage is primarily capacity-managed | Yes | Strong at four cameras, but needs at least 1 TB and continuous storage | Does not meet the event-only requirement |
| go2rtc plus a custom event recorder | Local restream is possible | Not supplied by go2rtc as a supported recorder feature | Only through custom detector and recorder logic | Only through custom cleanup | Yes if custom services are independent | Possible, but creates unowned custom seams | Requires custom ownership of missing recorder functions |

Matrix facts come from [R1-R6], [H1-H2], [F1-F10], [A1-A3], [S1-S2], and [G1-G2]. Assessment cells do not select an architecture.

## Architecture details

### 1. Reolink camera-native recording and upload

**Documented facts**

- Reolink has PoE, plug-in WiFi, first-generation battery, and second-generation battery doorbells. The PoE and plug-in WiFi versions are always on and support pre-recording, ONVIF, and RTSP. The first-generation battery model does not support pre-recording and requires a Reolink Home Hub for ONVIF or RTSP. The second-generation battery model supports pre-recording only in wired power mode; standalone ONVIF or RTSP support is described as a future firmware update [R4].
- Reolink says plug-in PoE and WiFi cameras have pre-motion recording enabled by default. It supports pre-motion recording to SD card, Reolink NVR, Home Hub, and FTP. The pre-record duration is several seconds and varies by model and hardware version [R1].
- Reolink record schedules can select smart detection types such as person instead of all motion [R3]. FTP schedules can also select Person on models that support smart detection [R2].
- Reolink doorbells can store video on SD card, NVR HDD, Home Hub, or FTP [R4]. All PoE cameras except add-on cameras and most plug-in WiFi cameras support FTP. Battery-camera FTP support depends on the model and hardware version [R5].
- Reolink explicitly says FTP pre-motion recording depends on network conditions and can lose pre-motion frames [R1]. Reolink FTP does not support SFTP. It can use FTPS when both endpoints support it [R2].
- Home Assistant's official Reolink documentation states that Reolink cameras and its integration continue to work when internet access is blocked. It also identifies the PoE and plug-in WiFi doorbells as directly tested models [H2].

**Assessment**

This is the smallest architecture if the installed doorbell is a PoE or plug-in WiFi model and its firmware exposes Person, pre-motion, and FTP controls. The camera owns detection and pre-roll. A local FTP Service owns persisted files. A timer on the FTP host deletes files whose event age is greater than 14 days.

This design has one central failure domain for storage but not for detection. Each camera continues to classify its own scene. A failure of the FTP Service loses the off-camera copy. A camera, its power, or its network link is a per-camera failure. An SD card can provide a second failure domain if the exact model can record to SD and FTP at the same time. Official sources reviewed here do not prove concurrent SD and FTP behavior for every doorbell model, so this needs a device test.

The design is weaker than Frigate for policy inspection. The camera UI and firmware own detector behavior, event boundaries, and pre-roll length. The FTP server sees completed files but does not know why each file exists unless names or directories preserve that information. Exact 14-day age starts need a defined rule, such as file modification time or a parsed camera timestamp. Clock drift and delayed uploads can change the result.

### 2. Home Assistant-triggered recording

**Documented facts**

- The Reolink integration provides local AI person binary sensors. It uses TCP push, ONVIF push, ONVIF long polling, or five-second fast polling, in that order, and also performs a 60-second redundancy poll [H2].
- `camera.record` writes an MP4 from a camera stream. `lookback` adds video from before the action only when an HLS stream is already active. Home Assistant says duration and lookback are planned values and actual lengths can vary [H1].

**Assessment**

This path is camera person event -> Home Assistant binary sensor -> automation -> `camera.record` -> Home Assistant media directory -> separate cleanup automation.

It meets local operation but fails the independence criterion by construction. A Home Assistant restart, automation reload, unavailable entity, inactive HLS stream, or recorder conflict can remove pre-roll or the complete clip. Keeping HLS active for all four cameras makes pre-roll possible but gives Home Assistant a continuous stream workload. File retention is not part of `camera.record`.

This path remains useful for notifications or a non-critical second clip. It must not own the only event recording.

### 3. Frigate-managed detection and recording

**Documented facts**

- Frigate writes new stream segments to `/tmp/cache`. It moves only segments that match the configured recording retention policy to `/media/frigate/recordings`. Recording segments are remuxed without video re-encoding [F1].
- The official installation guide recommends a tmpfs mount for `/tmp/cache` [F9]. This keeps the short rolling write load in RAM rather than on persistent storage.
- An alerts-only configuration sets continuous retention to zero and retains only segments that overlap alerts [F1]. Review alerts can be restricted to `person`, and zones can further restrict which people create alerts [F2]. Frigate defaults include car alerts unless tracked/review labels are restricted to person [F2, F4].
- Frigate 0.17.2 source defines five-second default pre-capture and post-capture values and permits pre-capture up to 60 seconds [F3, F5]. The recording maintainer holds non-matching segments until they are older than the configured event pre-capture window, then drops them [F6].
- Frigate 0.17.2 cleanup source computes retention cutoffs from configured day values using review-item `end_time`. It normally runs cleanup at `expire_interval`; the default is 60 minutes [F3, F6]. If less than one hour of storage remains, Frigate can delete the oldest hour without regard to retention [F1].
- Frigate has an official Reolink stream recipe. It warns that Reolink feature and stream behavior is inconsistent across models. It recommends HTTP-FLV for 5 MP and lower cameras, CBR or "fluency first," and an interframe interval equal to the frame rate [F10].
- Frigate recommends a 5 fps detection stream and normally uses a separate main stream for recording [F10].
- Official configuration examples show `mqtt.enabled: False`, so Frigate can run without Home Assistant or an MQTT broker [F7].
- Frigate says one entry-level accelerator is sufficient for one to six cameras with occasional motion. Hardware video decoding is recommended for multiple cameras [F8].

**Assessment**

The Frigate flow is camera local main and substreams -> Frigate/go2rtc -> Frigate motion gate -> Frigate person detector -> person alert policy -> retained recording segments. The record stream is continuously ingested into tmpfs, but only qualifying person-alert segments are persisted to recording storage when the explicit policy above is used.

Use a dedicated Frigate Service and persistent Frigate database. Do not run Frigate as a Home Assistant child process if process independence is a strict requirement. Home Assistant can read Frigate later, but Frigate startup, detection, recording, and cleanup must not need Home Assistant.

Frigate centralizes four camera streams, detection, metadata, temporary cache, and cleanup. This gives one clear policy owner but also one larger failure domain. If Frigate, its detector, tmpfs, database, or host fails, all four central recordings can fail. Camera-native microSD person recording can reduce this risk if concurrent operation is verified.

For this homelab, the RX 7600 already serves Ollama. Frigate supports AMD ROCm detection, but sharing one GPU makes Ollama load and the GPU driver part of the camera failure domain. This report does not assume that shared operation is reliable. Prefer a separate supported detector or prove GPU isolation and worst-case latency under simultaneous Ollama and four-camera load before production use.

### 4. Agent DVR local AI

**Documented facts**

- Agent DVR can record in Alert mode. Its camera recording settings include a pre-record Buffer and an inactivity timeout. It can save a raw main or record stream to avoid re-encoding [A1].
- Its built-in object detection uses local ONNX models and can select Person. The built-in local AI needs a license or active subscription [A2].
- Its documented AI alert-filter flow uses motion to invoke object recognition, raises an alert when a selected object is found, and records in Alert mode [A2].
- Storage management supports maximum file age in hours at media-directory and device levels [A3].
- If AI is unavailable, the configurable Motion Pass-through control can let motion events pass as valid alerts [A2]. This favors capture availability but violates strict person-only persistence during detector failure.

**Assessment**

Agent DVR can meet the main criteria with Buffer, Person-only local AI, Alert recording mode, and a maximum age of 336 hours. Set Motion Pass-through off if person-only persistence is strict. That choice means an AI outage produces no clips instead of extra motion clips.

Agent DVR is credible when local feedback-based suppression is valuable. The project documents local per-camera learning from accepted and rejected detections [A2]. However, it adds a commercial license condition for built-in AI, and a four-camera capacity statement comparable to Frigate's planning guide was not found in the reviewed official material. Run a sustained load test before selection.

### 5. Alternatives that do not improve this decision

**Scrypted NVR:** Scrypted provides local smart detections and a polished NVR interface, but its official design records every camera 24/7 [S1]. It requires at least three days of full-video capacity and at least a 1 TB storage disk. Its four-camera one-week estimates range from 1 TB at 1080p to 2.4 TB at 4K [S2]. It is a good continuous NVR, but it does not satisfy event-only persisted video.

**go2rtc plus a custom recorder:** go2rtc is useful as a local restream layer. Its MP4 endpoint can record future video for a requested duration, but the open upstream pre-record request states that it does not support lookback [G1, G2]. Adding a detector, ring buffer, event state machine, atomic file finalization, index, cleanup, and health model would reproduce the deep functions already owned by Frigate or Agent DVR. This does not improve reliability or maintainability.

Moonfire NVR, Shinobi, and other general NVRs were not promoted because the reviewed primary-source evidence did not show a material advantage over Frigate for this exact combination of person-only persistence, bounded pre-capture, native age retention, and Home Assistant independence.

## Sizing and operations

### Network and temporary cache

Frigate and Agent DVR must ingest streams continuously to hold pre-roll. For `N` cameras with record-stream bitrate `B` Mbit/s, approximate inbound record bandwidth is:

`N * B Mbit/s`

Temporary video bytes for `P` seconds of buffered record video are approximately:

`N * B * P / 8 MB`

This excludes segment overlap, container overhead, detection frames, audio, previews, and safety margin. Measure actual main and substream rates. Do not size from resolution alone. For Frigate, include enough tmpfs for the maximum pre-capture window, in-progress segments, concurrent camera activity, and delayed processing. The official 1 GB tmpfs example is a starting example, not a four-camera guarantee [F9].

Frigate also needs shared memory for decoded detection frames. Its installation guide gives a formula and states that the default 128 MB is suitable for two cameras detecting at 720p. Four cameras need a calculation from their actual detection resolutions [F9].

### Persistent event storage

For average person-event duration `E` seconds, `K` retained events per camera per day, `N` cameras, bitrate `B` Mbit/s, and `D = 14` days, approximate payload storage is:

`N * K * E * B * D / 8 MB`

Include pre-capture, post-capture, overlapping event behavior, audio, thumbnails, database growth, filesystem overhead, and at least a substantial free-space reserve. Measure a busy week, then size for a worse week. Frigate emergency cleanup can violate 14-day retention when storage is nearly full [F1]. Agent DVR can also delete by size if both age and size controls are active [A3].

### Four-camera compute

- Use camera substreams for detection and main streams for recording.
- Start near Frigate's recommended 5 detection fps. Higher detection resolution and frame rate increase decode and detector work [F10].
- Use hardware video decoding. The object detector does not decode video [F7].
- Test all four cameras with simultaneous person movement, night mode, rain, and an Ollama workload.
- Track detector inference latency, skipped frames, stream restarts, tmpfs use, recording gaps, database health, disk free space, and cleanup success.
- Keep camera and homelab clocks synchronized. Event boundaries and age retention depend on reliable time.

### Reliability checks

Test the user-visible result, not only component health:

1. Walk into each scene from every entry edge and verify that the saved clip starts before first visible entry.
2. Trigger all four cameras at the same time and verify event classification, complete clips, and cleanup metadata.
3. Restart Home Assistant during an event. The primary recorder must continue without a gap.
4. Restart the recorder and detector separately. Record the loss window and verify automatic recovery.
5. Disconnect one camera network link and restore it. Other cameras must continue.
6. Fill a test volume to each warning threshold and verify that alerts occur before early deletion.
7. Advance test file ages beyond 14 days and verify the actual cleanup delay.
8. Block camera internet access and verify local streams, events, recording, playback, and administration.

## Risks and open verification items

1. **Exact doorbell identity:** Record the product name, color variant, hardware version, power mode, and firmware. "Reolink doorbell" is not enough. Battery first generation, battery second generation, plug-in WiFi, and PoE have different pre-record and local-stream behavior [R4].
2. **Firmware behavior:** Verify that the installed firmware exposes a stable local main stream and substream, Person detection where required, pre-motion recording, and FTP where required. Reolink and Frigate both warn that behavior varies by model or hardware [R1, R5, F10].
3. **Camera-native pre-roll length:** Reolink only documents "several seconds" that vary by model and hardware. Measure the actual clip [R1].
4. **microSD versus FTP:** Verify whether this exact doorbell can write the same person event to microSD and FTP concurrently, and whether both copies contain pre-roll. This was not established by the reviewed official material.
5. **FTP age source:** Decide whether 14 days starts at event time, upload completion, or server modification time. Delayed uploads and camera clock errors can change deletion time.
6. **Frigate stream protocol:** Test HTTP-FLV and RTSP against the installed doorbell. Use the Frigate 0.17.2 Reolink recipe, but do not assume one protocol is stable on every model [F10].
7. **Person policy:** Decide whether a person anywhere in frame is retained or only a person in one or more zones. Test threshold, minimum area, masks, stationary behavior, and night performance.
8. **Detector failure policy:** Decide between fail-open and fail-closed. Fail-open keeps motion video when AI is unavailable but violates person-only persistence. Fail-closed preserves the storage rule but can lose security events.
9. **Retention semantics:** Confirm that "14 days" means no normal deletion before 14 days and deletion on the next cleanup pass. Frigate's default pass is hourly, not instantaneous [F3, F6].
10. **Storage pressure:** Size storage and alerts so emergency deletion cannot occur during the 14-day target window [F1].
11. **GPU contention:** Prove or avoid resource sharing between Frigate and Ollama on the RX 7600. A separate detector gives a cleaner failure boundary.
12. **Fallback independence:** If microSD fallback is selected, test it while Frigate, FTP, and the homelab are unavailable. Confirm retrieval after service restoration.

## Comparison summary

Frigate is the only assessed architecture with direct primary-source support for all core mechanics: local stream ingestion, bounded temporary pre-capture, person-only alert retention, native retention days, and operation without Home Assistant. The person-only policy requires explicit tracking, review-label, and retention configuration; default alerts include cars [F1-F6].

Reolink-to-FTP has lower system complexity, but the exact doorbell must prove reliable person filtering and FTP pre-roll. It needs server-side age cleanup because camera storage alone does not provide an exact 14-day rule.

Agent DVR has a documented local-AI path, but it has license and policy-control gates. Scrypted NVR intentionally persists 24/7 video, so it does not meet this event-only requirement. go2rtc does not supply pre-event lookback; a custom recorder would need to own the missing functions. These comparisons do not select an architecture.

## Sources

All sources were retrieved on 2026-08-23. Official documentation and official project source are primary sources. GitHub issue [G2] is maintainer-controlled upstream material but has lower authority than released documentation or source.

### Reolink

- **[R1]** Reolink, [Introduction to Pre-Motion Record](https://support.reolink.com/articles/900000784786-Introduction-to-Pre-Motion-Record/).
- **[R2]** Reolink, [How to Set up FTP for Reolink Products](https://support.reolink.com/articles/360020081034-How-to-Set-up-FTP-for-Reolink-Products/).
- **[R3]** Reolink, [How to Set up Record Schedule for Reolink Cameras via Reolink App](https://support.reolink.com/articles/360003592694-How-to-Set-up-Record-Schedule-for-Reolink-Cameras-via-Reolink-App/).
- **[R4]** Reolink, [Introduction to Reolink Video Doorbell Cameras](https://support.reolink.com/articles/16929500357657-Introduction-to-Reolink-Video-Doorbell-Cameras/).
- **[R5]** Reolink, [Which Cameras/NVRs Support FTP Uploading](https://support.reolink.com/articles/900000625446-Which-Cameras-NVRs-Support-FTP-Uploading/).
- **[R6]** Reolink, [Introduction to the Settings on Reolink Web Interface](https://support.reolink.com/articles/900000593263-Introduction-to-the-Settings-on-Reolink-Web-Interface/).

### Home Assistant

- **[H1]** Home Assistant, [Record camera feed](https://www.home-assistant.io/actions/camera.record/).
- **[H2]** Home Assistant, [Reolink integration](https://www.home-assistant.io/integrations/reolink/).

### Frigate

- **[F1]** Frigate 0.17.2, [Recording](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/configuration/record.md).
- **[F2]** Frigate 0.17.2, [Review](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/configuration/review.md).
- **[F3]** Frigate 0.17.2 source, [record configuration model](https://github.com/blakeblackshear/frigate/blob/v0.17.2/frigate/config/camera/record.py).
- **[F4]** Frigate 0.17.2 source, [review configuration model](https://github.com/blakeblackshear/frigate/blob/v0.17.2/frigate/config/camera/review.py) and [object configuration model](https://github.com/blakeblackshear/frigate/blob/v0.17.2/frigate/config/camera/objects.py).
- **[F5]** Frigate 0.17.2 source, [constants](https://github.com/blakeblackshear/frigate/blob/v0.17.2/frigate/const.py).
- **[F6]** Frigate 0.17.2 source, [recording cache maintainer](https://github.com/blakeblackshear/frigate/blob/v0.17.2/frigate/record/maintainer.py) and [recording cleanup](https://github.com/blakeblackshear/frigate/blob/v0.17.2/frigate/record/cleanup.py).
- **[F7]** Frigate 0.17.2, [Frigate Configuration](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/configuration/index.md).
- **[F8]** Frigate 0.17.2, [Planning a New Installation](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/frigate/planning_setup.md) and [Recommended hardware](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/frigate/hardware.md).
- **[F9]** Frigate 0.17.2, [Installation](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/frigate/installation.md).
- **[F10]** Frigate 0.17.2, [Camera Specific Configurations: Reolink Cameras](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/configuration/camera_specific.md#reolink-cameras) and [Camera setup](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/frigate/camera_setup.md).

### Agent DVR

- **[A1]** iSpyConnect, [Agent DVR: Editing Cameras](https://www.ispyconnect.com/docs/agent/editing-cameras#recording).
- **[A2]** iSpyConnect, [Agent DVR: AI Configuration](https://www.ispyconnect.com/docs/agent/ai-config).
- **[A3]** iSpyConnect, [Agent DVR: Storage Management](https://www.ispyconnect.com/docs/agent/storage).

### Screened alternatives

- **[S1]** Scrypted, [Scrypted NVR](https://docs.scrypted.app/scrypted-nvr/).
- **[S2]** Scrypted, [Scrypted NVR Storage Setup](https://docs.scrypted.app/scrypted-nvr/recording-storage).
- **[G1]** go2rtc, [Project README and MP4 module](https://github.com/AlexxIT/go2rtc#module-mp4).
- **[G2]** go2rtc, [Upstream pre-record feature request](https://github.com/AlexxIT/go2rtc/issues/876).
