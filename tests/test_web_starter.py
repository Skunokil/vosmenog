"""Smoke and packaging tests for optional EVM browser starter."""
import json
from pathlib import Path
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "evm2" / "web-starter"


class WebStarterTests(unittest.TestCase):
    def test_manifest_and_source_paths(self):
        manifest = json.loads((PACK / "MANIFEST.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["version"], "0.2-beta")
        self.assertFalse(manifest["automatic_sync"])
        for name in manifest["files"]:
            self.assertTrue((PACK / name).is_file(), name)

    def test_offline_instruction_contract(self):
        instr = (PACK / "01_Instrukciya.md").read_text(encoding="utf-8")
        for expected in ("## 4. Происхождение важных решений и запретов",
                         "owner_direct", "agent_no_authority", "scope=unknown",
                         "needs_confirmation", "prepared / not_saved"):
            self.assertIn(expected, instr)
        self.assertIn("только", instr)
        self.assertIn("Не утверждай", instr)

    def test_entry_and_first_prompt(self):
        entry = (ROOT / "ENTRY.md").read_text(encoding="utf-8")
        prompt = (PACK / "00_PROMPT_START.txt").read_text(encoding="utf-8")
        self.assertIn("web-starter/README.md", entry)
        self.assertIn("EVM_WEB_STARTER_v0.2.zip", prompt)
        self.assertIn("ОДИН первый шаг", prompt)
        self.assertIn("Не придумывай", prompt)

    def test_downloadable_zip_matches_sources(self):
        manifest = json.loads((PACK / "MANIFEST.json").read_text(encoding="utf-8"))
        archive = PACK / manifest["archive"]
        self.assertTrue(archive.is_file())
        with ZipFile(archive) as zipfile:
            self.assertIsNone(zipfile.testzip())
            self.assertEqual(set(zipfile.namelist()), set(manifest["files"]))
            for name in manifest["files"]:
                self.assertEqual(zipfile.read(name), (PACK / name).read_bytes(), name)


if __name__ == "__main__":
    unittest.main()
