"""Read-only startup checks; every Git mutation is confined to /tmp fixtures."""
import contextlib
import importlib.machinery
import importlib.util
import io
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("evm_source_test", str(ROOT / "harness/tools/evm"))
spec = importlib.util.spec_from_loader(loader.name, loader)
evm = importlib.util.module_from_spec(spec); loader.exec_module(evm)


class GitSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="evm-source-", dir="/tmp")
        self.base = Path(self.temp.name).resolve(); self.seed = self.base / "seed"
        self.remote = self.base / "remote.git"; self.work = self.base / "work"
        self.g(self.base, "init", "-b", "main", str(self.seed))
        self.commit(self.seed, "first")
        self.g(self.base, "clone", "--bare", str(self.seed), str(self.remote))
        self.g(self.base, "clone", str(self.remote), str(self.work))

    def tearDown(self): self.temp.cleanup()

    def g(self, where, *args):
        where = Path(where).resolve(); assert where.is_relative_to(Path("/tmp"))
        return subprocess.run(["git", "-C", str(where), "-c", "core.hooksPath=/dev/null",
            "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", *args],
            check=True, capture_output=True, text=True).stdout.strip()

    def commit(self, where, text):
        assert where.resolve().is_relative_to(Path("/tmp"))
        (where / "file.txt").write_text(text)
        self.g(where, "add", "--", "file.txt"); self.g(where, "commit", "-m", text)
        return self.g(where, "rev-parse", "HEAD")

    def advance(self, fetch=True):
        remote_sha = self.commit(self.seed, "remote update")
        assert self.remote.is_absolute() and self.remote.is_relative_to(Path("/tmp"))
        self.g(self.seed, "push", str(self.remote), "main")
        if fetch: self.g(self.work, "fetch", "origin", "main")
        return remote_sha

    def state(self, **kwargs): return evm.git_source_state(self.work, workdir=kwargs.get("workdir", self.work))

    def test_current(self):
        value = self.state(); self.assertEqual(value["status"], "current"); self.assertFalse(value["blocked"])

    def test_behind(self):
        self.advance(); value = self.state()
        self.assertEqual(value["status"], "behind"); self.assertEqual(value["behind"], 1); self.assertTrue(value["blocked"])

    def test_ahead(self):
        self.commit(self.work, "local update"); value = self.state()
        self.assertEqual(value["status"], "ahead"); self.assertEqual(value["ahead"], 1); self.assertFalse(value["blocked"])

    def test_diverged(self):
        self.commit(self.work, "local update"); self.advance(); value = self.state()
        self.assertEqual(value["status"], "diverged"); self.assertTrue(value["blocked"])

    def test_remote_object_not_fetched(self):
        sha = self.advance(fetch=False); value = self.state()
        self.assertEqual(value["remote_sha"], sha); self.assertEqual(value["status"], "unknown"); self.assertTrue(value["blocked"])

    def test_dirty_is_reported_without_writing_or_fetching(self):
        (self.work / "file.txt").write_text("pending edit")
        before = self.g(self.work, "status", "--porcelain")
        original = subprocess.run; commands = []
        def observe(command, **kwargs): commands.append(command); return original(command, **kwargs)
        with patch.object(evm.subprocess, "run", side_effect=observe): value = self.state()
        self.assertEqual(value["dirty"], 1); self.assertEqual(self.g(self.work, "status", "--porcelain"), before)
        self.assertFalse(any(set(c) & {"fetch", "pull", "checkout", "reset", "push"} for c in commands))

    def test_worktree_checked_against_main_trunk(self):
        sha = self.advance(); feature = self.base / "feature"
        self.g(self.work, "worktree", "add", "-b", "feature", str(feature), sha)
        value = self.state(workdir=feature)
        self.assertEqual(value["branch"], "main"); self.assertEqual(value["status"], "current")
        self.assertEqual(Path(value["repo"]), feature)

    def test_remote_unavailable_does_not_claim_current(self):
        self.g(self.work, "remote", "set-url", "origin", str(self.base / "unavailable"))
        self.assertEqual(self.state()["status"], "unknown"); self.assertTrue(self.state()["blocked"])

    def test_no_origin_is_explicit(self):
        self.g(self.work, "remote", "remove", "origin")
        value = self.state(); self.assertEqual(value["status"], "unknown"); self.assertIn("origin", value["reason"])

    def test_network_timeout_is_bounded(self):
        original = subprocess.run
        def timeout(command, **kwargs):
            if "ls-remote" in command:
                self.assertLessEqual(kwargs["timeout"], 5)
                self.assertEqual(kwargs["env"]["GIT_TERMINAL_PROMPT"], "0")
                raise subprocess.TimeoutExpired(command, kwargs["timeout"])
            return original(command, **kwargs)
        with patch.object(evm.subprocess, "run", side_effect=timeout):
            value = self.state(); self.assertEqual(value["status"], "unknown"); self.assertTrue(value["blocked"])

    def test_boot_calls_check_in_full_and_brief_modes(self):
        self.advance()
        for brief in (False, True):
            with patch.object(evm, "resolve", return_value=(self.work, None, None)), \
                 patch.object(evm, "harness_off", return_value=False), \
                 patch.object(evm, "first_task_block", return_value=[]), \
                 patch.object(evm, "last_shift_line", return_value=None), \
                 patch.object(evm, "threshold_lines", return_value=[]), \
                 patch.object(evm, "update_notice", return_value=[]), contextlib.redirect_stdout(io.StringIO()) as output:
                code = evm.boot("fixture", "solo", brief)
            self.assertEqual(code, 1); self.assertIn("origin/main", output.getvalue()); self.assertIn("СТОП", output.getvalue())


if __name__ == "__main__": unittest.main()
