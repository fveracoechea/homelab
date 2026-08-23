# Event-Retention Storage Guardrails

Research date: 2026-08-23

Issue: [#19, Research event-retention storage guardrails](https://github.com/fveracoechea/homelab/issues/19)

## Decision summary

Use Frigate to select and expire 14-day `person` review-item media. Put Frigate state on a fail-closed, preallocated, fixed-size ext4 filesystem with a 200 GiB outer allocation. This is the only option assessed here that gives Frigate an accurate low-space signal and also prevents it from consuming the shared root filesystem beyond the budget.

Do not use systemd deletion as the normal retention owner. Keep ext4 project quota as the second choice if a nested filesystem is rejected, but add a quota-aware pressure service because Frigate cannot see project quota headroom.

The two requirements are conditional, not absolute. A 200 GiB budget can hold 14 days only while all data in scope averages at most 14.29 GiB/day, about 173 KiB/s. If the 14-day set is larger, the system must either delete data younger than 14 days, reject new media, or exceed 200 GiB. Issue #23 must choose which invariant wins.

## Scope and terms

Frigate 0.14 and later calls a time period with one or more tracked objects a **review item**. It classifies review items as alerts or detections. The old UI term **event** meant a tracked object, not a review item. This report uses **person-event retention** for the requested policy and names Frigate objects precisely where behavior depends on them.[^frigate-review]

The **operating budget** is all persistent Frigate state under `/var/lib/frigate`, unless issue #23 explicitly excludes exports or the SQLite database. On NixOS, the native Service patches Frigate's media and config base from `/media/frigate` and `/config` to `/var/lib/frigate`; it also uses `/var/lib/frigate/frigate.db`, runs as the `frigate` user, and declares `StateDirectory=frigate`.[^nixpkgs-package][^nixpkgs-module]

## Relevant homelab facts

- The repository declares `/` as ext4 on `/dev/nvme0n1p2`. There is no separate `/var` or media filesystem.[^repo-hardware]
- A read-only inspection on 2026-08-23 showed one 1.8 TiB ext4 partition for `/`, `/nix/store`, and Podman overlay storage. It had 107 GiB used and 1.6 TiB available. The NVMe also has a 1 GiB EFI partition and 8.8 GiB swap partition.
- The root mount options were `rw,relatime`. Its ext4 superblock had 4 KiB blocks, 256-byte inodes, and neither `project` nor `quota` enabled. Project quota therefore needs a filesystem feature and mount change before use.[^ext4][^tune2fs]
- The filesystem reserves 24,290,455 blocks, about 92.7 GiB, for its reserved-block user or group. This reserve helps privileged processes continue when unprivileged Services can no longer allocate blocks, but it is not a per-Service budget.[^tune2fs]
- The Host ran NixOS 26.11, Linux 6.18.37, and systemd 261.1. Its `systemd-tmpfiles-clean.timer` was active and runs 15 minutes after boot and once per day.
- The current repository has no Frigate Service or event-media path. This ticket therefore informs issue #23 rather than changing an existing retention deployment.
- Nix's current unstable index provides Frigate 0.17.2. The NixOS module provides `services.frigate.settings`, stores state under `/var/lib/frigate`, and runs the Service as a dedicated `frigate` system user.[^nix-mcp]

## Frigate-native retention and low-space cleanup

### What it can enforce

Frigate can track only `person`, or can restrict alert and detection labels to `person`. It can keep recordings that overlap matching alerts or detections for 14 days. Recording retention chooses the largest matching retention period, so continuous or motion settings must not accidentally extend the requested set.[^frigate-review][^frigate-record]

A minimal semantic policy is:

- track `person`;
- create only the required `person` alerts or detections, with zones if the policy is location-specific;
- set continuous and general motion retention to zero unless broader footage is intentional;
- retain the chosen alert or detection class for 14 days with the required mode;
- set snapshot retention to 14 days if snapshots are part of the policy;
- treat exports as separately governed data because exports are not rolling review-item retention.

Frigate stores one best-frame snapshot per tracked object and can also store a full-resolution clean copy. Disabling the clean copy when Frigate+ is not used reduces unneeded budget use.[^frigate-snapshots]

Regular recording cleanup runs at `record.expire_interval` minutes, with an upstream default of 60. It removes expired review metadata, thumbnails, recording segments, and previews while updating its SQLite records. This application ownership preserves database and file consistency better than external deletion.[^frigate-cleanup]

### Low-space behavior

Frigate samples recent recording bandwidth. Every five minutes it compares the aggregate hourly bandwidth with `shutil.disk_usage(RECORD_DIR).free`. If less than one hour of recording space remains, it deletes the oldest hour of recordings. Emergency deletion ignores configured retention and can delete media younger than 14 days. It updates overlapping event rows to show that clips are gone.[^frigate-storage][^frigate-record]

This mechanism is a safety valve, not a 200 GiB budget control:

- On the current shared root filesystem, it sees root free space, now about 1.6 TiB. It will not act when Frigate itself reaches 200 GiB.
- A user or project quota does not change the filesystem-wide free value that Frigate reads. Frigate can therefore reach its quota first.
- Emergency cleanup deletes recordings. Snapshots, exports, database growth, or other files can still exhaust a Frigate filesystem.
- The check interval leaves a five-minute race. A burst can fill the available space before the next check.
- Slow storage can make the recording maintainer discard old cache segments to avoid a crash, independent of retention.[^frigate-recording-errors]

### Failure behavior

If the shared root fills, unrelated Services can receive `ENOSPC`; non-root Services can be blocked before the root reserve is used. If an ext4 quota is reached, writes receive `EDQUOT` instead.[^write]

Frigate does not document a transaction-level guarantee for `EDQUOT`. Media writes, snapshot writes, and SQLite writes can fail at different points. A hard quota is therefore containment, not graceful degradation. Frigate's native emergency cleanup is graceful only when its filesystem free-space view matches the boundary.

## systemd cleanup

### `systemd-tmpfiles`

`systemd-tmpfiles` can recursively remove directory contents by age. The Host already runs its cleanup timer daily. Its default age test uses file atime, birth time, ctime, and mtime; any recent applicable timestamp prevents deletion. An explicit age selector can narrow this behavior.[^tmpfiles]

This is not a good normal retention owner for Frigate:

- It knows file timestamps and paths, not review labels, zones, alert severity, pre/post capture, or shared recording segments.
- Playback can affect access time, and Frigate writes a UTC date/hour/camera hierarchy. File age is not identical to event policy age.
- Direct deletion can leave Frigate database rows that point to missing media. Frigate offers `record.sync_recordings`, but documents it as an expensive repair for variations, not as the normal deletion mechanism.[^frigate-record]
- Daily execution permits up to about one extra day of age unless a separate timer runs more often.
- Age cleanup has no size cap. A high person-event rate can exceed 200 GiB before 14 days.

### Custom oneshot and timer

A custom systemd Service can calculate directory size and delete oldest files until below a low watermark. It can run more often than `systemd-tmpfiles-clean.timer` and can stop Frigate before work. It still duplicates Frigate's retention model and must update or reconcile SQLite state. A file-only script can also delete one segment used by several tracked objects.

Use a custom Service only as quota-pressure fallback or monitoring. Prefer one that asks Frigate to remove data through a supported interface. If no supported bulk-expiry interface exists, stop Frigate before direct changes and treat the action as emergency recovery, not normal operation.

## ext4 quotas

Linux quotas support per-user, per-group, and per-project soft and hard space and inode limits. A hard limit cannot be exceeded. A soft limit becomes hard after its grace period. `setquota` accepts GiB units and supports project quotas with `-P`.[^quotactl][^setquota]

### User quota

A 200 GiB hard quota on the `frigate` user is simple because the NixOS module already gives the Service a dedicated user. It counts every file owned by that UID on the root filesystem, including `/var/cache/frigate`, not only event media. Root-created or ownership-changed files can escape or distort the intended scope.

It also has the same visibility problem as project quota: Frigate reads filesystem free space and does not see its remaining user allowance. It can hit `EDQUOT` without low-space cleanup.

### Project quota

Project quota is path-tree-oriented and is the better quota type. ext4 manages an inode project ID when the `project` feature is enabled, and the `prjquota` mount option enables support. `chattr -p` sets a project ID, while the `P` attribute makes new descendants inherit the project and constrains cross-project renames and hard links.[^ext4][^chattr]

It can scope `/var/lib/frigate` without charging unrelated files owned by the same UID. The current root is technically compatible because it uses 256-byte inodes, but it does not yet have the required `project` or `quota` features. Enabling them changes the root filesystem and needs a planned maintenance and rollback procedure. No NixOS first-class ext4 project setup option was found; Nix can declare mount options and systemd units, while the live quota initialization remains an explicit operation.[^nix-mcp]

Project quota is the best in-place fallback if a dedicated filesystem is rejected. Set a lower operating soft threshold and a 200 GiB hard limit, monitor quota usage directly, and trigger Frigate-aware cleanup before the hard limit. Do not rely on Frigate's filesystem low-space check.

## Dedicated filesystem options

### Separate disk, partition, or logical volume

A real 200 GiB filesystem gives hard capacity isolation and makes Frigate's `disk_usage(RECORD_DIR)` observe the correct boundary. A separate physical disk also isolates device failure and I/O contention. A partition or logical volume on the same NVMe isolates capacity but not device failure or I/O.

The current NVMe is not under LVM and its root partition occupies almost all usable space. Creating a new partition would require shrinking ext4 while unmounted and then shrinking the partition. `resize2fs` supports shrinking only while unmounted and warns that partition sizing mistakes can lose the filesystem.[^resize2fs] This is not justified for a new NVR when safer alternatives exist.

### Preallocated filesystem image on root

A 200 GiB regular file can be preallocated on root, formatted as ext4, attached through a loop device, and mounted for Frigate state. `fallocate` allocates extents without writing zeroes, and `mount` has direct loop-device support.[^fallocate][^mount]

This has the best fit with current storage:

- The outer preallocation reserves the budget before Frigate starts and prevents later NVR growth from taking unrelated free blocks.
- The inner filesystem is a hard boundary whose free space Frigate can see, so native emergency cleanup starts before inner `ENOSPC`.
- No root partition shrink is needed.
- It isolates capacity failure, but not NVMe hardware failure, root filesystem failure, or I/O contention.
- It adds loop and nested-ext4 operational complexity, a second journal, filesystem overhead, and a second filesystem to check and monitor.

Mount the image for all `/var/lib/frigate` state if the operating budget includes the database, clips, exports, and recordings. Ensure the mount is required before `frigate.service`; if it is unavailable, Frigate must remain stopped. Otherwise `StateDirectory=frigate` can expose the underlying root directory and silently bypass the budget. Do not use a permissive `nofail` path for this mount.[^nixpkgs-module]

Set inner ext4 reserved blocks deliberately. A media-only filesystem does not need the root filesystem's normal 5 percent privileged reserve. Keep enough free-space margin for SQLite and snapshots, and alert well before Frigate's one-hour emergency threshold.

## Comparison

| Control | 14-day person semantics | Hard 200 GiB boundary | Frigate sees pressure | Database consistency | Protects unrelated Services | Main failure |
| --- | --- | --- | --- | --- | --- | --- |
| Frigate retention on shared root | Yes | No | Only root-wide pressure | Best | No | Shared root can fill |
| `systemd-tmpfiles` age cleanup | No | No | No | Poor | No | Deletes files behind Frigate |
| Custom systemd size cleanup | Partial, if reimplemented | Soft only | External | Risky | Partial | Race or model drift |
| ext4 user quota | Yes, with Frigate | Yes | No | `EDQUOT` risk | Yes | Counts all files for UID |
| ext4 project quota | Yes, with Frigate | Yes | No | `EDQUOT` risk | Yes | Needs quota-aware pressure action |
| Same-NVMe fixed filesystem | Yes, with Frigate | Yes | Yes | Best under normal cleanup | Yes | Inner FS fills or mount is absent |
| Separate physical filesystem | Yes, with Frigate | Yes | Yes | Best | Yes | NVR stops; other Services continue |

## Recommended failure policy for issue #23

1. Fail closed when the Frigate filesystem is absent. Do not start the Service on the underlying root path.
2. Let Frigate expire 14-day person review media in normal operation.
3. Alert on projected 14-day size and filesystem use before emergency cleanup. Measure actual GiB/day after deployment because event rate, bitrate, capture windows, and snapshots determine capacity.
4. At pressure, delete the oldest recordings through Frigate even if younger than 14 days. This keeps the 200 GiB safety boundary and unrelated Services healthy. Record the reduced retention as a degraded state.
5. If strict 14-day retention must win, reject new recordings at the boundary or increase storage. No cleanup mechanism can satisfy both limits when demand exceeds capacity.
6. Keep exports outside rolling retention or give them a separate explicit limit. Otherwise manual exports can consume the event budget and Frigate's emergency cleanup will not remove them.
7. Test three failures before production: missing mount at boot, filled inner filesystem, and an event burst that exceeds the measured daily allowance. Verify that only Frigate degrades and that root free space remains stable.

## Sources

[^repo-hardware]: Repository [`hosts/homelab/hardware-configuration.nix`](../../hosts/homelab/hardware-configuration.nix), root filesystem declaration.
[^frigate-review]: Frigate, [Review](https://docs.frigate.video/configuration/review), current 2026 documentation.
[^frigate-record]: Frigate, [Recording](https://docs.frigate.video/configuration/record), current 2026 documentation.
[^frigate-snapshots]: Frigate, [Snapshots](https://docs.frigate.video/configuration/snapshots), current 2026 documentation.
[^frigate-cleanup]: Frigate source, [`frigate/record/cleanup.py`](https://github.com/blakeblackshear/frigate/blob/dev/frigate/record/cleanup.py), accessed 2026-08-23.
[^frigate-storage]: Frigate source, [`frigate/storage.py`](https://github.com/blakeblackshear/frigate/blob/dev/frigate/storage.py), accessed 2026-08-23.
[^frigate-recording-errors]: Frigate, [Recording errors](https://docs.frigate.video/troubleshooting/recordings), current 2026 documentation.
[^nixpkgs-package]: Nixpkgs, [`pkgs/by-name/fr/frigate/package.nix`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/fr/frigate/package.nix), native path substitutions.
[^nixpkgs-module]: Nixpkgs, [`nixos/modules/services/video/frigate.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/video/frigate.nix), native Service user and directories.
[^nix-mcp]: Live nix-mcp queries on 2026-08-23: nixpkgs unstable `frigate` 0.17.2; `services.frigate.*`; `systemd.tmpfiles.*`; `quota` 4.11.
[^tmpfiles]: systemd, [`tmpfiles.d(5)`](https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html), current manual.
[^ext4]: e2fsprogs 1.47.4, [`ext4(5)`](https://man7.org/linux/man-pages/man5/ext4.5.html), project/quota features and mount options, rendered 2026-05-30.
[^tune2fs]: e2fsprogs 1.47.4, [`tune2fs(8)`](https://man7.org/linux/man-pages/man8/tune2fs.8.html), quota features and reserved blocks, rendered 2026-05-30.
[^quotactl]: Linux man-pages 6.18, [`quotactl(2)`](https://man7.org/linux/man-pages/man2/quotactl.2.html), quota types and limits, 2026-04-19.
[^setquota]: quota-tools, [`setquota(8)`](https://man7.org/linux/man-pages/man8/setquota.8.html), project and GiB limit syntax, rendered 2026-05-30.
[^chattr]: e2fsprogs 1.47.4, [`chattr(1)`](https://man7.org/linux/man-pages/man1/chattr.1.html), project ID and inheritance, rendered 2026-05-30.
[^write]: Linux man-pages 6.18, [`write(2)`](https://man7.org/linux/man-pages/man2/write.2.html), `EDQUOT`, `ENOSPC`, and partial writes, 2026-02-08.
[^resize2fs]: e2fsprogs 1.47.4, [`resize2fs(8)`](https://man7.org/linux/man-pages/man8/resize2fs.8.html), offline shrink and partition warning, rendered 2026-05-30.
[^fallocate]: util-linux, [`fallocate(1)`](https://man7.org/linux/man-pages/man1/fallocate.1.html), preallocation, source snapshot 2026-05-24.
[^mount]: util-linux, [`mount(8)`](https://man7.org/linux/man-pages/man8/mount.8.html), filesystem and loop-device mounts, source snapshot 2026-05-24.
