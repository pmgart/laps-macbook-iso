# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for add-efi-boot.py.

Run:  python3 -m unittest discover -s tests -v
These cover the parts that are cheap to test without a 40-minute live-build run:
kernel name detection (the trap that silently breaks the GRUB menu) and MBR blob
resolution.
"""
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("add_efi_boot", ROOT / "add-efi-boot.py")
assert _spec is not None and _spec.loader is not None, "kan inte ladda add-efi-boot.py"
aeb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(aeb)


class KernelDetectionTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.live = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def touch(self, *names):
        for n in names:
            (self.live / n).write_text("x")

    def test_single_pair(self):
        self.touch("vmlinuz-6.12.107+deb13-amd64", "initrd.img-6.12.107+deb13-amd64")
        self.assertEqual(
            aeb.detect_kernel(self.live),
            ("vmlinuz-6.12.107+deb13-amd64", "initrd.img-6.12.107+deb13-amd64"),
        )

    def test_kernel_without_initrd_is_ignored(self):
        self.touch("vmlinuz-6.1.0-1-amd64")
        with self.assertRaises(SystemExit):
            aeb.detect_kernel(self.live)

    def test_empty_dir_raises(self):
        with self.assertRaises(SystemExit):
            aeb.detect_kernel(self.live)

    def test_multiple_pairs_picks_highest_sorted(self):
        self.touch(
            "vmlinuz-6.11.0-amd64", "initrd.img-6.11.0-amd64",
            "vmlinuz-6.12.107+deb13-amd64", "initrd.img-6.12.107+deb13-amd64",
        )
        self.assertEqual(aeb.detect_kernel(self.live)[0], "vmlinuz-6.12.107+deb13-amd64")

    def test_override_accepts_bare_version(self):
        self.touch("vmlinuz-6.12.107+deb13-amd64", "initrd.img-6.12.107+deb13-amd64")
        self.assertEqual(
            aeb.detect_kernel(self.live, "6.12.107+deb13-amd64"),
            ("vmlinuz-6.12.107+deb13-amd64", "initrd.img-6.12.107+deb13-amd64"),
        )

    def test_override_accepts_prefixed_name(self):
        self.touch("vmlinuz-6.12.107+deb13-amd64", "initrd.img-6.12.107+deb13-amd64")
        self.assertEqual(
            aeb.detect_kernel(self.live, "vmlinuz-6.12.107+deb13-amd64")[0],
            "vmlinuz-6.12.107+deb13-amd64",
        )

    def test_override_that_does_not_exist_raises(self):
        self.touch("vmlinuz-6.12.107+deb13-amd64", "initrd.img-6.12.107+deb13-amd64")
        with self.assertRaises(SystemExit):
            aeb.detect_kernel(self.live, "9.9.9-nope")


class GrubConfigTest(unittest.TestCase):
    def test_spi_fix_in_all_boot_paths(self):
        cfg = aeb.GRUB_CFG_TEMPLATE.format(
            kernel="vmlinuz-6.12.107+deb13-amd64", initrd="initrd.img-6.12.107+deb13-amd64"
        )
        # live (2 entries) + graphical installer + text installer
        self.assertEqual(cfg.count("initcall_blacklist=dw_pci_driver_init"), 4)
        self.assertIn("/live/vmlinuz-6.12.107+deb13-amd64", cfg)
        self.assertIn("/live/initrd.img-6.12.107+deb13-amd64", cfg)

    def test_four_desktop_menus_present(self):
        cfg = aeb.GRUB_CFG_TEMPLATE.format(kernel="vmlinuz-x", initrd="initrd.img-x")
        for token in ("LAPS Debian Live", "Installer (graphical)", "Installer (text)", "local disk"):
            self.assertIn(token, cfg)


class IsohdpfxTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self._saved = (getattr(aeb, "BASE"), getattr(aeb, "LEGACY_ISOHPFX"))
        setattr(aeb, "BASE", self.tmp)
        setattr(aeb, "LEGACY_ISOHPFX", self.tmp / "legacy.bin")
        self._env = os.environ.pop("LAPS_ISOHPFX", None)

    def tearDown(self):
        setattr(aeb, "BASE", self._saved[0])
        setattr(aeb, "LEGACY_ISOHPFX", self._saved[1])
        if self._env is not None:
            os.environ["LAPS_ISOHPFX"] = self._env
        self._tmp.cleanup()

    def test_missing_returns_none(self):
        self.assertIsNone(aeb.find_isohdpfx())

    def test_wrong_size_is_rejected(self):
        (self.tmp / "tools").mkdir()
        (self.tmp / "tools" / "isohdpfx.bin").write_bytes(b"0" * 100)
        self.assertIsNone(aeb.find_isohdpfx())

    def test_correct_size_is_accepted(self):
        (self.tmp / "tools").mkdir()
        blob = self.tmp / "tools" / "isohdpfx.bin"
        blob.write_bytes(b"\0" * 432)
        self.assertEqual(aeb.find_isohdpfx(), blob)


if __name__ == "__main__":
    unittest.main()
