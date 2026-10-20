import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
import client_dispatch as chat
_read_cli_version = chat._cli_version


class DispatchTests(unittest.TestCase):
    def setUp(self):
        self.snapshot = SimpleNamespace(workshop_root='C:/workshop', payload={'items': [
            {'id': 'agentes:review', 'name': 'review', 'section': 'Agentes'}]})
        self.find = lambda client, root: {'claude': 'C:/bin/claude.exe',
            'codex': 'C:/bin/codex.exe', 'gemini': 'C:/bin/gemini.cmd'}.get(client)
        self.body = dict(client='claude', model='sonnet', mode='text-only',
                         destination='new-request', message='hello')
        version = patch.object(chat, '_cli_version', return_value=(2, 1, 270))
        version.start()
        self.addCleanup(version.stop)

    def test_registry_access_is_unknown_and_unverified_adapters_unavailable(self):
        clients = chat.registry(self.snapshot, self.find)['clients']
        self.assertTrue(clients[0]['available'])
        self.assertEqual(clients[0]['models'][0]['access'], 'unknown')
        self.assertTrue(all(not c['available'] for c in clients[1:]))

    def test_old_native_cli_is_unavailable(self):
        with patch.object(chat, '_cli_version', return_value=(2, 1, 258)):
            client = chat.registry(self.snapshot, self.find)['clients'][0]
        self.assertFalse(client['available'])
        self.assertEqual(client['version'], '2.1.258')
        self.assertIn('2.1.259', client['reason'])

    @patch.object(chat.subprocess, 'run', return_value=type('Result', (), {'returncode': 0,
        'stdout': b'2.1.270 (Claude Code)\n'})())
    def test_cli_version_check_uses_fixed_noninteractive_command(self, run):
        self.assertEqual(_read_cli_version('C:/bin/claude.exe'), (2, 1, 270))
        self.assertEqual(run.call_args.args[0], ['C:/bin/claude.exe', '--version'])
        self.assertEqual(run.call_args.kwargs['stdin'], chat.subprocess.DEVNULL)
        self.assertFalse(run.call_args.kwargs['shell'])

    @patch.object(chat, '_run', return_value=(0, '{"result":"answer"}', False))
    def test_content_stdin_and_selected_settings(self, run):
        self.body.update(message='$(bad) & secret text', context='document', agent='agentes:review')
        result = chat.dispatch(self.body, self.snapshot, self.find, role_text='role')
        argv, stdin = run.call_args.args
        self.assertTrue(result['ok'])
        self.assertEqual(result['response'], 'answer')
        self.assertNotIn(self.body['message'], argv)
        self.assertIn(self.body['message'], stdin)
        self.assertIn('document', stdin)
        self.assertIn('role', stdin)
        self.assertIn('--safe-mode', argv)
        self.assertIn('--strict-mcp-config', argv)
        self.assertEqual(argv[argv.index('--tools') + 1], '')

    @patch.object(chat, '_run')
    def test_reject_invalid_combinations_and_oversize(self, run):
        for changes in ({'model': 'invented'}, {'mode': 'bypassPermissions'},
                        {'destination': 'existing-terminal'}, {'client': 'codex'},
                        {'agent': 'agentes:review'}, {'message': 'a' * (chat.MAX_TEXT + 1)}):
            with self.subTest(changes=changes):
                self.assertFalse(chat.dispatch(dict(self.body, **changes), self.snapshot, self.find)['ok'])
        run.assert_not_called()

    @patch.object(chat, '_run', return_value=(1, '', True))
    def test_timeout_is_uncertain_and_not_retried(self, run):
        result = chat.dispatch(self.body, self.snapshot, self.find)
        self.assertEqual(result['status'], 'uncertain')
        self.assertEqual(run.call_count, 1)

    @patch.object(chat, '_run', return_value=(1, 'sensitive error text', False))
    def test_failure_does_not_expose_raw_diagnostics(self, run):
        result = chat.dispatch(self.body, self.snapshot, self.find)
        self.assertEqual(result['status'], 'failed')
        self.assertNotIn('sensitive', json.dumps(result))

    @patch.object(chat, '_run')
    def test_concurrent_rejection(self, run):
        chat._gate.acquire()
        try:
            self.assertEqual(chat.dispatch(self.body, self.snapshot, self.find)['status'], 'rejected')
        finally:
            chat._gate.release()
        run.assert_not_called()

    def test_pipe_transport_uses_stdin(self):
        code, output, uncertain = chat._run([sys.executable, '-c',
            'import sys; print(sys.stdin.read())'], 'stdin-only')
        self.assertEqual(code, 0)
        self.assertEqual(output.strip(), 'stdin-only')
        self.assertFalse(uncertain)

    def test_output_limit_terminates_process(self):
        with patch.object(chat, 'MAX_OUTPUT', 32):
            _, output, uncertain = chat._run([sys.executable, '-c',
                'print("x" * 10000)'], '')
        self.assertTrue(uncertain)
        self.assertLessEqual(len(output.encode()), 32)


if __name__ == '__main__':
    unittest.main()
