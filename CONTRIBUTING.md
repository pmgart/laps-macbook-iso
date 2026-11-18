# Contributing

This is a small, hardware-specific project. The most valuable contributions are **reports
from real MacBook8,1 hardware** and **fixes for build breakage on other hosts**.

## Reporting a problem

Open an issue with:

1. What you ran (exact `make` target or command) and the **output**, not a summary of it.
2. The checksum of the ISO you built or booted: `sha256sum laps-macbook-debian-trixie.iso`.
3. Host details: `cat /etc/os-release | head -3`, `dpkg -l live-build | tail -1`,
   `uname -r`.
4. Hardware evidence where relevant: `cat /sys/class/dmi/id/product_name` must say
   `MacBook8,1`, plus `dmesg` lines for the subsystem in question.
5. If it is a boot problem: which menu entry, whether the machine is EFI-only, and whether
   a USB keyboard was attached.

Issues without the actual error text usually cannot be diagnosed — the interesting failures
here are silent (black screen, dead keyboard), so be explicit about what you observed.

## Changing code

- Shell: `bash -n` and `shellcheck -x -S warning *.sh tools/*.sh` must pass (both run in CI).
- Python: `python3 -m py_compile add-efi-boot.py` and `python3 -m unittest discover -s tests -v`.
- Never hardcode a home directory. Scripts resolve their own location with
  `BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and Python uses
  `Path(__file__).resolve().parent`. `sudo` sets `HOME=/root`, so `~/` breaks when the
  script is run with sudo.
- Keep the patch scripts **idempotent and self-verifying**: they must detect that they were
  already applied, and must fail loudly if the target file does not match expectations.
- Do not reorder the `-graft-points` path list in `add-efi-boot.py` — kernel and initrd must
  stay before the squashfs (see `docs/TROUBLESHOOTING.md`, item 7).
- If you change anything that affects the produced image, update `MANIFEST.md` with the new
  measurements and checksum.

## Scope

In scope: build system, EFI boot path, installer preseed, package selection, verification
tooling, documentation. Hardware fixes themselves (audio driver, camera firmware, sleep) live
in [`pmgart/macbook8-1-debian-guide`](https://github.com/pmgart/macbook8-1-debian-guide) —
report those there.

## Licence

Contributions are accepted under GPL-3.0-or-later, the licence of this repository.
