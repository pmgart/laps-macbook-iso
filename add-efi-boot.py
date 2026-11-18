#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make the live-build ISO bootable on Apple EFI (MacBook8,1) — Debian's proven model.

Why this step exists
--------------------
live-build 3.0~a57 cannot produce a grub-efi ISO: LB_BOOTLOADER=grub-efi is accepted
for the *installer*, but `lb binary` writes binary.hybrid.iso without a bootloader.
This script takes that ISO and adds the EFI path itself, following the exact recipe
Debian uses for debian-live-*-amd64-cinnamon.iso:

  xorriso -as mkisofs -R -r -J -joliet-long -l -cache-inodes -iso-level 3
    -isohybrid-mbr <isohdpfx.bin> -partition_offset 16
    -e boot/grub/efi.img -no-emul-boot
    -isohybrid-gpt-basdat -isohybrid-apm-hfsplus

Design points that took real debugging (do not "simplify" them away)
--------------------------------------------------------------------
1. The EFI binary is built with `grub-mkimage -p (memdisk)/boot/grub -c early.cfg`, so
   the prefix can find its grub.cfg. An empty memdisk gives a silent black screen.
2. early-config searches for /boot/grub/grub.cfg, sets prefix, then calls `normal`.
3. efi.img is built with mtools (mformat/mmd/mcopy). The older pyfatfs variant
   (make-efi-img.py) produced corrupt FAT and is kept for reference only.
4. unicode.pf2 ships inside efi.img and in /boot/grub — without the font gfxterm shows
   nothing.
5. Placement matters: kernel and initrd must sit at low LBA, *before* the 2.4 GB
   squashfs, or OVMF fails with "failure reading sector". Hence -graft-points with an
   explicit path list, kernel first.

Usage
-----
    python3 add-efi-boot.py                 # run after `lb binary`
    python3 add-efi-boot.py --check         # verify inputs/tools, change nothing
    python3 add-efi-boot.py --kernel 6.12.107+deb13-amd64
    python3 add-efi-boot.py --output /tmp/my.iso --label MY-LIVE

Inputs : chroot/binary.hybrid.iso (from `lb binary`) + tools/isohdpfx.bin + grub unicode.pf2
Output : laps-macbook-debian-trixie.iso (repo root)
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BASE = Path(__file__).resolve().parent
SRC = BASE / "chroot" / "binary.hybrid.iso"
OUT = BASE / "laps-macbook-debian-trixie.iso"
UNICODE_PF2 = Path("/usr/share/grub/unicode.pf2")
# Historical location, kept as fallback for the machine this was originally written on.
LEGACY_ISOHPFX = Path.home() / ".hermes" / "cache" / "scratch" / "isohdpfx-laps.bin"
REQUIRED_TOOLS = ("xorriso", "grub-mkimage", "grub-fstest", "mformat", "mmd", "mcopy")

# GRUB menu — the SPI fix (initcall_blacklist=dw_pci_driver_init) is present in every
# path: live, graphical installer and text installer, so the internal keyboard works
# in all three phases.
GRUB_CFG_TEMPLATE = """\
set timeout=10
set default=0
insmod all_video
insmod gfxterm
insmod png
set gfxmode=auto
set gfxpayload=keep
loadfont /boot/grub/unicode.pf2
terminal_output gfxterm

menuentry "LAPS Debian Live — 4 desktops (MacBook8,1 SPI fix active)" {{
\tlinux /live/{kernel} boot=live components quiet splash initcall_blacklist=dw_pci_driver_init keyboard-layouts=se
\tinitrd /live/{initrd}
}}
menuentry "LAPS Debian Live — 4 desktops (debug console, no splash)" {{
\tlinux /live/{kernel} boot=live components initcall_blacklist=dw_pci_driver_init keyboard-layouts=se
\tinitrd /live/{initrd}
}}
menuentry "LAPS Debian Installer (graphical)" {{
\tlinux /install/gtk/vmlinuz initcall_blacklist=dw_pci_driver_init preseed/file=/cdrom/install/preseed.cfg
\tinitrd /install/gtk/initrd.gz
}}
menuentry "LAPS Debian Installer (text)" {{
\tlinux /install/vmlinuz initcall_blacklist=dw_pci_driver_init preseed/file=/cdrom/install/preseed.cfg
\tinitrd /install/initrd.gz
}}
menuentry "Boot from local disk" {{
\texit 1
}}
"""

# Debian's early-config pattern: locate the config file, set prefix, hand over to `normal`.
EARLY_CFG = """\
search --set=root --file /boot/grub/grub.cfg
set prefix=($root)/boot/grub
export prefix
normal
"""

GRUB_MODULES = (
    "linux efi_gop efitextmode all_video fat iso9660 part_gpt part_msdos "
    "normal boot configfile search search_fs_file search_fs_uuid echo ls test "
    "gfxterm gfxmenu font png memdisk tar"
)


def said(msg: str) -> None:
    print(msg, flush=True)


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    said(f"  $ {' '.join(str(c) for c in cmd[:6])}{' ...' if len(cmd) > 6 else ''}")
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        print(f"❌ FAILED: {' '.join(str(c) for c in cmd[:3])}\n{r.stdout[-400:]}\n{r.stderr[-400:]}")
        sys.exit(1)
    return r


def find_isohdpfx() -> Path | None:
    """MBR blob (432 bytes) for -isohybrid-mbr. Never silently substitute another file."""
    for candidate in (os.environ.get("LAPS_ISOHPFX"), BASE / "tools" / "isohdpfx.bin", LEGACY_ISOHPFX):
        if not candidate:
            continue
        p = Path(candidate)
        if p.is_file() and p.stat().st_size == 432:
            return p
    return None


def check_tools() -> list[str]:
    """Names of required host tools that are not on PATH."""
    return [t for t in REQUIRED_TOOLS if shutil.which(t) is None]


def detect_kernel(live_dir: Path, override: str | None = None) -> tuple[str, str]:
    """Return (vmlinuz-name, initrd-name) as they appear inside /live of the source ISO.

    live-build names them vmlinuz-<ver> and initrd.img-<ver>. Auto-detection keeps the
    GRUB menu correct across kernel updates; a hardcoded version silently produces a
    menu pointing at files that no longer exist.
    """
    if override:
        kernel = override if override.startswith("vmlinuz-") else f"vmlinuz-{override}"
        initrd = "initrd.img-" + kernel[len("vmlinuz-"):]
        if not (live_dir / kernel).is_file():
            raise SystemExit(f"❌ {live_dir / kernel} finns inte")
        if not (live_dir / initrd).is_file():
            raise SystemExit(f"❌ {live_dir / initrd} finns inte")
        return kernel, initrd

    pairs: list[tuple[str, str]] = []
    for k in sorted(live_dir.glob("vmlinuz-*")):
        i = live_dir / ("initrd.img-" + k.name[len("vmlinuz-"):])
        if i.is_file():
            pairs.append((k.name, i.name))
    if not pairs:
        found = sorted(p.name for p in live_dir.glob("*"))[:10]
        raise SystemExit(f"❌ Inget vmlinuz-*/initrd.img-*-par i {live_dir} (hittade: {found})")
    if len(pairs) > 1:
        said(f"⚠️  Flera kärnor i /live — använder {pairs[-1][0]} (override med --kernel)")
    return pairs[-1]


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Add Debian-style EFI boot to a live-build ISO (MacBook8,1).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Kör efter `sudo lb build`; verifiera sedan med verify-iso.sh.",
    )
    ap.add_argument("--check", action="store_true", help="verifiera indata och verktyg, bygg inget")
    ap.add_argument("--source", type=Path, default=SRC, help=f"käll-ISO (default: {SRC})")
    ap.add_argument("--output", type=Path, default=OUT, help=f"utdata (default: {OUT})")
    ap.add_argument("--kernel", help="kärnversion, t.ex. 6.12.107+deb13-amd64 (auto annars)")
    ap.add_argument("--label", default="LAPS-MACBOOK-DEBIAN", help="ISO-volymerikett")
    args = ap.parse_args()

    src: Path = args.source
    out: Path = args.output
    isohpfx = find_isohdpfx()
    missing = check_tools()

    if args.check:
        problems = []
        said("== förhandskontroll ==")
        said(f"  käll-ISO    : {src} {'✅' if src.is_file() else '❌ saknas — kör lb binary först'}")
        said(f"  MBR-blob    : {isohpfx or '❌ saknas — kör tools/setup-host-deps.sh'}")
        said(f"  unicode.pf2 : {UNICODE_PF2} {'✅' if UNICODE_PF2.is_file() else '❌ saknas (apt install grub-common)'}")
        said(f"  verktyg     : {'✅ alla finns' if not missing else '❌ saknas: ' + ' '.join(missing)}")
        said(f"  utdata      : {out}")
        said("  kärna       : detekteras från /live när käll-ISO:n extraherats"
             + (f" (override: {args.kernel})" if args.kernel else ""))
        if not src.is_file():
            problems.append("käll-ISO")
        if isohpfx is None:
            problems.append("MBR-blob")
        if not UNICODE_PF2.is_file():
            problems.append("unicode.pf2")
        problems.extend(missing)
        if problems:
            said("❌ saknas: " + ", ".join(problems))
        sys.exit(1 if problems else 0)

    if not src.is_file():
        raise SystemExit(f"❌ {src} saknas — kör `sudo lb build` (eller build-laps-debian.sh) först")
    if isohpfx is None:
        raise SystemExit("❌ isohdpfx-blob (432 B) saknas — kör tools/setup-host-deps.sh")
    if missing:
        raise SystemExit("❌ Saknade verktyg: " + " ".join(missing))
    if not UNICODE_PF2.is_file():
        raise SystemExit(f"❌ {UNICODE_PF2} saknas — apt install grub-common")

    work = Path(tempfile.mkdtemp(prefix="laps-efi-"))
    said(f"Arbetskatalog: {work}")

    # ── Steg 1: Extrahera käll-ISO med xorriso osirrox (bevarar allt) ──
    said("1/6 Extraherar käll-ISO (osirrox)...")
    tree = work / "tree"
    run(["xorriso", "-osirrox", "on", "-indev", str(src), "-extract", "/", str(tree)])
    run(["chmod", "-R", "u+w", str(tree)])
    dirs = sorted(d.name for d in tree.iterdir())
    if "live" not in dirs or "install" not in dirs:
        raise SystemExit(f"❌ live/install saknas i ISO-trädet: {dirs}")
    said(f"  ✅ {len(list(tree.rglob('*')))} noder; live+install+pool finns")

    kernel, initrd = detect_kernel(tree / "live", args.kernel)
    said(f"  ✅ kärna: {kernel} + {initrd}")
    grub_cfg = GRUB_CFG_TEMPLATE.format(kernel=kernel, initrd=initrd)

    # ── Steg 2: /boot/grub i trädet (Debians modell) ──
    said("2/6 Bygger /boot/grub (grub.cfg + font) i ISO-trädet...")
    bg = tree / "boot" / "grub"
    bg.mkdir(parents=True, exist_ok=True)
    (bg / "grub.cfg").write_text(grub_cfg)
    shutil.copy2(UNICODE_PF2, bg / "unicode.pf2")

    # ── Steg 3: EFI-binär — memdisk med meny (fallback) + early-config (huvudväg) ──
    said("3/6 Bygger GRUB EFI-binär (grub-mkimage -c early-config)...")
    memdisk_dir = work / "memdisk-root" / "boot" / "grub"
    memdisk_dir.mkdir(parents=True)
    (memdisk_dir / "grub.cfg").write_text(grub_cfg)  # fallback-meny i memdisk
    early = work / "early.cfg"
    early.write_text(EARLY_CFG)
    efi_bin = work / "bootx64.efi"
    run([
        "grub-mkimage", "-O", "x86_64-efi",
        "-o", str(efi_bin),
        "-p", "(memdisk)/boot/grub",
        "-c", str(early),
        *GRUB_MODULES.split(),
    ])

    # ── Steg 4: efi.img med mtools (FAT32, Debians layout) ──
    said("4/6 Skapar efi.img (mtools FAT32)...")
    efi_img = work / "efi.img"
    img_mb = 8
    efi_img.write_bytes(b"\x00" * (img_mb * 1024 * 1024))
    run(["mformat", "-i", str(efi_img), "-C", "-T", str((img_mb * 1024 * 1024) // 512), "-h", "255", "-s", "63", "::"])
    run(["mmd", "-i", str(efi_img), "::EFI", "::EFI/boot", "::boot", "::boot/grub"])
    run(["mcopy", "-i", str(efi_img), str(efi_bin), "::EFI/boot/bootx64.efi"])
    run(["mcopy", "-i", str(efi_img), str(efi_bin), "::boot/grub/grubx64.efi"])
    run(["mcopy", "-i", str(efi_img), str(bg / "grub.cfg"), "::boot/grub/grub.cfg"])
    run(["mcopy", "-i", str(efi_img), str(early), "::boot/grub/early.cfg"])
    run(["mcopy", "-i", str(efi_img), str(UNICODE_PF2), "::boot/grub/unicode.pf2"])

    (tree / "boot" / "grub" / "efi.img").write_bytes(efi_img.read_bytes())
    et = tree / "EFI" / "boot"
    et.mkdir(parents=True, exist_ok=True)
    shutil.copy2(efi_bin, et / "bootx64.efi")

    # ── Steg 5: xorriso mkisofs + graft-points — deterministisk placeringsordning ──
    # Empiriskt bevisat: när kernel+initrd ligger tidigt (låg LBA) bootar OVMF
    # fullständigt; ligger de efter 1,5 GB squashfs → "failure reading sector".
    said("5/6 Bygger hybrid-ISO (graft-points, kernel först)...")
    out_tmp = work / "out.iso"
    lines = [f"/live/{kernel}={tree / 'live' / kernel}",
             f"/live/{initrd}={tree / 'live' / initrd}",
             f"/live/filesystem.squashfs={tree / 'live' / 'filesystem.squashfs'}"]
    for p in sorted((tree / "boot").rglob("*")):
        if p.is_file():
            lines.append(f"/boot/{p.relative_to(tree / 'boot')}={p}")
    lines.append(f"/EFI/boot/bootx64.efi={et / 'bootx64.efi'}")
    for p in sorted(tree.rglob("*")):
        if p.is_dir():
            continue
        s = str(p.relative_to(tree))
        if s.startswith(("boot/", "EFI/", "live/")):
            continue
        lines.append(f"/{s}={p}")
    path_list = work / "path-list.txt"
    path_list.write_text("\n".join(lines) + "\n")
    run([
        "xorriso", "-as", "mkisofs",
        "-R", "-r", "-J", "-joliet-long", "-l", "-cache-inodes", "-iso-level", "3",
        "-graft-points",
        "-isohybrid-mbr", str(isohpfx),
        "-partition_offset", "16",
        "-V", args.label,
        "-e", "boot/grub/efi.img", "-no-emul-boot",
        "-isohybrid-gpt-basdat", "-isohybrid-apm-hfsplus",
        "-path-list", str(path_list),
        "-o", str(out_tmp),
    ])

    # ── Steg 6: Verifiering ──
    said("6/6 Verifierar ISO:n...")
    checks = [
        ("grub.cfg i trädet", ["grub-fstest", str(out_tmp), "ls", "(loop0)/boot/grub/"]),
        ("live-katalog", ["grub-fstest", str(out_tmp), "ls", "(loop0)/live/"]),
        ("install-katalog", ["grub-fstest", str(out_tmp), "ls", "(loop0)/install/"]),
        ("grub.cfg innehåll (menuentry)", ["grub-fstest", str(out_tmp), "cat", "(loop0)/boot/grub/grub.cfg"]),
    ]
    for name, cmd in checks:
        r = subprocess.run(cmd, capture_output=True, text=True)
        text = (r.stdout or r.stderr).strip()
        ok = r.returncode == 0 and len(text) > 0
        said(f"  {'✅' if ok else '❌'} {name}: {text[:120]}")
        if not ok:
            sys.exit(1)

    shutil.move(str(out_tmp), str(out))
    said(f"\n✅ KLAR: {out}")
    said(f"   Storlek: {out.stat().st_size / 1024 / 1024:.0f} MB")
    said("   EFI: /boot/grub/efi.img (El Torito) + /EFI/boot/bootx64.efi + memdisk-fallback")
    said("   USB-hybrid: isohybrid-gpt-basdat + MBR-kod → BalenaEtcher-flashbar")


if __name__ == "__main__":
    main()
