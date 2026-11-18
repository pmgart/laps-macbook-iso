# Legacy scripts — kept for reference, not used by the build

| File | Status | Why it is here |
|---|---|---|
| `add-efi-boot.sh.old` | **Superseded** | First attempt at the EFI step: `dd` + `mkfs.vfat` + `grub-mkstandalone` with an embedded config, hardcoded paths. It produced images that either showed a black screen or failed with `failure reading sector`. Replaced by `add-efi-boot.py`. |
| `make-efi-img.py` | **Superseded** | Built `efi.img` with pyfatfs, which produced corrupt FAT that Apple firmware refused. `add-efi-boot.py` uses mtools instead. |
| `sudoers-laps-livebuild.example` | Optional | Passwordless-sudo entry for one specific build script on one specific machine. Useful if you want an agent to trigger builds unattended; adjust user and path, install with `visudo -f /etc/sudoers.d/…`. Not required for a normal build. |

Nothing in `legacy/` is invoked by `make` or by any script in the repository root. They are
kept because the failure modes they document are referenced in `docs/TROUBLESHOOTING.md`
(items 6 and 7).
