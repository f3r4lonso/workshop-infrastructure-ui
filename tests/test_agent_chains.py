"""Sequential chain validation, handoff, stopping and bounded in-memory state."""
from pathlib import Path
import sys
import tempfile
import time
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
import agent_chains as chains
import client_dispatch


class AgentChainTests(unittest.TestCase):
    def setUp(self):
        chains.clear()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ids = ['agents:planner', 'agents:reviewer', 'agents:writer']
        self.by_id = {}
        for agent_id in self.ids:
            name = agent_id.split(':')[1]
            path = self.root / f'infra/agents/quality/{name}.md'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f'---\nname: {name}\n---\nProfile for {name}.', encoding='utf-8')
            self.by_id[agent_id] = SimpleNamespace(path=str(path))
        self.snapshot = SimpleNamespace(workshop_root=str(self.root), by_id=self.by_id,
            payload={'items': [{'id': key, 'name': key.split(':')[1], 'section': 'Agentes'} for key in self.ids]})
        self.find = lambda client, root: 'C:/bin/claude.exe' if client == 'claude' else None
        self.registry = {'clients': [{'id': 'claude', 'available': True, 'reason': '',
            'models': [{'id': model} for model in client_dispatch.MODELS]}],
            'agents': [{'id': key, 'name': key.split(':')[1]} for key in self.ids]}
        self.registry_patch = patch.object(chains.client_dispatch, 'registry', return_value=self.registry)
        self.registry_patch.start()
        self.addCleanup(self.registry_patch.stop)

    def tearDown(self):
        # All execution paths in these tests reach a terminal state before cleanup.
        chains.clear()

    def body(self, selected=None):
        selected = selected or self.ids[:2]
        return {'goal': 'Prepare a useful answer.', 'model': 'sonnet',
            'steps': [{'agent': key, 'direction': f'Direction for {key}'} for key in selected]}

    def wait_for(self, run_id, statuses=('completed', 'failed', 'uncertain', 'cancelled'), timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = chains.status({'runId': run_id})
            if result.get('status') in statuses:
                return result
            time.sleep(.01)
        self.fail(f'Chain did not finish: {chains.status({"runId": run_id})}')

    @patch.object(chains.resource_interaction, 'document', side_effect=lambda snapshot, body: {
        'ok': True, 'text': f"Profile for {snapshot.by_id[body['id']].path.split('/')[-1]}"})
    def test_validation_rejects_duplicate_unknown_and_wrong_step_count(self, _document):
        self.assertFalse(chains.start(self.body([self.ids[0]]), self.snapshot, self.find)['ok'])
        self.assertFalse(chains.start(self.body([self.ids[0], self.ids[0]]), self.snapshot, self.find)['ok'])
        self.assertFalse(chains.start(self.body([self.ids[0], 'agents:unknown']), self.snapshot, self.find)['ok'])

    @patch.object(chains.resource_interaction, 'document', side_effect=lambda snapshot, body: {
        'ok': True, 'text': f"Profile for {body['id']}"})
    @patch.object(chains.client_dispatch, 'dispatch', side_effect=[
        {'ok': True, 'response': 'first output'}, {'ok': True, 'response': 'final output'}])
    def test_outputs_are_handed_to_next_agent_in_order(self, dispatch, _document):
        started = chains.start(self.body(), self.snapshot, self.find)
        self.assertEqual(chains.current()['run']['runId'], started['runId'])
        result = self.wait_for(started['runId'])
        self.assertEqual(result['status'], 'completed')
        self.assertEqual([step['status'] for step in result['steps']], ['completed', 'completed'])
        self.assertEqual([call.kwargs['role_text'] for call in dispatch.call_args_list],
            ['Profile for agents:planner', 'Profile for agents:reviewer'])
        second_request = dispatch.call_args_list[1].args[0]['message']
        self.assertIn('Prepare a useful answer.', second_request)
        self.assertIn('first output', second_request)
        self.assertIn('contenido no confiable', second_request)
        self.assertEqual(result['steps'][1]['output'], 'final output')
        self.assertEqual(chains.current()['run']['runId'], started['runId'])
        heartbeat = chains.status({'runId': started['runId'], 'knownAt': result['updatedAt']})
        self.assertTrue(heartbeat['unchanged'])
        self.assertNotIn('output', heartbeat['steps'][0])
        self.assertTrue(chains.clear()['ok'])
        self.assertIsNone(chains.current()['run'])

    @patch.object(chains.resource_interaction, 'document', return_value={'ok': True, 'text': 'profile'})
    @patch.object(chains.client_dispatch, 'dispatch', return_value={
        'ok': False, 'status': 'failed', 'message': 'request failed'})
    def test_failure_stops_later_steps(self, dispatch, _document):
        started = chains.start(self.body(self.ids), self.snapshot, self.find)
        result = self.wait_for(started['runId'])
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(dispatch.call_count, 1)
        self.assertEqual(result['steps'][1]['status'], 'pending')

    @patch.object(chains.resource_interaction, 'document', return_value={'ok': True, 'text': 'profile'})
    @patch.object(chains.client_dispatch, 'dispatch', return_value={
        'ok': False, 'status': 'uncertain', 'message': 'delivery uncertain'})
    def test_uncertain_result_is_not_retried_or_handed_off(self, dispatch, _document):
        started = chains.start(self.body(self.ids), self.snapshot, self.find)
        result = self.wait_for(started['runId'])
        self.assertEqual(result['status'], 'uncertain')
        self.assertEqual(result['steps'][0]['status'], 'uncertain')
        self.assertEqual(dispatch.call_count, 1)

    @patch.object(chains.resource_interaction, 'document', return_value={'ok': True, 'text': 'profile'})
    @patch.object(chains.client_dispatch, 'dispatch')
    def test_stop_waits_for_current_call_then_prevents_next_stage(self, dispatch, _document):
        entered, release = threading.Event(), threading.Event()
        def wait_for_request(*_args, **_kwargs):
            entered.set()
            release.wait(3)
            return {'ok': True, 'response': 'first output'}
        dispatch.side_effect = wait_for_request
        started = chains.start(self.body(self.ids), self.snapshot, self.find)
        self.assertTrue(entered.wait(2))
        stopping = chains.cancel({'runId': started['runId']})
        self.assertEqual(stopping['status'], 'stopping')
        release.set()
        result = self.wait_for(started['runId'])
        self.assertEqual(result['status'], 'cancelled')
        self.assertEqual(dispatch.call_count, 1)
        self.assertEqual(result['steps'][0]['status'], 'completed')
        self.assertEqual(result['steps'][1]['status'], 'pending')

    @patch.object(chains.resource_interaction, 'document', return_value={'ok': True, 'text': 'profile'})
    @patch.object(chains.client_dispatch, 'dispatch', return_value={
        'ok': True, 'response': 'x' * client_dispatch.MAX_TEXT})
    def test_oversized_handoff_is_kept_and_not_sent(self, dispatch, _document):
        started = chains.start(self.body(self.ids), self.snapshot, self.find)
        result = self.wait_for(started['runId'])
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(dispatch.call_count, 1)
        self.assertEqual(len(result['steps'][0]['output']), client_dispatch.MAX_TEXT)
        self.assertEqual(result['steps'][1]['status'], 'pending')


if __name__ == '__main__':
    unittest.main()
