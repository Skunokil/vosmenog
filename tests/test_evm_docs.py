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


    def test_session_exists_before_any_epic(self):
        for p in (self.plan / "epics").glob("*.md"):
            p.unlink()
        session = self.parsed("new-session")
        self.assertTrue(session["uid"].startswith("D-"))
        self.assertFalse(list((self.plan / "epics").glob("*.md")))
        path = Path(session["path"])
        first = json.loads(path.read_text().splitlines()[0].removeprefix("<!-- evm-doc: ").removesuffix(" -->"))
        self.assertEqual(first["classification"], "undecided")
        self.assertEqual(first["work_refs"], [])
        self.assertEqual(first["route_history"], [])
        self.assertIn("Исходное намерение", path.read_text())
        self.assertEqual(self.parsed("check")["status"], "PASS")
        route = self.parsed("route", "--session-uid", session["uid"], "--kind", "no_epic")
        self.assertEqual(route["classification"], "no_epic")
        self.assertEqual(route["work_refs"], [])
        self.assertEqual(self.parsed("check")["status"], "PASS")

    def test_route_later_links_a_new_epic_without_changing_session_identity(self):
        session = self.parsed("new-session")
        session_path = Path(session["path"])
        original = session_path.read_text().partition("\n")[2]
        epic = self.parsed("new-work", "--kind", "EPIC", "--slug", "new-intent")
        work_path = Path(epic["path"]).relative_to(self.plan).as_posix()
        linked = self.parsed("route", "--session-uid", session["uid"], "--kind", "epic",
                             "--work-path", work_path)
        self.assertEqual(linked["classification"], "epic")
        self.assertEqual(linked["work_refs"], [epic["uid"]])
        self.assertEqual(original, session_path.read_text().partition("\n")[2])
        first = json.loads(session_path.read_text().splitlines()[0][14:-4])
        self.assertEqual(first["uid"], session["uid"])
        self.assertEqual(first["route_history"][0]["kind"], "epic")
        self.assertEqual(self.parsed("check")["status"], "PASS")

    def test_session_can_route_to_more_than_one_work_document(self):
        session = self.parsed("new-session")
        epic = self.parsed("new-work", "--kind", "EPIC", "--slug", "problem")
        ep = Path(epic["path"]).relative_to(self.plan).as_posix()
        self.parsed("route", "--session-uid", session["uid"], "--kind", "epic", "--work-path", ep)
        bug = self.parsed("new-work", "--kind", "BUG", "--parent", epic["code"], "--slug", "failure")
        bp = Path(bug["path"]).relative_to(self.plan).as_posix()
        result = self.parsed("route", "--session-uid", session["uid"], "--kind", "bug",
                             "--work-path", bp)
        self.assertEqual(result["classification"], "mixed")
        self.assertEqual(set(result["work_refs"]), {epic["uid"], bug["uid"]})
        self.assertEqual(self.parsed("check")["status"], "PASS")

    def test_route_requires_exact_path_for_legacy(self):
        session = self.parsed("new-session")
        initial = Path(session["path"]).read_bytes()
        invalid = self.call("route", "--session-uid", session["uid"], "--kind", "epic",
                            "--work-path", "EPIC-011")
        self.assertEqual(invalid.returncode, 2)
        self.assertEqual(Path(session["path"]).read_bytes(), initial)
        result = self.parsed("route", "--session-uid", session["uid"], "--kind", "epic",
                             "--work-path", "epics/EPIC-011-basic.md")
        self.assertEqual(result["work_refs"], ["path:epics/EPIC-011-basic.md"])

    def test_route_rejects_native_session_and_does_not_create_shadow_document(self):
        native = self.plan / "sessions/work" / ("b"*32 + ".json")
        native.write_bytes(b"private token: never-read")
        before = set((self.plan / "sessions/work").iterdir())
        response = self.call("route", "--session-uid", "N-"+"b"*32, "--kind", "research")
        self.assertEqual(response.returncode, 2)
        self.assertEqual(before, set((self.plan / "sessions/work").iterdir()))
        self.assertEqual(native.read_bytes(), b"private token: never-read")




    def test_session_template_ensures_handoff_provenance_slots(self):
        # Regression guard: docs generator really includes D0.6 claim-level fields.
        session = self.parsed("new-session")
        content = Path(session["path"]).read_text(encoding="utf-8")
        self.assertIn("## 2a. Значимые решения и ограничения — происхождение (D0.6)", content)
        self.assertIn("| claim | origin / evidence_ref | authority | scope / valid_until | confirmation |", content)
        self.assertIn("agent_proposal", content)
        self.assertIn("needs_confirmation", content)
        self.assertIn("handoff_only", content)
        self.assertIn("Сверка утверждений при получении", content)
        self.assertNotIn("S-YYYYMMDDThhmmssZ-<12hex>", content)


if __name__ == "__main__":
    unittest.main()
