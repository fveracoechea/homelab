# Frigate deployment and AMD acceleration research

Issue: [#17](https://github.com/fveracoechea/homelab/issues/17)

Research date: 2026-08-23

Camera inventory update: 2026-08-27

Scope: Frigate `0.17.2`, with no deployment selection. Frigate and ROCm claims below use version-pinned first-party sources. NixOS package and module claims were checked with nix-mcp against the flake's pinned nixpkgs revision.

## Repository context

- `homelab` is the physical AMD host. The context records a Ryzen iGPU and a dedicated RX 7600, which Ollama already uses with ROCm.
- Caddy is the existing ingress. The current declarative OCI service pattern is rootful Podman plus `environmentFiles` under `/var/lib`.
- There is no Frigate service, RTSP/ONVIF, or MQTT configuration in this checkout. The purchased camera is a Reolink Battery Video Doorbell (2nd Gen). Storage requirements and whether Home Assistant integration is needed remain unknown.

## Current camera gate

The purchased Battery Video Doorbell (2nd Gen) cannot currently provide the continuous local stream that Frigate requires:

- Reolink classifies battery-powered Wi-Fi cameras as requiring a Reolink Home Hub for CGI, RTSP, and ONVIF. The model-specific FAQ says standalone RTSP/ONVIF in Wired Power Mode is a future firmware feature, not a current capability. [^reolink-protocols] [^reolink-doorbell-faq]
- Wired Power Mode enables always-on operation and continuous recording on the device, but it does not currently add standalone RTSP/ONVIF. A Home Hub-connected doorbell cannot enter Wired Power Mode under the currently documented firmware behavior. [^reolink-doorbell-faq] [^reolink-power-modes]
- Reolink states that a battery-camera RTSP preview through a Home Hub or NVR ends after at most five minutes when the camera returns to sleep. This is not a continuous Frigate ingest path. [^reolink-rtsp]

Do not implement Frigate against this camera until released firmware provides a verified continuous standalone stream, or the camera is replaced with a plug-in Wi-Fi or PoE model with documented standalone CGI, RTSP, and ONVIF. Buying a Home Hub does not clear the current stream gate.

Record the camera return deadline and decide before it expires. If continuous NVR ingest is required, replace the camera. Buy a Home Hub only if its non-Frigate functions have independent value. Waiting for firmware means explicitly accepting the risk that the return option expires first.

## Deployment options

| Concern | Native NixOS | Declarative Podman OCI |
| --- | --- | --- |
| Service shape | `services.frigate.settings` accepts Frigate YAML as a Nix attribute set. Its `hostname` option configures an Nginx virtual host. [^nix-pinned-frigate-module] | `virtualisation.oci-containers` runs OCI containers as systemd services. Its backend defaults to Podman for this Host's state version. [^nix-pinned-oci-module] |
| Upstream release | The pinned nixpkgs package is Frigate 0.17.2 and depends on ordinary `onnxruntime`, not `onnxruntime-migraphx`; it does not reproduce the official ROCm image runtime. [^nix-pinned-frigate] | Frigate 0.17.2 documents the `-rocm` image for AMD object detection. The image Dockerfile installs ROCm 7.1.1 and its requirements pin ONNX Runtime MIGraphX 1.23.1. [^frigate-detector] [^frigate-dockerfile] [^frigate-requirements] |
| Hardware access | The module option documents AMD VA-API support when `hardware.graphics.enable` is enabled and `vaapiDriver = "radeonsi"` is used. [^nix-pinned-frigate-module] | OCI containers can attach named host devices through `devices`. [^nix-pinned-oci-module] |
| Secret boundary | Do not put camera or MQTT credentials in the Nix attribute set: this is configuration, not a secret boundary. | OCI `environmentFiles` loads absolute-path environment files. Frigate substitutes only supported `FRIGATE_*` variables in config values. [^nix-pinned-oci-module] [^frigate-config] |

Neither option is selected by this research. The later decision must use the camera inventory and hardware gates below.

## GPU device and access paths

- ROCm in Frigate requires `/dev/kfd` and `/dev/dri`. AMD documents `/dev/kfd` as the shared compute interface and `/dev/dri/renderD*` as individual GPU nodes; passing an individual render node restricts the container to that GPU while `/dev/kfd` remains required. [^amd-container]
- The OCI device list can therefore pass `/dev/kfd` plus the measured RX 7600 render node for ROCm inference, and, if separate decode is required, the measured Ryzen iGPU render node for VA-API decode. Do not assume `renderD128`, `renderD129`, or a ROCm index. Measure them on the host, then verify `rocminfo` and `amd-smi list` inside the container. AMD states that these tools enumerate only GPUs passed into the container. [^amd-container]
- For AMD video decode, Frigate 0.17.2 specifies `LIBVA_DRIVER_NAME=radeonsi` and `ffmpeg.hwaccel_args: preset-vaapi`. It says hardware decode has no CPU fallback when explicitly configured, so a failed decode configuration is a release blocker. [^frigate-video]
- Frigate permits `HSA_OVERRIDE_GFX_VERSION` where a GPU needs a chipset override and directs operators to inspect `rocminfo` first. AMD's ROCm 7.1.1 matrix lists `gfx1100` and `gfx1101`, not `gfx1102`; any RX 7600 override is a measured compatibility experiment, not an asserted supported configuration. [^frigate-detector] [^amd-rocm-matrix]

## Credentials and network boundary

- Keep RTSP/ONVIF and optional MQTT credentials in a root-owned runtime file under `/var/lib/frigate/`, not in the Nix store or a generated Frigate configuration file. Use only documented `{FRIGATE_*}` substitutions. Frigate advises Docker environment variables or secrets instead of its plaintext `environment_vars` configuration. [^frigate-config] [^frigate-advanced]
- Persist `/config`: Frigate stores its configuration and SQLite database there. Persist the media paths separately, and use a tmpfs for `/tmp/cache`. [^frigate-install]
- Publish or proxy only authenticated port `8971`. Frigate describes `5000` as an unauthenticated internal UI/API port; it must not be exposed through Caddy. Publish `8554` or `8555` only when RTSP restreaming or WebRTC is required and after defining LAN and mesh-interface firewall policy. [^frigate-install] [^frigate-auth]
- MQTT is optional for Frigate but required for the Home Assistant integration; both systems must connect to the same broker. No broker is declared in this repository. [^frigate-install]

## Camera inventory and hardware gates

Before selecting native NixOS or declarative Podman OCI:

1. Inventory each camera's address, RTSP path, codec/profile, main and detect resolution, FPS, audio, ONVIF credentials, retention, and direct-restream/WebRTC requirement.
2. Decide whether Home Assistant events are required. If yes, identify the shared MQTT broker and its credentials boundary.
3. Size `/dev/shm` from the final detect resolutions. Frigate gives a 128 MB baseline for two 720p detect cameras and a per-camera formula; include its stated 40 MB logging allowance. [^frigate-install]
4. Map the RX 7600 and Ryzen iGPU PCI identities to their `/dev/dri/renderD*` nodes. Pass only the required nodes with `/dev/kfd`; run `rocminfo` and `amd-smi list` inside the candidate container.
5. Test iGPU VA-API against every selected camera codec/profile. Require clean Frigate logs and hardware decode before enabling recordings.
6. Decide whether ROCm inference is required. The pinned native package does not include the official MIGraphX runtime, so ROCm is an OCI-specific candidate unless a separate native packaging design is researched. [^nix-pinned-frigate]
7. If evaluating OCI ROCm, use the Frigate 0.17.2 `-rocm` image and test native GPU detection first. Only then test an `HSA_OVERRIDE_GFX_VERSION` value if needed. Frigate recommends first starting the ONNX detector with object detection disabled so model conversion can complete and cache, then enabling detection. [^frigate-detector]
8. Before a sustained camera plus Ollama test, define numeric pass/fail limits for detection latency, dropped frames, stream restarts, decode errors, VRAM pressure, and Ollama interruption. Use CPU detection or a separate detector if shared RX 7600 operation fails.
9. Validate the final credential-free configuration with the exact selected runtime before deployment. For OCI, Frigate documents a container command that returns nonzero for an invalid configuration. [^frigate-advanced]

## Sources

[^nix-frigate-settings]: NixOS option index, [`services.frigate.settings`](https://search.nixos.org/options?channel=unstable&show=services.frigate.settings).
[^nix-frigate-hostname]: NixOS option index, [`services.frigate.hostname`](https://search.nixos.org/options?channel=unstable&show=services.frigate.hostname).
[^nix-frigate-vaapi]: NixOS option index, [`services.frigate.vaapiDriver`](https://search.nixos.org/options?channel=unstable&show=services.frigate.vaapiDriver).
[^nix-oci-backend]: NixOS option index, [`virtualisation.oci-containers.backend`](https://search.nixos.org/options?channel=unstable&show=virtualisation.oci-containers.backend).
[^nix-oci-devices]: NixOS option index, [`virtualisation.oci-containers.containers.<name>.devices`](https://search.nixos.org/options?channel=unstable&show=virtualisation.oci-containers.containers.%3Cname%3E.devices).
[^nix-oci-environment-files]: NixOS option index, [`virtualisation.oci-containers.containers.<name>.environmentFiles`](https://search.nixos.org/options?channel=unstable&show=virtualisation.oci-containers.containers.%3Cname%3E.environmentFiles).
[^nix-pinned-frigate]: nix-mcp read of [`pkgs/by-name/fr/frigate/package.nix`](https://github.com/NixOS/nixpkgs/blob/2fcb964de67fcf60b43471c55d5d99e61a9ccb5a/pkgs/by-name/fr/frigate/package.nix) at the flake's pinned nixpkgs revision, accessed 2026-08-27.
[^nix-pinned-frigate-module]: nix-mcp read of [`nixos/modules/services/video/frigate.nix`](https://github.com/NixOS/nixpkgs/blob/2fcb964de67fcf60b43471c55d5d99e61a9ccb5a/nixos/modules/services/video/frigate.nix) at the flake's pinned nixpkgs revision, accessed 2026-08-27.
[^nix-pinned-oci-module]: nix-mcp read of [`nixos/modules/virtualisation/oci-containers.nix`](https://github.com/NixOS/nixpkgs/blob/2fcb964de67fcf60b43471c55d5d99e61a9ccb5a/nixos/modules/virtualisation/oci-containers.nix) at the flake's pinned nixpkgs revision, accessed 2026-08-27.
[^frigate-install]: Frigate 0.17.2, [`installation.md`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/frigate/installation.md).
[^frigate-config]: Frigate 0.17.2, [`configuration/index.md`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/configuration/index.md).
[^frigate-advanced]: Frigate 0.17.2, [`configuration/advanced.md`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/configuration/advanced.md).
[^frigate-auth]: Frigate 0.17.2, [`configuration/authentication.md`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/configuration/authentication.md).
[^frigate-video]: Frigate 0.17.2, [`hardware_acceleration_video.md`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/configuration/hardware_acceleration_video.md).
[^frigate-detector]: Frigate 0.17.2, [`object_detectors.md`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docs/docs/configuration/object_detectors.md).
[^frigate-dockerfile]: Frigate 0.17.2, [`docker/rocm/Dockerfile`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docker/rocm/Dockerfile).
[^frigate-requirements]: Frigate 0.17.2, [`docker/rocm/requirements-wheels-rocm.txt`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docker/rocm/requirements-wheels-rocm.txt).
[^amd-container]: AMD ROCm 7.1.1, [running ROCm Docker containers](https://rocm.docs.amd.com/projects/install-on-linux/en/docs-7.1.1/how-to/docker.html).
[^amd-rocm-matrix]: AMD ROCm 7.1.1, [compatibility matrix](https://rocm.docs.amd.com/en/docs-7.1.1/compatibility/compatibility-matrix.html).
[^reolink-protocols]: Reolink, [Which Reolink Products Support CGI/RTSP/ONVIF](https://support.reolink.com/articles/900000617826-Which-Reolink-Products-Support-CGI-RTSP-ONVIF/), accessed 2026-08-27.
[^reolink-doorbell-faq]: Reolink, [FAQs for Reolink Video Doorbell (2nd Gen)](https://support.reolink.com/articles/60553722670617-FAQs-for-Reolink-Video-Doorbell-2nd-Gen/), accessed 2026-08-27.
[^reolink-power-modes]: Reolink, [Introduction to Power Modes of Reolink Battery Video Doorbells](https://support.reolink.com/articles/56608051231129-Introduction-to-Power-Modes-of-Reolink-Battery-Video-Doorbells-Dual-Power-Support/), accessed 2026-08-27.
[^reolink-rtsp]: Reolink, [Introduction to RTSP](https://support.reolink.com/articles/900000630706-Introduction-to-RTSP/), accessed 2026-08-27.
