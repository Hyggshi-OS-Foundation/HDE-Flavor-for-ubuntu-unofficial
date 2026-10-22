# NexWM OS — unofficial Ubuntu flavor built around HDE (NexWM)

A reproducible, CI-only Ubuntu flavor: a desktop distribution based on
Ubuntu LTS whose entire user experience is [HDE — the Hyggshi Desktop
Environment](https://github.com/Hyggshi-OS-Research-Technology/NexWM)
(panel, Start menu, Hyggshi Files, Hyggshi Settings, HDE lock screen) with
**NexWM**, HDE's own window manager, as the default session, and SDDM with
HDE's own login theme on top.

## What this repository produces

A single hybrid live/installer ISO per build, `nexwm-os-<ubuntu-version>-desktop-amd64.iso`:

* boots on BIOS and on UEFI (and from USB in both cases),
* boots into a live desktop with automatic login (casper user, the HDE
  session started through SDDM and `nexwm`),
* ships the **Calamares** installer ("Install NexWM OS") wired with the
  flavor's own settings and branding,
* contains **no GNOME and no snapd**: the base system is debootstrapped
  from the Ubuntu archive and any GNOME seed leftovers are purged
  (`config/packages/gnome-purge.list`), so the flavor pays for the desktop
  it actually ships.

## The pipeline (GitHub Actions only)

Everything runs on hosted `ubuntu-24.04` runners —
[`.github/workflows/build-iso.yml`](.github/workflows/build-iso.yml):

1. **Base** — `debootstrap` the base suite from `archive.ubuntu.com`
   (`config/flavor.conf`: newest stable LTS by default, overridable with a
   workflow input). This replaces the "download the Ubuntu ISO and peel
   GNOME out" shortcut with a cleaner equivalent: the flavor builds from the
   same per-suite archive seeds official images use, and *never installs a
   GNOME layer to remove in the first place*. The GNOME purge stage
   (`scripts/stages/25-remove-gnome.sh`) is still there as a hard guarantee.
2. **Desktop** — the pinned **NexWM/HDE** checkout is cloned with its commit
   recorded for provenance, copied into the chroot, and built by HDE's own
   in-chroot builder (`packaging/hyggshi-os/build-nexwm.sh` of that
   repository): build deps, `make`, `make check-full`, installs to `/usr`,
   keeps runtime libraries, removes build tools. The SDDM login theme from
   `login/sddm` is installed as well.
3. **Flavor layer** — `os-release`, issue text, casper live configuration,
   per-boot SDDM autologin, Yaru themes, fonts, PipeWire, NetworkManager,
   udisks2, gnome-keyring and the flavor's live smoke-check units.
4. **Installer** — Calamares plus the settings, branding, slideshow and
   launcher from `config/calamares/` and `config/usr/`, modeled on the
   settings Ubuntu flavors ship in `calamares-settings-ubuntu`.
5. **Live medium** — the rootfs becomes `casper/filesystem.squashfs`
   (zstd) with `filesystem.{manifest,size}` and `md5sum.txt`.
6. **ISO** — one hybrid medium with `xorriso`: isolinux + isohybrid MBR for
   BIOS/USB, a standalone GRUB x86_64-efi image in a FAT ESP for UEFI/USB.
7. **Preflight** — `scripts/stages/90-report.sh` verifies the structure,
   the casper metadata, presence of HDE and Calamares inside the squashfs
   and the sha256 sidecar.
8. **QEMU smoke** — BIOS *and* UEFI boots under QEMU (KVM when the runner
   provides `/dev/kvm`, TCG otherwise). The ISO's own
   `nexwm-os-live-check` unit reports `NEXWMOS_SMOKE_OK` on the serial
   console once the live desktop is genuinely up, then powers the machine
   off. `test/qemu-smoke.sh` greps the firmware path's serial log for the
   marker; logs are always uploaded as artifacts.

Build stages, each reviewable in its own file under `scripts/stages/`:

| Stage                          | Where     | What |
| ------------------------------ | --------- | ---- |
| `10-bootstrap-rootfs.sh`       | host      | debootstrap the base suite |
| `20-install-base.sh`           | chroot    | base packages, kernel, casper initramfs, graphical target |
| `25-remove-gnome.sh`           | chroot    | purge any GNOME layer |
| `30-build-de.sh`               | chroot    | build + install HDE (repository's own builder) |
| `35-sddm-login.sh`             | chroot    | HDE SDDM login theme |
| `40-branding.sh`               | chroot    | os-release, casper.conf, live units, SDDM defaults |
| `50-installer.sh`              | chroot    | Calamares + flavor settings + branding + launcher |
| `60-cleanup-rootfs.sh`         | chroot    | hygiene before squashing |
| `70-squashfs.sh`               | host      | casper/filesystem.squashfs + metadata |
| `80-iso.sh`                    | host      | isolinux, GRUB ESP, xorriso, checksums |
| `90-report.sh`                 | host      | preflight checks |

`build.sh` runs the same pipeline locally **for maintainers only**; the
project rule is that ISOs are *never* produced on a developer machine —
GitHub Actions is the single build authority.

## Running it yourself (CI)

Push to `main`, dispatch the workflow, or tag with `v*` (a tag run publishes
the ISO as a GitHub release once QEMU smoke passes). Workflow inputs:

* `base-suite` — pin a codename (`noble`, ...) instead of the config default;
* `hde-ref` — build a branch/tag of NexWM instead of `main`;
* `skip-qemu` — skip the firmware smoke tests (discouraged).

Artifacts per run: the ISO + sha256, full stage logs, the `hde-provenance`
commit record, and serial console logs from both QEMU boots.

## Configuration surface

| Path | Purpose |
| ---- | ------- |
| `config/flavor.conf` | flavor identity, HDE repo/ref, base suite policy, live user |
| `config/os-release`  | `/etc/os-release` template (`__VERSION__`/`__CODENAME__` filled at build time) |
| `config/packages/`   | apt lists: base set, GNOME purge list, installer set |
| `config/calamares/`  | Calamares `settings.conf`, module configs, branding + slideshow |
| `config/systemd/`    | live-only units (per-boot SDDM autologin, desktop smoke check) |
| `config/usr/`        | live helper scripts and the installer `.desktop` entry |

## On becoming an official Ubuntu flavor

Ubuntu's flavor process expects (see `docs/FLAVOR-CHECKLIST.md` for the
full list): a buildable and installable ISO at release cadence, tracking
each Ubuntu release, coordination with Ubuntu Central (application through
the Community Council / flavor governance), no unlicensed use of the Ubuntu
trademark in the *product name*, and adoption of the Ubuntu installer
expectations. This repository is engineered for exactly those obligations:

* weekly CI runs keep the ISO buildable against the base archive,
* the base suite defaults to **newest stable LTS**, matching the flavor
  release cadence, and can be pinned per build,
* the name is the project's own (`NexWM OS`); `os-release` marks itself as
  `ID_LIKE debian ubuntu` and about text as *based on Ubuntu*, without
  claiming to be Ubuntu,
* the QEMU smoke tests prove — on every run — that both firmware paths boot
  to the desktop, and the installer is Calamares configured in-repo.

## Repository layout

```
build.sh                 local orchestrator (maintainer use; CI is the authority)
config/                  flavor definition (identity, packages, calamares, systemd, os-release)
scripts/stages/          the reviewable build stages
scripts/common.sh        shared helpers
tools/                   host dependency installer
test/qemu-smoke.sh       firmware boot smoke tests (BIOS + UEFI)
.github/workflows/       the CI pipeline
docs/FLAVOR-CHECKLIST.md official-flavor evaluation checklist
```

## License

GPL-3.0, matching the third-party flavor guidelines for remix tooling; the
HDE desktop itself carries its own MIT license upstream.
