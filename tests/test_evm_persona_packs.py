"""D0.5: public Persona Pack manifest and boundary contract checks."""

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_ROOT = ROOT / "evm2" / "agent-packs" / "packs"
PUBLIC_IDS = {"vosmenog", "minotaur"}
AVAILABILITY = {"reference_only", "source_only", "native_installed", "unavailable"}


class TestPublicPersonaPacks(unittest.TestCase):
    def test_exact_public_catalog(self):
        found = {p.name for p in PACK_ROOT.iterdir() if p.is_dir()}
        self.assertEqual(found, PUBLIC_IDS)

    def test_manifests_and_source_paths(self):
        for persona_id in sorted(PUBLIC_IDS):
            with self.subTest(persona_id=persona_id):
                path = PACK_ROOT / persona_id / "pack.json"
                manifest = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(manifest["schema_version"], "0.1")
                self.assertEqual(manifest["persona_id"], persona_id)
                self.assertEqual(manifest["visibility"], "public")
                self.assertEqual(manifest["authority"], "unchanged_by_persona_pack")
                self.assertEqual(manifest["verification"], "not_tested_in_chatgpt")
                self.assertTrue(manifest["persona_sources"])
                sources = manifest["persona_sources"] + [
                    skill["source"] for skill in manifest["skills"]
                ]
                for source in sources:
                    self.assertEqual(source["repository"], "Skunokil/vosmenog")
                    self.assertEqual(source["ref"], "main")
                    rel = Path(source["path"])
                    self.assertFalse(rel.is_absolute())
                    self.assertNotIn("..", rel.parts)
                    self.assertTrue((ROOT / rel).is_file(), rel)
                for skill in manifest["skills"]:
                    self.assertIn(skill["availability"], AVAILABILITY)
                    self.assertNotEqual(skill["availability"], "native_installed")

    def test_documents_present(self):
        for path in (
            "evm2/agent-packs/REGISTRY.md",
            "evm2/agent-packs/PACK_CONTRACT.md",
            "evm2/adapters/chatgpt/PERSONA_ROUTER.md",
            "evm2/skills/persona-maker/SKILL.md",
        ):
            self.assertTrue((ROOT / path).is_file(), path)


if __name__ == "__main__":
    unittest.main()
