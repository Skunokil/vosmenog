"""Session Record lifecycle adapter regression tests; no real servers or secrets."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "harness/tools/evm-session"
EVM = ROOT / "harness/tools/evm"
INSTALL = ROOT / "harness/adapters/claude-code/install.py"
SOURCE = "claude-code"


class SessionHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="evm-hooks-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.planning = self.home / "project"
        self.planning.mkdir()
        for d in ("sessions", "epics", "bugs"):
            (self.planning / d).mkdir()
        self.env = {**os.environ, "HOME": str(self.home)}
        self.sid = "test-session-abc"

    def command(self, action, source=SOURCE, sid=None, *extras):
        argv = [sys.executable, str(HOOK), "--planning", str(self.planning),
                "--project", "demo", "--source", source,
                "--external-id", sid or self.sid, action, *extras]
        return subprocess.run(argv, capture_output=True, text=True, env=self.env, timeout=20)

    def result(self, action, source=SOURCE, sid=None, *extras):
        res = self.command(action, source, sid, *extras)
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
        return json.loads(res.stdout)

    def test_first_session_is_undecided_without_epic(self):
        result = self.result("ensure")
        self.assertEqual(result["status"], "CREATED")
        p = Path(result["path"])
        header = json.loads(p.read_text().splitlines()[0][14:-4])
        self.assertEqual(header["classification"], "undecided")
        self.assertEqual(header["work_refs"], [])
        self.assertFalse(list((self.planning / "epics").iterdir()))
        self.assertIn(result["uid"], p.read_text())
        self.assertEqual(self.result("ensure")["uid"], result["uid"])
        self.assertEqual(len(list((self.planning / "sessions/active").glob("*.md"))), 1)

    def test_parallel_start_does_not_duplicate_document(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda i: self.result("ensure"), range(6)))
        self.assertEqual(len({r["uid"] for r in results}), 1)
        self.assertEqual(len({r["path"] for r in results}), 1)
        self.assertEqual(len(list((self.planning / "sessions/active").glob("*.md"))), 1)

    def test_safe_event_trace_omits_all_input_and_output(self):
        opened = self.result("ensure")
        a = self.result("observe", SOURCE, None, "--event", "tool.returned",
                        "--tool", "Bash;cat-private-key")
        b = self.result("observe", SOURCE, None, "--event", "tool.failed", "--tool", "Read")
        self.assertEqual(a["event_id"], "E00001")
        self.assertEqual(b["event_id"], "E00002")
        trace = Path(a["trace"])
        self.assertEqual(trace, Path(b["trace"]))
        rows = [json.loads(x) for x in trace.read_text().splitlines()]
        self.assertEqual(rows[0]["tool_class"], "other")
        self.assertEqual(rows[1]["tool_class"], "Read")
        self.assertEqual(rows[0]["outcome"], "not_verified")
        self.assertNotIn("private-key", trace.read_text())
        self.assertEqual(trace.stat().st_mode & 0o777, 0o600)
        self.assertEqual(opened["uid"], a["uid"])

    def test_session_end_only_observes_does_not_close(self):
        note = self.result("ensure")
        self.result("observe", SOURCE, None, "--event", "session.ended")
        self.assertTrue(Path(note["path"]).is_file())
        self.assertEqual(self.result("ensure")["status"], "RESUMED")

    def test_native_codex_json_is_authoritative(self):
        key = hashlib.sha256(("demo" + "\0" + self.sid).encode()).hexdigest()[:32]
        native = self.planning / "sessions/work" / (key + ".json")
        native.parent.mkdir(exist_ok=True)
        native.write_bytes(b"private native data; not valid JSON")
        x = self.result("ensure", "codex-generic")
        self.assertEqual(x["status"], "NATIVE_SESSION_OWNED")
        self.assertFalse((self.planning / "sessions/active").exists())
        y = self.result("observe", "codex-generic", None, "--event", "tool.returned")
        self.assertEqual(y["status"], "NATIVE_SESSION_OWNED")
        self.assertEqual(native.read_bytes(), b"private native data; not valid JSON")

    def test_different_external_session_has_different_uid(self):
        first = self.result("ensure")
        second = self.result("ensure", SOURCE, "a-second-session")
        self.assertNotEqual(first["uid"], second["uid"])
        self.assertNotEqual(first["path"], second["path"])

    def test_no_tool_event_without_session(self):
        result = self.result("observe", SOURCE, None, "--event", "tool.failed")
        self.assertEqual(result["status"], "NO_SESSION_RECORD")
        self.assertFalse((self.home / ".local").exists())

    def test_reject_traversal_and_symlink_trace_folder(self):
        bad = self.command("ensure", SOURCE, "../outside")
        self.assertEqual(bad.returncode, 2)
        note = self.result("ensure")
        state = self.home / ".local/state/evm"
        state.mkdir(parents=True)
        (state / "traces").symlink_to(self.home / "project")
        failed = self.command("observe", SOURCE, None, "--event", "tool.returned")
        self.assertEqual(failed.returncode, 2)
        self.assertFalse((self.home / "project/demo").exists())
        self.assertTrue(Path(note["path"]).is_file())

    def test_evm_wrapper_preserves_existing_claude_hook_and_sanitizes(self):
        memory = self.home / ".config/opencode/memory"
        memory.mkdir(parents=True)
        event = {"hook_event_name": "SessionStart",
                 "session_id": self.sid, "cwd": str(self.home)}
        proc = subprocess.run([sys.executable, str(EVM), "hook", "start",
                               "--source", "claude-code"], input=json.dumps(event),
                              capture_output=True, text=True, env=self.env, timeout=20)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Session Record:", proc.stdout)
        self.assertNotIn("not_saved", proc.stdout)
        payload = {"hook_event_name": "PostToolUse", "session_id": self.sid,
                   "cwd": str(self.home), "tool_name": "Bash",
                   "tool_input": {"command": "cat /secrets"},
                   "tool_response": {"stdout": "TOP-SECRET", "exit_code": 0}}
        p = subprocess.run([sys.executable, str(EVM), "hook", "tool",
                            "--source", "claude-code"], input=json.dumps(payload),
                           capture_output=True, text=True, env=self.env, timeout=20)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout, "")
        traces = list((self.home / ".local/state/evm/traces/personal").glob("*.jsonl"))
        self.assertEqual(len(traces), 1)
        self.assertNotIn("TOP-SECRET", traces[0].read_text())
        self.assertNotIn("/secrets", traces[0].read_text())

    def test_claude_hook_install_opt_in_and_idempotent(self):
        conf = self.home / ".claude"
        conf.mkdir()
        target = conf / "settings.json"
        target.write_text(json.dumps({"hooks": {
            "SessionStart": [{"hooks": [{"type": "command", "command": "echo existing"}]}]
        }}))
        args = [sys.executable, str(INSTALL), "--session-hooks"]
        for _ in (0, 1):
            p = subprocess.run(args, capture_output=True, text=True, env=self.env, timeout=20)
            self.assertEqual(p.returncode, 0, p.stderr)
        settings = json.loads(target.read_text())
        self.assertIn("echo existing", json.dumps(settings))
        for event in ("SessionStart", "PostToolUse", "PostToolUseFailure", "SessionEnd"):
            scripts = json.dumps(settings["hooks"][event])
            self.assertEqual(scripts.count("evm hook "), 1)
        self.assertEqual(len([e for e in settings["hooks"]["SessionStart"]
                              if "evm hook" in json.dumps(e)]), 1)


if __name__ == "__main__":
    unittest.main()
