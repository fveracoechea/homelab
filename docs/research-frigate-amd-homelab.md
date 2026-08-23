# Frigate deployment and AMD acceleration research

Issue: [#17](https://github.com/fveracoechea/homelab/issues/17)

Research date: 2026-08-23

Pinned base: nixpkgs `2fcb964de67fcf60b43471c55d5d99e61a9ccb5a`, Frigate `0.17.2`

## Decision

Use rootful declarative Podman with the official amd64 image `ghcr.io/blakeblackshear/frigate:0.17.2-rocm@sha256:6268386f9ef436feb8b3e3218566d11ef56cdf140afe165063d74f6a5367c1b2`. Keep the Frigate configuration declarative and free of credentials, use the Ryzen iGPU for VA-API decode, and expose the RX 7600 to ROCm inference by measured ROCm UUID. Do not use native `services.frigate` for this hardware plan: its package lacks the upstream ROCm/MIGraphX runtime, and its module owns an Nginx frontend that does not fit the homelab's existing Caddy ingress.[^frigate-image]

Treat RX 7600 inference as a measured compatibility path, not an officially supported ROCm 7.1.1 combination. Frigate supplies the required image and documents the override mechanism, but AMD's ROCm 7.1.1 Radeon Linux matrix omits the RX 7600. Test native `gfx1102` first, then use `HSA_OVERRIDE_GFX_VERSION=11.0.0` only if startup or model compilation fails.[^rocm-radeon-711] [^frigate-detectors]

## Pinned homelab facts

- The flake pins nixpkgs revision `2fcb964de67fcf60b43471c55d5d99e61a9ccb5a`; its `pkgs.frigate` is `0.17.2`.[^nix-package]
- Caddy owns wildcard-certificate ingress. Paperless-gpt already establishes the local pattern of rootful `virtualisation.oci-containers` with credentials in an external file below `/var/lib`.[^repo-caddy] [^repo-paperless-gpt]
- Ollama is native `services.ollama` with `pkgs.ollama-rocm`, `ROCR_VISIBLE_DEVICES=0`, and `HSA_OVERRIDE_GFX_VERSION=11.0.0` for the RX 7600.[^repo-ollama]
- A read-only host inspection confirmed RX 7600 PCI `0000:03:00.0` is `renderD128` (`1002:7480`) and Ryzen iGPU PCI `0000:10:00.0` is `renderD129` (`1002:164e`). Use `/dev/dri/by-path/pci-0000:...-render` as host-side device sources so render-node renumbering does not silently swap GPUs.

## Deployment comparison

| Concern | Native `services.frigate` 0.17.2 | Declarative Podman OCI |
| --- | --- | --- |
| Version | Flake pins the Nix package and dependencies. | Pin the official amd64 manifest digest above, not `stable-rocm` or a bare tag.[^frigate-release] [^frigate-image] |
| Support shape | NixOS repackages Frigate as a Python service. Upstream documents Frigate as a container and recommends Docker Compose.[^nix-package] [^frigate-install] | Uses upstream's tested filesystem, S6 services, FFmpeg, Nginx, and ROCm dependency set. Podman supplies an OCI-compatible runtime, although Frigate documents Docker. |
| Configuration | `services.frigate.settings` generates YAML, validates it at build time by default, and copies it into `/run/frigate` at startup.[^nix-module] | Generate credential-free YAML from Nix and bind it read-only at `/config/config.yml`; mount writable `/var/lib/frigate/config` at `/config` for the database, generated JWT secret, model cache, and migrations.[^frigate-config] |
| State | The module manages `/var/lib/frigate`, `/var/cache/frigate`, and `/run/frigate` with a dedicated user.[^nix-module] | Bind persistent config and media directories, use tmpfs for `/tmp/cache`, and calculate `/dev/shm` from camera detect resolutions.[^frigate-install] |
| Ingress | The module enables Nginx and creates a Frigate virtual host, which competes with Caddy and duplicates ingress policy.[^nix-module] [^repo-caddy] | Publish authenticated port `8971` on `127.0.0.1` only, disable Frigate TLS, and proxy it through Caddy. Never publish unauthenticated port `5000`.[^frigate-auth] [^frigate-proxy] |
| Decode | The module adds `render`, supports `vaapiDriver = "radeonsi"`, and expects `hardware.graphics.enable` plus `preset-vaapi`.[^nix-module] | Pass the iGPU render node, set `LIBVA_DRIVER_NAME=radeonsi`, and use `preset-vaapi` with verified GPU selection.[^frigate-video] |
| Inference | The pinned package uses ordinary `python313Packages.onnxruntime`; it has no official-image equivalent ROCm dependency or module option. Included `rocminfo` is diagnostic only.[^nix-package] [^nix-module] | The official image installs ROCm `7.1.1` and ONNX Runtime MIGraphX `1.23.1`, the pair in AMD's compatibility matrix.[^frigate-rocm-dockerfile] [^frigate-rocm-requirements] [^rocm-711] |
| Credentials | Literal values in `services.frigate.settings` enter generated Nix-store YAML. A generic systemd `EnvironmentFile` override is possible but is not a first-class Frigate option. | The pinned OCI module has `environmentFiles`. Put only `{FRIGATE_*}` placeholders in declarative YAML and values in a root-owned mode `0600` file below `/var/lib/frigate`.[^nix-oci] [^frigate-config] |
| Rollback | Atomic with the flake and patched Nix package. | Atomic service/config declaration, with the prior image digest retained for rollback. |

## Recommended OCI boundary

Use the existing rootful Podman backend without `privileged = true`. Frigate, AMD, and Podman support explicit device passthrough.[^frigate-install] [^amd-container] [^podman-run]

Pass these devices:

- `/dev/kfd` for ROCm compute.
- RX 7600 `/dev/dri/by-path/pci-0000:03:00.0-render` to container `/dev/dri/renderD128` for inference.
- Ryzen iGPU `/dev/dri/by-path/pci-0000:10:00.0-render` to container `/dev/dri/renderD129` for decode.

Set `ROCR_VISIBLE_DEVICES` to the measured RX 7600 ROCm UUID. Do not copy Ollama's host-relative index `0` without measuring the container because device filtering can change visible indices. ROCm accepts UUIDs and states that device passthrough is stronger isolation than environment variables. Frigate 0.17.2 does not pass its detector `device` value into MIGraphX provider options, so container-level ROCr isolation is the reliable selector.[^rocm-isolation] [^frigate-model-util] [^onnx-migraphx]

For VA-API, Frigate 0.17.2 can select a GPU by numeric `ffmpeg.gpu` index, but its preset implementation does not sort render-node directory enumeration. Measure the in-container index in repeated restart tests. If it is unstable, use explicit FFmpeg VA-API arguments containing `/dev/dri/renderD129`. Confirm decode with `vainfo`, Frigate logs, and host GPU telemetry. Frigate has no CPU fallback when configured hardware decode fails.[^frigate-video] [^frigate-ffmpeg-presets]

For ROCm, first run container `rocminfo` with no architecture override and confirm that its only GPU is the RX 7600 `gfx1102`. Start one ONNX YOLOv9 detector with object detection disabled while Frigate compiles and caches the model, as upstream recommends. If loading or compilation fails, test `HSA_OVERRIDE_GFX_VERSION=11.0.0`; record it as an unsupported compatibility override, not hardware detection.[^frigate-detectors]

## Credentials and access

- Keep camera RTSP/ONVIF and optional MQTT credentials out of Nix expressions and image declarations. Load supported `FRIGATE_*` substitutions from `/var/lib/frigate/frigate.env` through OCI `environmentFiles`.[^frigate-config] [^nix-oci]
- Do not use Frigate `environment_vars` for secrets; upstream says these are plain text in the configuration and recommends container environment variables or secrets.[^frigate-advanced]
- Let Frigate generate `.jwt_secret` in persisted `/config`, or bind a root-owned secret as `/run/secrets/FRIGATE_JWT_SECRET`. Frigate checks the environment, `CREDENTIALS_DIRECTORY`, then persisted `.jwt_secret`.[^frigate-auth]
- Proxy only `127.0.0.1:8971` through Caddy. Port `5000` is unauthenticated and admin-equivalent. Publish `8554` and `8555` only if RTSP restream or WebRTC needs direct LAN/tailnet access, with interface-specific firewall rules.[^frigate-auth] [^frigate-install]
- Frigate 0.17.2 fixes several authorization and credential leaks, but its release notes list three unresolved advisories affecting viewer roles and logs/go2rtc/static recordings. Keep it LAN/tailnet-only and do not grant untrusted viewer accounts until a fixed release is pinned.[^frigate-release]

## Coexistence with Ollama

Ryzen iGPU decode does not use RX 7600 compute or its 8 GB VRAM. Frigate ROCm inference and Ollama do share the RX 7600. Visibility settings hide unwanted GPUs; they do not partition VRAM, compute units, or scheduling.[^repo-ollama] [^rocm-isolation]

There is no robust GPU resource limit in the current OCI declaration or ROCm process model. Use this operating policy:

1. Give the always-on NVR priority.
2. Start with one small Frigate ONNX detector and a 320x320 model.
3. Allow one Ollama model and one request at a time; unload models promptly where clients permit it.
4. Measure detection latency, dropped frames, RX VRAM, and Ollama failures under simultaneous text and vision requests.
5. If the workload approaches 8 GB or harms detection latency, move Ollama to CPU/on-demand operation, stop it during NVR-critical periods, or add a separate supported compute GPU. Do not tune around allocation failures.

Do not reuse Ollama's architecture override by assumption. Ollama's Nix package and Frigate's ROCm 7.1.1 image carry different user-space stacks and need independent tests.[^repo-ollama] [^frigate-rocm-dockerfile]

## Acceptance gates

No system configuration was built or changed during this research. Before deployment:

1. Confirm camera count, codecs, detect resolutions, retention, storage, and whether MQTT/Home Assistant integration is required.
2. Calculate `--shm-size` and `/tmp/cache` tmpfs from final camera settings.[^frigate-install]
3. Verify the PCI by-path mappings and confirm iGPU codec/profile support with `vainfo`.
4. Record the RX 7600 ROCm UUID, select by UUID, and confirm `rocminfo` exposes only that GPU.
5. Test native `gfx1102` before the `11.0.0` override and prove MIGraphX, not CPU, runs repeated inference.
6. Validate declarative YAML with the exact pinned image and synthetic credentials, never real credentials in a build sandbox or Nix store.
7. Run a sustained camera plus Ollama load test and record latency, FFmpeg errors, dropped frames, GPU use, VRAM, and recovery.
8. Recheck unresolved advisories. Prefer a later fixed image if available before implementation and repeat the pinned native comparison.

## Blockers and unknowns

- Camera inventory and retention are unknown, so shared memory, tmpfs, media capacity, and decode throughput cannot be sized.
- The ONNX person-detection model and its source/license are not selected; the ROCm image has no default ONNX model.[^frigate-detectors]
- MQTT is optional for Frigate but required for its Home Assistant integration; this repo has no declared MQTT broker.[^frigate-install]
- RX 7600 `gfx1102` is absent from AMD's ROCm 7.1.1 Radeon Linux support list. The override needs an end-to-end host proof.[^rocm-radeon-711]
- The RX 7600 ROCm UUID and stable in-container VA-API selection have not been measured.
- Safe simultaneous Frigate and Ollama use cannot be decided without a sustained test using the selected models.
- Frigate 0.17.2 has disclosed unresolved authorization issues; network restriction does not make untrusted viewer roles safe.[^frigate-release]

## Sources

[^repo-caddy]: [`services/caddy.nix`](../services/caddy.nix)
[^repo-paperless-gpt]: [`services/paperless-gpt.nix`](../services/paperless-gpt.nix)
[^repo-ollama]: [`services/ollama.nix`](../services/ollama.nix)
[^nix-package]: NixOS/nixpkgs, pinned [`pkgs/by-name/fr/frigate/package.nix`](https://github.com/NixOS/nixpkgs/blob/2fcb964de67fcf60b43471c55d5d99e61a9ccb5a/pkgs/by-name/fr/frigate/package.nix)
[^nix-module]: NixOS/nixpkgs, pinned [`nixos/modules/services/video/frigate.nix`](https://github.com/NixOS/nixpkgs/blob/2fcb964de67fcf60b43471c55d5d99e61a9ccb5a/nixos/modules/services/video/frigate.nix)
[^nix-oci]: NixOS/nixpkgs, pinned [`nixos/modules/virtualisation/oci-containers.nix`](https://github.com/NixOS/nixpkgs/blob/2fcb964de67fcf60b43471c55d5d99e61a9ccb5a/nixos/modules/virtualisation/oci-containers.nix)
[^frigate-release]: Frigate, [`0.17.2` release](https://github.com/blakeblackshear/frigate/releases/tag/v0.17.2)
[^frigate-image]: GitHub Container Registry, [Frigate `0.17.2-rocm` manifests](https://github.com/blakeblackshear/frigate/pkgs/container/frigate/982027592?tag=0.17.2-rocm)
[^frigate-install]: Frigate, [Installation](https://docs.frigate.video/frigate/installation/)
[^frigate-config]: Frigate, [Configuration and environment substitution](https://docs.frigate.video/configuration/)
[^frigate-advanced]: Frigate, [Advanced options](https://docs.frigate.video/configuration/advanced/)
[^frigate-auth]: Frigate, [Authentication](https://docs.frigate.video/configuration/authentication/)
[^frigate-proxy]: Frigate, [Reverse proxy](https://docs.frigate.video/guides/reverse_proxy/)
[^frigate-video]: Frigate, [Video decoding](https://docs.frigate.video/configuration/hardware_acceleration_video/)
[^frigate-detectors]: Frigate, [AMD/ROCm and ONNX detectors](https://docs.frigate.video/configuration/object_detectors/#amdrocm-gpu-detector)
[^frigate-rocm-dockerfile]: Frigate `0.17.2`, [`docker/rocm/Dockerfile`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docker/rocm/Dockerfile)
[^frigate-rocm-requirements]: Frigate `0.17.2`, [`docker/rocm/requirements-wheels-rocm.txt`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/docker/rocm/requirements-wheels-rocm.txt)
[^frigate-model-util]: Frigate `0.17.2`, [`frigate/util/model.py`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/frigate/util/model.py)
[^frigate-ffmpeg-presets]: Frigate `0.17.2`, [`frigate/ffmpeg_presets.py`](https://github.com/blakeblackshear/frigate/blob/v0.17.2/frigate/ffmpeg_presets.py)
[^amd-container]: AMD ROCm, [Run ROCm containers](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/how-to/docker.html)
[^rocm-isolation]: AMD ROCm, [GPU isolation](https://rocm.docs.amd.com/en/docs-7.2.3/conceptual/gpu-isolation.html)
[^rocm-711]: AMD ROCm, [`7.1.1` compatibility matrix](https://rocm.docs.amd.com/en/docs-7.1.1/compatibility/compatibility-matrix.html)
[^rocm-radeon-711]: AMD ROCm on Radeon, [`7.1.1` Linux support matrix](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.1.1/docs/compatibility/compatibilityrad/native_linux/native_linux_compatibility.html)
[^onnx-migraphx]: ONNX Runtime, [MIGraphX provider](https://onnxruntime.ai/docs/execution-providers/MIGraphX-ExecutionProvider.html)
[^podman-run]: Podman, [`podman-run(1)`](https://docs.podman.io/en/latest/markdown/podman-run.1.html)
