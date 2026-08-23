# Event-Retention Storage Guardrails

Research date: 2026-08-23

Issue: [#19, Research event-retention storage guardrails](https://github.com/fveracoechea/homelab/issues/19)

## Purpose

This research compares four controls for a future Frigate Service on the homelab Host. It does not select an enforcement policy. Issue [#23](https://github.com/fveracoechea/homelab/issues/23) owns that decision.

Frigate calls an interval with tracked objects a **review item**. It classifies review items as alerts or detections. This report uses "person-event" only as the ticket term; Frigate terms are used when source behavior depends on them.[^frigate-review]

## Non-negotiable limit

A 200 GiB operating budget has a **14.29 GiB/day threshold** (200 / 14 = 14.2857 GiB/day, rounded). At 14.29 GiB/day and above, 14 days conflicts with 200 GiB. No cleanup or storage control can guarantee both: the system must either remove data younger than 14 days, refuse or lose new data, or use more than 200 GiB.

The measurement must include every data class inside the budget, such as recordings, snapshots, previews, exports, and the SQLite database. The configuration must state which classes are in scope.

## Guarantee types

- **Age guarantee:** qualifying media is retained for at least 14 days.
- **Capacity guarantee:** the Service cannot consume more than 200 GiB of the guarded storage resource.
- **Availability guarantee:** Frigate storage use cannot exhaust space needed by unrelated Services. This does not guarantee that Frigate can continue recording.

## Comparison

| Control | Age guarantee | Capacity guarantee | Availability guarantee | Important limit |
| --- | --- | --- | --- | --- |
| Frigate NVR cleanup | Normal cleanup can apply configured retention to Frigate-managed recordings and review data. | No fixed 200 GiB limit on a shared filesystem. Its emergency cleanup is capacity-responsive only to filesystem free space. | No on a shared root filesystem. | Emergency cleanup can delete recordings younger than configured retention. |
| Fixed-size filesystem | No. | Yes, bounded by the filesystem's allocatable blocks. | Yes for data on other filesystems. | Frigate can still fill its own filesystem and receive `ENOSPC`. |
| ext4 quota | No. | Yes for the charged UID, GID, or project when a hard limit is set. | Yes for quota subjects outside that limit on the same filesystem. | Frigate reads filesystem free space, not its remaining quota, and can receive `EDQUOT` before its own low-space cleanup starts. |
| systemd cleanup | Best-effort file-age cleanup only. | No. | No direct guarantee. | It does not understand Frigate review semantics or capacity, and external deletion can leave Frigate metadata stale. |

## Frigate v0.17.2 NVR cleanup

The NixOS unstable package index reports Frigate version 0.17.2.[^nix-mcp] The following claims are pinned to the Frigate `v0.17.2` tag, not current documentation or the development branch.

Frigate recording retention uses configured day cutoffs. The applicable retention is the largest matching recording or tracked-object retention, and its default expiration interval is 60 minutes.[^frigate-record-config][^frigate-record-docs][^frigate-cleanup]

This can provide normal **age** handling when labels, alert or detection classes, retention modes, and other recording retention settings match the intended person policy. It is not an unconditional 14-day age guarantee. The low-storage path estimates the recording rate and, when less than one hour remains, deletes the oldest hour of recordings regardless of retention settings.[^frigate-record-docs] A full filesystem can therefore cause deletion before day 14.

The low-storage check uses free space returned for Frigate's recordings directory. On a shared root filesystem, this is root filesystem free space, not Frigate directory use or a quota remainder. It does not create a 200 GiB **capacity** or unrelated-Service **availability** guarantee.[^frigate-storage]

Frigate manages its own recording files and database updates during normal cleanup. Direct external file deletion does not have that consistency property. Frigate v0.17.2 also has a retention edge case: with `continuous.days: 0`, cleanup can select no-motion/no-audio segments without the review-age condition that protects reviews. A recent review item can therefore lose a pre- or post-capture segment even with alert or detection retention configured.[^frigate-cleanup]

## Fixed-size ext4 filesystem

An ext4 filesystem records a total block count and free block count. Its formatted capacity, metadata, and reserved blocks bound the allocatable space. It does not delete files when full; allocation eventually fails.[^ext4-super]

A dedicated 200 GiB filesystem therefore provides a **capacity** boundary for data placed on it. If it is a separate mount from the root filesystem, it also provides an **availability** boundary for unrelated Services because Frigate cannot allocate its blocks from their filesystem. This control has no **age** policy. It also does not protect Frigate recording continuity: Frigate can consume its own free blocks, and its low-storage cleanup can reduce retention before `ENOSPC`.

The backing can be a separate device, partition, logical volume, or a preallocated filesystem image. These forms differ in device-failure and I/O isolation, but not in the three guarantees above. A mount failure must not silently expose an unguarded directory on the root filesystem if the 200 GiB boundary is required.

## ext4 quota

The Linux quota subsystem limits blocks and inodes per user, group, or project on a filesystem. A hard limit cannot be exceeded except by a process with `CAP_SYS_RESOURCE`; a soft limit allows temporary excess until its grace period expires.[^quota]

This gives a **capacity** guarantee for the charged subject. It gives an **availability** guarantee to other subjects on that filesystem, subject to privileged bypasses and correct ownership or project assignment. It provides no **age** guarantee. At the hard boundary writes can fail with `EDQUOT`; quota containment is not a graceful cleanup or recording-availability guarantee.[^quota]

For a directory tree, ext4 project IDs and `EXT4_PROJINHERIT_FL` are the relevant mechanisms. New descendants inherit the project ID when the directory has the project-inheritance attribute. Cross-project rename and hard-link restrictions help preserve the tree boundary.[^ext4-inodes][^chattr]

Neither user nor project quota changes the filesystem-wide free-space value that Frigate reads. Frigate can reach its quota without entering its own low-space deletion path. The NixOS facts in this report are limited to declarative tmpfiles support and the available Frigate package version; quota enablement and initialization need separate implementation validation.[^nix-mcp]

## systemd cleanup

NixOS exposes `systemd.tmpfiles.settings` to declare systemd-tmpfiles rules, including cleanup rules.[^nixos-tmpfiles] Upstream `systemd-tmpfiles --clean` removes files by age according to tmpfiles rules. The standard cleanup timer starts 15 minutes after boot and then daily.[^tmpfiles-man][^tmpfiles-timer]

This is a best-effort **age** mechanism for file paths. It is not a Frigate person-review age guarantee: it knows paths and timestamps, not review labels, capture overlap, or shared recording segments. Aging tests use file timestamps, and an existing BSD file lock causes a path subtree to be skipped.[^tmpfiles-man]

Tmpfiles provides neither a 200 GiB **capacity** guarantee nor an **availability** guarantee. Deleting Frigate files outside Frigate can leave database records for missing media. A custom systemd service can add a size calculation, but it would still need to define deletion semantics and coordinate with Frigate; it is a distinct policy choice for issue #23, not a property of systemd cleanup.

## Decision gates for issue #23

1. Define the budget scope: recordings only, or all Frigate state including snapshots, previews, exports, and SQLite data.
2. Choose the behavior above 14.29 GiB/day: reduce age retention, reject or lose new data, or increase capacity.
3. Choose the capacity boundary: fixed-size filesystem, ext4 quota, or no independent boundary.
4. Define failure behavior for a missing or full guarded mount, quota exhaustion, and Frigate emergency deletion.
5. Define whether any external cleanup may delete Frigate-managed files and how database consistency is recovered.

## Sources

[^frigate-review]: Frigate `v0.17.2`, [Review configuration](https://raw.githubusercontent.com/blakeblackshear/frigate/v0.17.2/docs/docs/configuration/review.md).
[^frigate-record-config]: Frigate `v0.17.2`, [`frigate/config/camera/record.py`](https://raw.githubusercontent.com/blakeblackshear/frigate/v0.17.2/frigate/config/camera/record.py).
[^frigate-record-docs]: Frigate `v0.17.2`, [Recording configuration](https://raw.githubusercontent.com/blakeblackshear/frigate/v0.17.2/docs/docs/configuration/record.md).
[^frigate-cleanup]: Frigate `v0.17.2`, [`frigate/record/cleanup.py`](https://raw.githubusercontent.com/blakeblackshear/frigate/v0.17.2/frigate/record/cleanup.py).
[^frigate-storage]: Frigate `v0.17.2`, [`frigate/storage.py`](https://raw.githubusercontent.com/blakeblackshear/frigate/v0.17.2/frigate/storage.py).
[^ext4-super]: Linux kernel documentation, [The ext4 super block](https://docs.kernel.org/filesystems/ext4/super.html).
[^quota]: Linux kernel documentation, [The quota subsystem](https://docs.kernel.org/filesystems/quota.html).
[^ext4-inodes]: Linux kernel documentation, [The ext4 inode structure](https://docs.kernel.org/filesystems/ext4/inodes.html).
[^chattr]: e2fsprogs upstream, [`chattr(1)` source](https://raw.githubusercontent.com/tytso/e2fsprogs/master/misc/chattr.1.in).
[^nixos-tmpfiles]: NixOS option documentation, [`systemd.tmpfiles.settings`](https://search.nixos.org/options?query=systemd.tmpfiles.settings).
[^tmpfiles-man]: systemd upstream, [`tmpfiles.d(5)`](https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html).
[^tmpfiles-timer]: systemd upstream, [`systemd-tmpfiles-clean.timer`](https://raw.githubusercontent.com/systemd/systemd/main/units/systemd-tmpfiles-clean.timer).
[^nix-mcp]: nix-mcp queries on 2026-08-23: nixpkgs unstable `frigate` is 0.17.2; NixOS `systemd.tmpfiles.settings` declares tmpfiles rules.
