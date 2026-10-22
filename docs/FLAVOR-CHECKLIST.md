# Official Ubuntu flavor evaluation checklist

Use this to prepare an application and keep the project compliant. Sources:
Ubuntu's flavor program pages and the requirements historical flavors were
held to (see ubuntu.com/desktop/flavours and the Community Council process).

## Product requirements

- [ ] **ISO buildable from source, reproducibly, on release cadence.**
      This repo: one CI workflow produces the whole ISO; weekly scheduled
      builds prove the pipeline against the moving base archive.
- [ ] **ISO installs on BIOS and UEFI.** QEMU smoke tests cover both
      firmware paths on every run; the installer is Calamares configured
      in this repository (settings + branding + module sequence).
- [ ] **Tracks Ubuntu releases.** Base suite defaults to the newest stable
      LTS (`config/flavor.conf`), pinned per build via workflow input; the
      release tags follow Ubuntu's. Keep `UBUNTU_LTS_SUITES` current.
- [ ] **Secure Boot.** Current medium boots UEFI without Secure Boot;
      follow-ups: shim-signed chain in `efi.img` and SBAT metadata.
      (Tracked: the signed packages are already part of the target system's
      package set for the installed side.)
- [ ] **Kernel/initramfs freshness.** casper initramfs regenerated at build
      time from the installed kernel; verify after each base bump.
- [ ] **No unofficial mirrors/mods of Ubuntu's brand.** The name is the
      project's own; "based on Ubuntu" statements must be accurate in
      branding and os-release (they are: `ID_LIKE`, `UBUNTU_CODENAME`).
- [ ] **Trademark review.** Applying for flavor status requires Canonical
      approval to use the trademark; until then keep the unaffiliated
      positioning above everywhere user-visible.
- [ ] **Release Team coordination.** On acceptance, align ISO publication
      dates with Ubuntu's; CI already keeps the medium buildable weekly.

## Quality requirements

- [ ] Live session autologins (casper + SDDM) and reaches the desktop: covered by the QEMU smoke marker.
- [ ] Installer completes an install to disk end-to-end: automated UI-driven Calamares coverage is still TODO (manual verification until then).
- [ ] package list is curated (`config/packages/`), no GNOME leftovers (purge list + nobody-installs-GNOME base).
- [ ] `os-release`, lsb-release, issue text are flavor-correct.
- [ ] The DE is built from a pinned upstream commit; provenance file ships with every build.

## CI surfaces that must stay green

- [ ] build job: debootstrap, package installs, HDE `make check-full`, squashfs, xorriso.
- [ ] preflight (`90-report.sh`): medium structure, casper metadata, HDE + installer presence inside the squashfs.
- [ ] `qemu-smoke` (BIOS) and `qemu-smoke` (UEFI).
- [ ] logs uploaded on every run (stage logs, hde provenance, serial logs).
