"""Installer regression tests. No real Codex, auth, model, or privilege calls."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


LAUNCHER = Path(__file__).resolve().parents[1] / 'harness' / 'tools' / 'evm-codex-go'


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='evm-go-test-', dir='/tmp')
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        self.log = self.root / 'calls'
        self.rule = self.root / 'codex' / 'rules' / 'evm-privileged.rules'
        self.env = dict(os.environ, HOME=str(self.root), CODEX_HOME=str(self.root / 'codex'),
                        PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                        TEST_LOG=str(self.log), TEST_RULE=str(self.rule))
        self.env.pop('TEST_FAIL_CHECK', None)
        for name, text in {
            'id': '#!/bin/sh\nprintf "1000\\n"\n',
            'codex': '''#!/bin/sh
printf '%s\\n' "$*" >> "$TEST_LOG"
if [ "$1" = execpolicy ]; then
  if [ -e "$TEST_RULE" ]; then
    printf 'published\\n' >> "$TEST_LOG"
  else
    printf 'unpublished\\n' >> "$TEST_LOG"
  fi
  [ "${TEST_FAIL_CHECK:-0}" = 0 ] || exit 23
  printf '{"decision":"prompt"}\\n'
fi
''',
        }.items():
            path = bin_dir / name
            path.write_text(text)
            path.chmod(0o700)

    def run_launcher(self, *args):
        return subprocess.run(['bash', str(LAUNCHER), *args], env=self.env,
                              text=True, capture_output=True)

    def test_install_checks_before_publish(self):
        result = self.run_launcher('--install')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.rule.is_file())
        self.assertIn('unpublished', self.log.read_text().splitlines())
        self.assertNotIn('published', self.log.read_text().splitlines())

    def test_failed_check_leaves_no_rule_install(self):
        self.env['TEST_FAIL_CHECK'] = '1'
        result = self.run_launcher('--install')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.rule.exists())

    def test_failed_check_leaves_no_rule_launch(self):
        self.env['TEST_FAIL_CHECK'] = '1'
        result = self.run_launcher()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.rule.exists())
        self.assertNotIn('--sandbox', self.log.read_text())

    def test_existing_different_rule_preserved(self):
        self.rule.parent.mkdir(parents=True)
        self.rule.write_text('# owner policy\n')
        result = self.run_launcher('--install')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.rule.read_text(), '# owner policy\n')

    def test_repeat_install_preserves_file(self):
        self.assertEqual(self.run_launcher('--install').returncode, 0)
        before = (self.rule.stat().st_ino, self.rule.read_bytes())
        self.assertEqual(self.run_launcher('--install').returncode, 0)
        self.assertEqual((self.rule.stat().st_ino, self.rule.read_bytes()), before)

    def test_launch_keeps_safe_flags(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text()
        self.assertIn('--sandbox read-only --ask-for-approval on-request', calls)
        self.assertIn('approvals_reviewer="user"', calls)

    def test_invalid_args_do_not_create_rule(self):
        result = self.run_launcher('--wrong')
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.rule.exists())
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
