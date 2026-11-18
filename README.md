# Debian 13 for the 12-inch Retina MacBook (MacBook8,1)

[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
![Base: Debian 13 (trixie)](https://img.shields.io/badge/base-Debian%2013%20trixie-A80030)
![Boot verified: QEMU EFI](https://img.shields.io/badge/boot%20verified-QEMU%20EFI-success)

A reproducible **Debian 13 (trixie) live + installer ISO** for the early-2015 12-inch
Retina MacBook (A1534, `MacBook8,1`). The internal keyboard and trackpad work from the
very first GRUB menu — not after a fix — and Broadcom Wi-Fi firmware, a Swedish keyboard
fix, four desktop environments and a guided hardware-setup menu are baked in.

Built and maintained by **[LAPS AB](https://laps.se)**.

---

## The problems this solves

The MacBook8,1 is a beautiful machine with four specific problems on Linux:

| Problem | Symptom | What this ISO does |
|---|---|---|
| Apple SPI keyboard/trackpad | Dead keyboard at boot; GRUB and the installer are unusable | `initcall_blacklist=dw_pci_driver_init` in **every** boot path: live, graphical installer, text installer, and the installed system's GRUB (via preseed) |
| Broadcom Wi-Fi | No network after install | `firmware-brcm80211` in the package list and in the installer image |
| Swedish §/<> keys | Wrong characters on the two keys next to left Shift | `xorg.conf.d` layout + an `Xsession.d` keymap fix for all X11 logins |
| Audio, webcam, suspend | Work only with kernel patches and firmware extraction | Not forced into the ISO: a gated menu (`laps-macbook-setup`) runs the verified, reversible scripts on the installed machine |

## What you get

| Component | Detail |
|---|---|
| Desktops | Cinnamon, XFCE, KDE Plasma, Sway (Wayland) — choose at the login screen |
| Display manager | SDDM, configured for both X11 and Wayland sessions |
| Live system | Full desktop, Wi-Fi, Swedish keyboard, SPI fix active |
| Installer | Graphical and text preseeded Debian installer, SPI fix in the installed GRUB |
| Baked in | This project's companion guide repo at `/opt/macbook8-1-debian-guide`, plus `/usr/local/bin/laps-macbook-setup` |
| Boot media | USB-hybrid ISO: MBR + GPT + APM, flashable with `dd` or balenaEtcher, boots on Apple EFI |

## Requirements

- An x86_64 Linux host (built and verified on Debian/Ubuntu with `live-build` from apt).
  macOS and Windows hosts are **not** supported for building.
- `sudo` (live-build needs root to chroot and loop-mount).
- **~25 GB free disk** (the build tree peaks around 19 GB), 4 GB RAM, ~40 minutes.
- These packages:

```bash
sudo apt install live-build debootstrap xorriso grub-efi-amd64-bin grub-common \
                 mtools squashfs-tools p7zip-full
```

`tools/setup-host-deps.sh` (also `make deps`) checks all of the above and tells you what
is missing. The build was verified with `live-build 3.0~a57-1ubuntu54`; a different
version may need the three patch scripts adjusted — they verify themselves and refuse to
run blindly, so a mismatch fails loudly instead of producing a broken ISO.

## Quick start

```bash
git clone https://github.com/pmgart/laps-macbook-iso.git
cd laps-macbook-iso

make deps     # verify tools, live-build version, MBR blob
make build    # full build, ~40 min, runs detached; .build-done appears on success
make efi      # MANDATORY: add the EFI boot (see "Why an extra step")
make verify   # checklist: GRUB params, squashfs contents, EFI files
```

The finished image is `laps-macbook-debian-trixie.iso` in the repo root. The scripts
resolve their own location, so the directory can be named anything — no hardcoded paths.

Optional: `make qemu` boots the ISO in QEMU with OVMF for ~150 s and reports how much of
the CD was read — a cheap proof that the boot chain works before you touch real hardware.

## Why an extra EFI step exists

`live-build 3.0~a57` accepts `LB_BOOTLOADER=grub-efi`, but `lb binary` still writes a
`binary.hybrid.iso` **without a bootloader**. The MacBook8,1 has no BIOS, so such an ISO
is an unbootable brick.

`add-efi-boot.py` adds the EFI path afterwards, copying the recipe Debian uses for its own
live images: a `grub-mkimage` ELF inside an 8 MB FAT `efi.img`, published as an El Torito
entry, with `isohybrid-gpt-basdat` and an MBR blob so the same file also works as a USB
stick. It also fixes a subtle failure mode: kernel and initrd must be placed **before** the
2.4 GB squashfs on the disc, or OVMF gives up with *"failure reading sector"*.

## Pipeline

| Stage | Command | Result |
|---|---|---|
| 1. Patch live-build | `fix-livebuild-*.sh` | Three trixie-specific fixes to `/usr/lib/live/build` (idempotent, self-verifying) |
| 2. Configure | `config/` | Package lists, hooks, preseed, EFI/GRUB settings |
| 3. Bootstrap + chroot + binary | `sudo lb build` | `chroot/binary.hybrid.iso` (~2.6 GB, no bootloader) |
| 4. EFI + hybridise | `add-efi-boot.py` | `laps-macbook-debian-trixie.iso` (~3.0 GB) |
| 5. Verify | `verify-iso.sh` | 8 checks against the built image |
| 6. Boot test | `qemu-test-laps-iso.sh` | CD-read telemetry proving kernel + squashfs load |

`resume-binary.sh` re-enters at stage 3 if the chroot still exists (~10 min instead of 40).

## Verified build

The exact image this repo produced is recorded in [MANIFEST.md](MANIFEST.md), including
package lists (2 840 packages), kernel version, squashfs and EFI image sizes, and the
checksum:

```
1351d6c95e7a0bd869cb2062662d8c4b59a20b954f55bbd88e2213428ead44e6  laps-macbook-debian-trixie.iso
3 033 710 592 bytes
```

Verify any copy with `sha256sum -c` against the `.sha256` file, or just `make verify`.

**Honest status:** the image boots correctly under QEMU/OVMF with the SPI parameter on the
kernel command line, and its squashfs contents have been verified. As of the last update it
has **not** been booted on a physical MacBook8,1, and no full install on the real machine
has been performed. Treat the first real-hardware run as a test, and keep a second boot
method available.

## Writing the ISO to USB

```bash
# identify the stick carefully — this erases it
lsblk
sudo dd if=laps-macbook-debian-trixie.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

balenaEtcher works too. On the MacBook: power on while holding **Option (⌥)**, pick
*EFI Boot*. If the internal keyboard is dead in the picker (possible on some units before
the SPI fix), use a USB keyboard for that one step.

## After installation

```bash
sudo laps-macbook-setup
```

A menu for the three fixes that must run on the real machine: internal speakers (patched
CS4208 driver), FaceTime HD webcam (firmware 5.60.0), and suspend-then-hibernate. Every
step is gated, logs what it does, and has a `restore-*` counterpart. The full documentation
lives on the installed system at `/opt/macbook8-1-debian-guide`.

## Maintaining and rebuilding later

- **Kernel versions are auto-detected** from the built ISO, so a rebuild with a newer
  trixie kernel does not need manual menu editing (`--kernel` overrides it).
- **The patch scripts are idempotent** and back up the files they touch.
- **`make clean`** removes `chroot/` and `cache/` (19 GB) and leaves the ISO untouched.
- **Not bit-reproducible:** the mirrors are not pinned to a snapshot, so a rebuild today
  produces a different image. Pin `snapshot.debian.org` in `config/archives` if you need
  that. The verified binary is the artefact — archive it.

## Troubleshooting

The ten failures that actually happen, with causes and fixes:
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). The most common ones:

| Symptom | Cause | Fix |
|---|---|---|
| `live-build locked` | Stale `.lock` from a killed build | `sudo lb clean --purge`, or `resume-binary.sh` which cleans it |
| ❌ VERIFIERING MISSLYCKADES | live-build version changed, patch did not match | Read the script's message; compare with `3.0~a57-1ubuntu54` |
| Build freezes, apt lock holds | Build was suspended with `Ctrl+Z` | Never suspend; the scripts run detached for this reason |
| Black screen after EFI boot | Missing `unicode.pf2`, or empty memdisk | `add-efi-boot.py` handles both — verify with `make verify` |
| `failure reading sector` in OVMF | Kernel placed after the squashfs | Use this repo's `add-efi-boot.py` path list unchanged |

## Security and privacy

- No credentials, keys or tokens anywhere in this repo or in the produced image.
- No telemetry, no phone-home. The only network traffic is `apt`/`wget` fetching Debian
  packages and the installer's `Contents` indexes during the build.
- The preseed file sets no passwords and creates no users — the installer asks you.
- Found a security-relevant issue? Mail **pablo@laps.se** rather than opening a public issue.

## Repository layout

```
config/                live-build configuration (package lists, hooks, preseed, includes)
manifests/             package lists and measurements from the verified build
tools/                 isohdpfx.bin (MBR blob) + host dependency check
tests/                 unit tests for the kernel/blob logic (run in CI)
docs/                  troubleshooting + original Swedish build notes
legacy/                superseded scripts, kept for reference (not used by the build)
add-efi-boot.py        the EFI/hybrid step
build-laps-debian.sh   orchestrates patches + full build
resume-binary.sh       re-enter at the binary stage
verify-iso.sh          checklist verification
qemu-test-laps-iso.sh  QEMU EFI boot smoke test
```

## License

[GPL-3.0-or-later](LICENSE). `config/` is derived from live-build's configuration templates
(GPL-3+), so the repository uses the same licence. The frozen copy of the companion guide in
`config/includes.chroot/opt/macbook8-1-debian-guide/` is by the same author and carries the
same terms.

## Credits

Standing on Debian's work: [live-build](https://salsa.debian.org/live-team/live-build), GRUB,
xorriso, mtools and the Debian installer. The hardware fixes are documented step by step in
[`pmgart/macbook8-1-debian-guide`](https://github.com/pmgart/macbook8-1-debian-guide) —
Wi-Fi, SPI input, CS4208 speakers, FaceTime HD camera and suspend-then-hibernate, each with
diagnostics and a restore path.

## About LAPS AB

This ISO is maintained by **[LAPS AB](https://laps.se)**, a Swedish B2B agency in Malmö.
We build Webflow sites, SEO and content programmes, paid advertising, technical web
implementations and AI/automation for B2B companies. The MacBook fixes exist because we
run our own hardware on Debian and refuse to keep a machine that only boots half the time.

If your company needs a website that converts, an SEO programme that compounds, or
automation that removes manual work — that is what we do at **[laps.se](https://laps.se)**.

**No warranty.** This is a hardware-specific hobby-grade build system, published because
the fixes are worth sharing. Booting an unsupported Apple machine always carries risk; you
are responsible for your own data and your own recovery path.
