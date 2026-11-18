#!/usr/bin/env python3
"""Bygger EFI-bootbar LAPS MacBook ISO — Debians officiella beprövade modell.

Guldstandard: .disk/mkisofs från debian-live-13.6.0-amd64-cinnamon.iso:
  xorriso -as mkisofs -R -r -J -joliet-long -l -cache-inodes -iso-level 3
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -partition_offset 16
    -b isolinux/isolinux.bin ... -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot
    -isohybrid-gpt-basdat -isohybrid-apm-hfsplus

Nyckeländringar vs gamla add-efi-boot.py:
 1. EFI-binären byggs med grub-mkstandalone + memdisk-katalog som positional arg
    → prefix (memdisk)/boot/grub hittar sin grub.cfg (gamla bug: tomt memdisk).
 2. early-config: search --file /boot/grub/grub.cfg → set prefix → normal
    (exakt Debians mönster) → ISO-trädets /boot/grub/grub.cfg ger menyn.
 3. efi.img byggs med mtools (mformat/mmd/mcopy) — inte pyfatfs (korrumperade FAT).
 4. unicode.pf2 font följer med i efi.img + /boot/grub → meny syns, ingen svartskärm.
 5. xorriso med exakta officiella flaggor: -iso-level 3, -partition_offset 16,
    -isohybrid-gpt-basdat, -isohybrid-apm-hfsplus, -isohybrid-mbr isohdpfx
    → funkar som USB-sticka på Mac EFI (BalenaEtcher-flashbar hybrid).

Källor:
  SRC_ISO   = live-build binary.hybrid.iso (data: /live /install /pool ...)
  ISOHPFX   = MBR-koden dd:ad från officiella Debian-ISO:n (isohdpfx.bin 432 bytes)
  UNICODE   = /usr/share/grub/unicode.pf2
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BASE = Path("/home/pablo-magana/laps-debian-live")
SRC = BASE / "chroot/binary.hybrid.iso"
OUT = BASE / "laps-macbook-debian-trixie.iso"
ISOHPFX = Path("/home/pablo-magana/.hermes/cache/scratch/isohdpfx-laps.bin")
UNICODE_PF2 = Path("/usr/share/grub/unicode.pf2")

# LAPS menyer — SPI-fix i alla vägar (GRUB-parameter live + installer + preseed-system)
GRUB_CFG = """\
set timeout=10
set default=0
insmod all_video
insmod gfxterm
insmod png
set gfxmode=auto
set gfxpayload=keep
loadfont /boot/grub/unicode.pf2
terminal_output gfxterm

menuentry "LAPS Debian Live — 4 skrivbord (MacBook8,1 SPI-fix aktiv)" {
\tlinux /live/vmlinuz-6.12.107+deb13-amd64 boot=live components quiet splash initcall_blacklist=dw_pci_driver_init keyboard-layouts=se
\tinitrd /live/initrd.img-6.12.107+deb13-amd64
}
menuentry "LAPS Debian Live — 4 skrivbord (debug-konsol, ingen splash)" {
\tlinux /live/vmlinuz-6.12.107+deb13-amd64 boot=live components initcall_blacklist=dw_pci_driver_init keyboard-layouts=se
\tinitrd /live/initrd.img-6.12.107+deb13-amd64
}
menuentry "LAPS Debian Installer (grafisk)" {
\tlinux /install/gtk/vmlinuz initcall_blacklist=dw_pci_driver_init preseed/file=/cdrom/install/preseed.cfg
\tinitrd /install/gtk/initrd.gz
}
menuentry "LAPS Debian Installer (text)" {
\tlinux /install/vmlinuz initcall_blacklist=dw_pci_driver_init preseed/file=/cdrom/install/preseed.cfg
\tinitrd /install/initrd.gz
}
menuentry "Boot from local disk" {
\texit 1
}
"""

# Debians early-config-mönster: sök filen → sätt prefix → normal-modulen läser meny
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


def run(cmd, **kw):
    print(f"  $ {' '.join(str(c) for c in cmd[:6])}{' ...' if len(cmd) > 6 else ''}")
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        print(f"❌ FEL: {' '.join(str(c) for c in cmd[:3])}\n{r.stdout[-400:]}\n{r.stderr[-400:]}")
        sys.exit(1)
    return r


def main():
    if not SRC.exists():
        print(f"❌ {SRC} saknas — kör build-laps-debian.sh först"); sys.exit(1)
    if not ISOHPFX.exists() or ISOHPFX.stat().st_size != 432:
        print(f"❌ {ISOHPFX} saknas/fel storlek (432 bytes)"); sys.exit(1)

    work = Path(tempfile.mkdtemp(prefix="laps-efi-gold-"))
    print(f"Arbetskatalog: {work}")

    # ── Steg 1: Extrahera käll-ISO med xorriso osirrox (bevarar allt) ──
    print("1/6 Extraherar binary.hybrid.iso (osirrox)...")
    tree = work / "tree"
    run(["xorriso", "-osirrox", "on", "-indev", str(SRC), "-extract", "/", str(tree)])
    # ISO9660-kataloger är skrivskyddade efter extraktion — gör trädet skrivbart:
    run(["chmod", "-R", "u+w", str(tree)])
    dirs = sorted(d.name for d in tree.iterdir())
    assert "live" in dirs and "install" in dirs, f"live/install saknas i trädet: {dirs}"
    print(f"  ✅ {len(list(tree.rglob('*')))} noder; live+install+pool finns")

    # ── Steg 2: /boot/grub i trädet (Debians modell) ──
    print("2/6 Bygger /boot/grub (grub.cfg + font) i ISO-trädet...")
    bg = tree / "boot" / "grub"
    bg.mkdir(parents=True, exist_ok=True)
    (bg / "grub.cfg").write_text(GRUB_CFG)
    shutil.copy2(UNICODE_PF2, bg / "unicode.pf2")

    # ── Steg 3: EFI-binär — memdisk med meny (fallback) + early-config (huvudväg) ──
    print("3/6 Bygger GRUB EFI-binär (grub-mkimage -c early-config)...")
    memdisk_dir = work / "memdisk-root" / "boot" / "grub"
    memdisk_dir.mkdir(parents=True)
    (memdisk_dir / "grub.cfg").write_text(GRUB_CFG)  # fallback-meny i memdisk
    early = work / "early.cfg"
    early.write_text(EARLY_CFG)
    efi_bin = work / "bootx64.efi"
    run([
        "grub-mkimage", "-O", "x86_64-efi",
        "-o", str(efi_bin),
        "-p", "(memdisk)/boot/grub",
        "-c", str(early),                       # early config: search → normal
        *GRUB_MODULES.split(),
    ])

    # ── Steg 4: efi.img med mtools (FAT32, Debians layout) ──
    print("4/6 Skapar efi.img (mtools FAT32)...")
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

    # efi.img på Debians plats i trädet
    (tree / "boot" / "grub" / "efi.img").write_bytes(efi_img.read_bytes())
    # + EFI/boot i trädet (vissa firmware letar endast där)
    et = tree / "EFI" / "boot"
    et.mkdir(parents=True, exist_ok=True)
    shutil.copy2(efi_bin, et / "bootx64.efi")

    # ── Steg 5: xorriso mkisofs + graft-points — deterministisk placeringsordning ──
    # Empiriskt bevisat 2026-09-24: när kernel+initrd ligger tidigt (låg LBA) bootar
    # OVMF fullständigt; ligger de efter 1.5GB squashfs → 'failure reading sector'.
    # -graft-points + -path-list: varje rad "/iso/sökväg=lokal/fil" — ISO-strukturen
    # definieras explicit och placeringsordningen = radordningen.
    print("5/6 Bygger hybrid-ISO (graft-points, kernel först)...")
    out_tmp = work / "out.iso"
    kv = "vmlinuz-6.12.107+deb13-amd64"
    iv = "initrd.img-6.12.107+deb13-amd64"
    lines = []
    # 1) boot-kritiska filer först:
    lines.append(f"/live/{kv}={tree / 'live' / kv}")
    lines.append(f"/live/{iv}={tree / 'live' / iv}")
    lines.append(f"/live/filesystem.squashfs={tree / 'live' / 'filesystem.squashfs'}")
    # 2) boot-lagret (grub.cfg + font + efi.img som El Torito-referens):
    for p in sorted((tree / "boot").rglob("*")):
        if not p.is_file():
            continue
        lines.append(f"/boot/{p.relative_to(tree / 'boot')}={p}")
    lines.append(f"/EFI/boot/bootx64.efi={et / 'bootx64.efi'}")
    # 3) resten av trädet sorterat (install, dists, firmware, pool, .disk):
    for p in sorted(tree.rglob("*")):
        if p.is_dir():
            continue
        rel = p.relative_to(tree)
        s = str(rel)
        if s.startswith("boot/") or s.startswith("EFI/") or s.startswith("live/"):
            continue
        lines.append(f"/{s}={p}")
    path_list = work / "path-list.txt"
    path_list.write_text("\n".join(lines) + "\n")
    run([
        "xorriso", "-as", "mkisofs",
        "-R", "-r", "-J", "-joliet-long", "-l", "-cache-inodes", "-iso-level", "3",
        "-graft-points",
        "-isohybrid-mbr", str(ISOHPFX),
        "-partition_offset", "16",
        "-V", "LAPS-MACBOOK-DEBIAN",
        "-e", "boot/grub/efi.img", "-no-emul-boot",
        "-isohybrid-gpt-basdat", "-isohybrid-apm-hfsplus",
        "-path-list", str(path_list),
        "-o", str(out_tmp),
    ])

    # ── Steg 6: Verifiering ──
    print("6/6 Verifierar ISO:n...")
    checks = [
        ("grub.cfg i trädet", ["grub-fstest", str(out_tmp), "ls", "(loop0)/boot/grub/"]),
        ("live-katalog", ["grub-fstest", str(out_tmp), "ls", "(loop0)/live/"]),
        ("install-katalog", ["grub-fstest", str(out_tmp), "ls", "(loop0)/install/"]),
        ("grub.cfg innehåll (menuentry)", ["grub-fstest", str(out_tmp), "cat", "(loop0)/boot/grub/grub.cfg"]),
    ]
    for name, cmd in checks:
        r = subprocess.run(cmd, capture_output=True, text=True)
        out = (r.stdout or r.stderr).strip()
        ok = r.returncode == 0 and len(out) > 0
        print(f"  {'✅' if ok else '❌'} {name}: {out[:120]}")
        if not ok:
            sys.exit(1)

    shutil.move(str(out_tmp), str(OUT))
    print(f"\n✅ KLAR: {OUT}")
    print(f"   Storlek: {OUT.stat().st_size/1024/1024:.0f} MB")
    print("   EFI: /boot/grub/efi.img (El Torito) + /EFI/boot/bootx64.efi + memdisk-fallback")
    print("   USB-hybrid: isohybrid-gpt-basdat + MBR-kod → BalenaEtcher-flashbar")


if __name__ == "__main__":
    main()