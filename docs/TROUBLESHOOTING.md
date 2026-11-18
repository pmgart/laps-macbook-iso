# Troubleshooting

Every entry here is a failure that actually occurred while producing the verified image.
Symptoms first, then cause, then fix.

---

## 1. `live-build locked` / build refuses to start

**Symptom:** `lb binary` or `lb build` exits immediately with *"live-build locked"*.

**Cause:** a leftover `.lock` in the build directory, usually after a build was killed or
suspended mid-run. A suspended (`Ctrl+Z`) `sudo lb ...` also keeps the apt locks inside
`chroot/`.

**Fix:**

```bash
sudo lb clean --purge      # also unmounts chroot branches properly
# or, keeping the chroot for a binary-stage resume:
bash resume-binary.sh      # removes .lock and stale dpkg locks first
```

Never `rm -rf chroot` while it has active mounts — check first:
`grep "$PWD" /proc/mounts`.

---

## 2. `❌ VERIFIERING MISSLYCKADES: patchen finns inte i live-build`

**Symptom:** `build-laps-debian.sh` stops before building.

**Cause:** one of the three `fix-livebuild-*.sh` patches did not apply, because the
installed `live-build` is not the version this was verified against
(`3.0~a57-1ubuntu54`). The patch scripts are `sed`/`python` replacements against
`/usr/lib/live/build/*` and they check their own result rather than assuming success.

**Fix:** check `dpkg -l live-build`. If the version differs, read the patch script and the
actual file, adapt the search string, then re-run. Do not bypass the verification — an
unpatched `lb` produces an ISO that fails much later and less clearly.

---

## 3. `404` fetching `Contents-amd64.gz`

**Symptom:** the build stops in `lb_binary_debian-installer` with a failed `wget`.

**Cause:** since trixie, `Contents-<arch>.gz` lives per archive component
(`dists/trixie/main/…`) instead of at `dists/trixie/…`. The old flat URL is gone.

**Fix:** `sudo bash fix-livebuild-contents.sh` (patch 1). It fetches from each component and
verifies the block was replaced.

---

## 4. `grub-pc` / `grub-efi-amd64` conflict, or `lilo`/`linux-image-2.6-*` not found

**Symptom:** dep resolution fails when assembling the installer image.

**Cause:** live-build's installer package lists still name packages that no longer exist in
trixie, and `grub-pc` conflicts with `grub-efi-amd64`. The MacBook8,1 is EFI-only.

**Fix:** `sudo bash fix-livebuild-di-packages.sh` (patch 2) — narrows the list to
`grub-efi-amd64`.

---

## 5. `netinst_udeb_include` missing / datapath error

**Symptom:** `lb_binary_debian-installer` cannot find data files for the distribution.

**Cause:** `/usr/share/live/build/data/debian-cd/` has no `trixie` directory in this
live-build version.

**Fix:** `sudo bash fix-livebuild-trixie-data.sh` (patch 3) symlinks `trixie → sid`.
It refuses to run if `sid` is genuinely absent, because then something else is wrong.

---

## 6. Black screen after selecting *EFI Boot*

**Symptom:** the firmware finds the stick, the screen goes dark, nothing happens.

**Cause:** three known candidates — an EFI binary without a valid prefix (empty memdisk), a
missing `unicode.pf2` (gfxterm then renders nothing), or an `efi.img` built with pyfatfs
(which produced corrupt FAT in the original attempt).

**Fix:** use `add-efi-boot.py` (mtools + `grub-mkimage -p (memdisk)/boot/grub -c early.cfg`).
Verify the result contains `boot/grub/efi.img` and `EFI/boot/bootx64.efi`:

```bash
bash verify-iso.sh
7z l laps-macbook-debian-trixie.iso | grep -E 'efi.img|bootx64|grub.cfg'
```

---

## 7. OVMF/QEMU: `failure reading sector`

**Symptom:** firmware starts reading, then aborts with a sector error.

**Cause:** placement. If the kernel and initrd land after the 2.4 GB squashfs on the disc,
OVMF cannot read them reliably.

**Fix:** keep the `-graft-points` path list in `add-efi-boot.py` — the kernel, initrd and
squashfs are written first, in that order. Any "simplification" that re-sorts entries
reintroduces the bug.

---

## 8. Build dies or hangs when the terminal closes / `Ctrl+Z` is pressed

**Symptom:** build stalls, apt locks remain, later runs fail.

**Cause:** a suspended foreground process still holds the chroot and apt locks.

**Fix:** `build-laps-debian.sh` and `resume-binary.sh` already run the build in a detached
`nohup` child and write `.build-done` only on success — drive them, do not type `lb` by hand
in a foreground shell. If a stuck process exists, kill that exact PID (never `pkill -f lb`).

---

## 9. `sudo` scripts behave as if `~` is `/root`

**Symptom:** a script run with `sudo bash …` writes to `/root/…` or cannot find its files.

**Cause:** `sudo` sets `HOME=/root`. Every `~` expands to the root home.

**Fix:** all scripts here resolve their own directory (`$(cd "$(dirname "$0")" && pwd)`) and
use absolute paths. Keep it that way when editing; never reintroduce `~/`.

---

## 10. Rebuild produces a different checksum, or the GRUB menu boots nothing

**Symptom:** a fresh build works but does not match `MANIFEST.md`, or the menu entries point
at files that no longer exist.

**Cause:** no snapshot pinning (mirrors move), and — in the older revision — a hardcoded
kernel filename in the GRUB menu.

**Fix:** the current `add-efi-boot.py` detects the kernel/initrd names from the built ISO, so
new kernels are handled automatically. For byte-level similarity, pin a `snapshot.debian.org`
date in `config/archives`. Otherwise treat each build as its own artefact and record its
checksum.
