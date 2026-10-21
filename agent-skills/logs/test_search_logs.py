#!/usr/bin/env python3
"""Reader side of the log contract: search_logs.py finds what master_logger wrote.

Lives beside the reader because the logs skill ships (or not) separately from
the logger. Drives the real logger as a subprocess into a temp CLAUDE_LOG_ROOT.

Run: python3 agent-skills/logs/test_search_logs.py
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
LOGGER_DIR = REPO / 'claude' / 'hooks' / 'logger'
MASTER = LOGGER_DIR / 'master_logger.py'
SEARCH = HERE / 'search_logs.py'


class ReaderContract(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        tmp = Path(self._tmp.name).resolve()
        self.repo = tmp / 'proj'
        (self.repo / 'src').mkdir(parents=True)
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        self.env = {k: v for k, v in os.environ.items() if k != 'CLAUDE_PROJECT_DIR'}
        self.env['CLAUDE_LOG_ROOT'] = str(tmp / 'logroot')

    def tearDown(self):
        self._tmp.cleanup()

    def event(self, name, **kw):
        payload = {'hook_event_name': name, 'session_id': 's1', 'cwd': str(self.repo), **kw}
        p = subprocess.run([sys.executable, str(MASTER)], input=json.dumps(payload),
                           capture_output=True, text=True, env=self.env)
        self.assertEqual(p.returncode, 0, p.stderr)

    def search(self, *args, cwd=None):
        p = subprocess.run([sys.executable, str(SEARCH), *args], cwd=cwd or self.repo,
                           capture_output=True, text=True, env=self.env)
        return json.loads(p.stdout)

    def test_finds_logger_records_local_and_global(self):
        self.event('SessionStart', source='startup')
        self.event('PreToolUse', tool_name='Bash', tool_input={'command': 'echo zanzibar-marker'})
        self.event('PostToolUseFailure', tool_name='Bash', tool_input={'command': 'false'},
                   error='quokka-failure exit 1')
        local = self.search('search', 'zanzibar-marker', cwd=self.repo / 'src')
        self.assertEqual(local.get('total_matches'), 1, local)
        self.assertEqual(local['matches'][0]['excerpts'][0]['content_type'], 'tool_command')
        err = self.search('search', 'quokka-failure')
        self.assertEqual(err['matches'][0]['excerpts'][0]['content_type'], 'tool_error')
        self.assertEqual(self.search('global', 'zanzibar-marker')['total_project_matches'], 1)
        # Control: a term never logged finds nothing.
        self.assertEqual(self.search('search', 'qqq-never-logged')['total_matches'], 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
