"""Behavioral regression tests for EVM document catalog, no network or real project."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "harness/tools/evm-docs"


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="evm-doc-test-")
        self.addCleanup(self.tmp.cleanup)
        self.plan = Path(self.tmp.name) / "demo"
        for name in ("epics", "bugs", "sessions/archive", "sessions/work"):
            (self.plan / name).mkdir(parents=True, exist_ok=True)
        (self.plan / "epics/EPIC-011-basic.md").write_text("# EPIC-011: basic\n")
        (self.plan / "epics/TASK-011-1-first.md").write_text("# TASK-011-1\n")
        (self.plan / "epics/TASK-011-1-alternative.md").write_text("# TASK-011-1\n")

    def call(self, action, *args):
        return subprocess.run([sys.executable, "-I", str(CLI), "--planning",
                               str(self.plan), "--project", "demo", action, *args],
                              capture_output=True, text=True, timeout=20)

    def parsed(self, action, *args):
        proc = self.call(action, *args)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        return json.loads(proc.stdout)

    def test_legacy_codes_are_warning_not_destructive(self):
        result = self.parsed("scan")
        self.assertEqual(result["status"], "PASS")
        self.assertTrue(any(p["code"] == "AMBIGUOUS_CODE" and p["human_code"] == "TASK-011-1"
                            for p in result["warnings"]))
        self.assertTrue((self.plan / "epics/TASK-011-1-first.md").is_file())

    def test_new_work_allocates_per_project_and_parent(self):
        first = self.parsed("new-work", "--kind", "TASK", "--parent", "EPIC-011",
                            "--slug", "next-safe")
        self.assertEqual(first["code"], "TASK-011-002")
        epic = self.parsed("new-work", "--kind", "EPIC", "--slug", "new-phase")
        self.assertEqual(epic["code"], "EPIC-012")
        self.assertTrue(first["uid"].startswith("D-"))
        body = Path(first["path"]).read_text()
        self.assertIn('"work_refs":["EPIC-011"]', body)
        self.assertIn("draft", body)
        second = self.parsed("new-work", "--kind", "TASK", "--parent", "EPIC-011",
                             "--slug", "later")
        self.assertEqual(second["code"], "TASK-011-003")

    def test_session_uid_index_round_trip_and_stale_detection(self):
        session = self.parsed("new-session", "--work-ref", "EPIC-011")
        path = Path(session["path"])
        text = path.read_text()
        self.assertIn('"code":"'+session["code"]+'"', text)
        self.assertIn(session["code"], text)
        self.assertNotIn("S-YYYYMMDDThhmmssZ-<12hex>", text)
        self.parsed("index")
        catalog_path = self.plan / "sessions/_catalog.json"
        saved = catalog_path.read_bytes()
        self.parsed("index")
        self.assertEqual(saved, catalog_path.read_bytes())
        self.assertEqual(self.parsed("check")["status"], "PASS")
        other = self.parsed("new-session")
        self.assertNotEqual(session["uid"], other["uid"])
        # Creation refreshes derived indexes under the same local lock.
        self.assertEqual(self.parsed("check")["status"], "PASS")
        archive = self.plan / "sessions/archive" / path.name
        path.rename(archive)
        self.parsed("index")
        entries = json.loads(catalog_path.read_text())["entries"]
        self.assertEqual([x["uid"] for x in entries if x["path"] == "sessions/archive/"+path.name],
                         [session["uid"]])

    def test_parallel_work_numbering(self):
        def allocate(_):
            return self.parsed("new-work", "--kind", "TASK", "--parent", "EPIC-011",
                               "--slug", "parallel-"+str(_))
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            docs = list(pool.map(allocate, range(4)))
        self.assertEqual(len({x["uid"] for x in docs}), 4)
        self.assertEqual(len({x["code"] for x in docs}), 4)
        self.assertEqual(self.parsed("check")["status"], "PASS")

    def test_native_json_is_indexed_without_reading_private_body(self):
        path = self.plan / "sessions/work" / ("a"*32+".json")
        path.write_bytes(b"private-and-not-valid-json-SECRET-DATA")
        self.parsed("index")
        result = (self.plan / "sessions/_catalog.json").read_text()
        self.assertIn("N-" + "a"*32, result)
        self.assertNotIn("SECRET-DATA", result)

    def test_duplicate_uid_is_error_and_does_not_overwrite_catalog(self):
        original = self.parsed("new-session")
        baseline_index = (self.plan / "sessions/_catalog.json").read_bytes()
        source = Path(original["path"])
        copy = source.with_name("S-20261114T180000Z-abcdef012345.md")
        copy.write_text(source.read_text())
        proc = self.call("index")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("DUPLICATE_UID", proc.stdout)
        self.assertEqual((self.plan / "sessions/_catalog.json").read_bytes(), baseline_index)

    def test_symlink_refused(self):
        link = self.plan / "sessions/archive/fake.md"
        link.symlink_to(self.plan / "epics/EPIC-011-basic.md")
        result = self.call("check")
        self.assertEqual(result.returncode, 2)
        self.assertIn("SYMLINK", result.stdout)

    def test_malformed_refs_refused(self):
        before = list((self.plan / "sessions").rglob("*.md"))
        self.assertEqual(self.call("new-session", "--work-ref", "E\nEPIC-011").returncode, 2)
        self.assertEqual(before, list((self.plan / "sessions").rglob("*.md")))

    def test_parallel_allocator(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda n: self.parsed("new-session"), range(6)))
        self.assertEqual(len({r["code"] for r in results}), 6)
        self.assertEqual(len({r["uid"] for r in results}), 6)
        self.assertEqual(len(list((self.plan / "sessions/active").glob("*.md"))), 6)


if __name__ == "__main__":
    unittest.main()
