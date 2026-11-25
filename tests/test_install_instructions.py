"""Preserve owner instructions when installing and updating shipped profiles."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallInstructions(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.config = Path(work.name) / "config"
        self.agent = Path(work.name) / "agent"
        self.rules = self.config / "AGENTS.md"
        self.profile = self.config / "agents/Vosmenog.md"
        self.persona = self.agent / "persona_vosya.md"

    def install(self):
        subprocess.run([sys.executable, str(ROOT / "vosmenog/install-instructions.py"),
                        str(self.config), str(self.agent)], check=True, capture_output=True)

    def test_custom_global_persona_and_profile_survive(self):
        self.install()
        for path in (self.rules, self.persona, self.profile):
            path.write_bytes(b"owner instructions\r\n")
        self.install()
        for path in (self.rules, self.persona, self.profile):
            self.assertEqual(path.read_bytes(), b"owner instructions\r\n")

    def test_symlink_remains_owned(self):
        self.config.mkdir()
        target = self.config / "owner.md"
        self.rules.symlink_to(target)
        self.install()
        self.assertTrue(self.rules.is_symlink())
        self.assertFalse(target.exists())

    def test_managed_profile_with_local_perimeter(self):
        self.install()
        revision = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"])
        (self.config / ".vosmenog-deployed").write_bytes(revision)
        old = subprocess.check_output(["git", "-C", str(ROOT), "show",
                                       "HEAD:vosmenog/agents/Vosmenog.md"])
        template = (ROOT / "vosmenog/agents/Vosmenog.md").read_bytes()
        marker = "    # При установке сюда дописываются".encode()
        deny = b'    "/private/example/**": deny\n'
        self.profile.write_bytes(old.replace(marker, deny + marker))
        self.install()
        self.assertEqual(self.profile.read_bytes(), template.replace(marker, deny + marker))
