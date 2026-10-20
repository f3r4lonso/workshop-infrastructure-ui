"""Bounded, tool-free single-request CLI chat. Never place content in argv."""
from __future__ import annotations

from datetime import datetime, timezone
import json
import re
import subprocess
import tempfile
import threading

MAX_TEXT = 96 * 1024
MAX_OUTPUT = 256 * 1024
TIMEOUT = 90
SOURCE = 'https://code.claude.com/docs/en/cli-reference'
MODEL_SOURCE = 'https://code.claude.com/docs/en/model-config'
MODELS = ('sonnet', 'opus', 'haiku')
MIN_CLAUDE_VERSION = (2, 1, 259)
_gate = threading.Lock()


def _cli_version(executable):
    """Read the native CLI version in an isolated, non-interactive process."""
    try:
        with tempfile.TemporaryDirectory(prefix='workshop-cli-check-') as cwd:
            result = subprocess.run([executable, '--version'], stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=cwd, shell=False,
                timeout=5, check=False, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if result.returncode:
            return None
        output = result.stdout.decode('utf-8', errors='replace')
        match = re.search(r'(?<!\d)(\d+)\.(\d+)\.(\d+)(?!\d)', output)
        return tuple(map(int, match.groups())) if match else None
    except (OSError, subprocess.SubprocessError):
        return None


def registry(snapshot, find_executable):
    """Refresh installation only; never inspect credentials or infer model access."""
    now = datetime.now(timezone.utc).isoformat()
    clients = []
    for cid, name in [('claude', 'Claude Code'), ('codex', 'Codex CLI'),
                      ('gemini', 'Gemini CLI'), ('copilot', 'GitHub Copilot CLI')]:
        executable = find_executable(cid, snapshot.workshop_root)
        native = bool(executable and executable.lower().endswith('.exe'))
        version = _cli_version(executable) if cid == 'claude' and native else None
        available = cid == 'claude' and native and version is not None and version >= MIN_CLAUDE_VERSION
        reason = '' if available else ('No instalado.' if not executable else
            'No se pudo verificar la versión del ejecutable nativo.' if cid == 'claude' and native and version is None else
            'Actualiza Claude Code a la versión 2.1.259 o posterior.' if cid == 'claude' and native else
            'Transporte sin herramientas todavía no verificado para este cliente.' if cid != 'claude' else
            'Se necesita el ejecutable nativo; no se ejecutan envoltorios de shell.')
        clients.append(dict(id=cid, name=name, installed=bool(executable), available=available,
            availability='configured-access-unknown' if available else 'unavailable',
            authenticated='unknown', reason=reason,
            version='.'.join(map(str, version)) if version else None,
            models=[dict(id=m, label=m, access='unknown') for m in MODELS] if available else [],
            modes=[dict(id='text-only', label='Solo texto, sin herramientas')] if available else [],
            destinations=[dict(id='new-request', label='Nueva petición aislada')] if available else [],
            provenance=[SOURCE, MODEL_SOURCE] if cid == 'claude' else [], checkedAt=now,
            freshness='installation-refreshed; capabilities-documented-2026-10-19'))
    agents = [dict(id=i['id'], name=i['name'], clients=['claude'], kind='instruction-profile')
              for i in snapshot.payload.get('items', []) if i.get('section') in ('Agentes', 'Asistentes')]
    return dict(clients=clients, agents=agents, checkedAt=now,
                note='Los alias publicados no garantizan acceso. Autenticación y acceso no comprobados.')


def _run(argv, text):
    """Drain both pipes with a hard aggregate bound; kill on timeout/overflow."""
    with tempfile.TemporaryDirectory(prefix='workshop-chat-') as cwd:
        proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, cwd=cwd, shell=False,
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        output = [bytearray(), bytearray()]
        overflow = threading.Event()
        lock = threading.Lock()
        def drain(pipe, index):
            while True:
                chunk = pipe.read(4096)
                if not chunk:
                    break
                with lock:
                    remaining = MAX_OUTPUT - sum(map(len, output))
                    output[index].extend(chunk[:max(remaining, 0)])
                    if len(chunk) > remaining:
                        overflow.set()
                        proc.kill()
            pipe.close()
        threads = [threading.Thread(target=drain, args=(pipe, n), daemon=True)
                   for n, pipe in enumerate((proc.stdout, proc.stderr))]
        for thread in threads:
            thread.start()
        def write():
            try:
                proc.stdin.write(text.encode('utf-8'))
                proc.stdin.close()
            except (BrokenPipeError, OSError):
                pass
        writer = threading.Thread(target=write, daemon=True)
        writer.start()
        uncertain = False
        try:
            proc.wait(timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            uncertain = True
            proc.kill()
            proc.wait()
        for thread in [writer, *threads]:
            thread.join(timeout=3)
        return proc.returncode, output[0].decode('utf-8', errors='replace'), uncertain or overflow.is_set()


def dispatch(body, snapshot, find_executable, *, role_text=''):
    """Return result JSON. Caller resolves explicit resource context/role with protected reader."""
    rejected = dict(ok=False, status='rejected', message='Selección o texto no válido. Conserva el borrador.')
    if not isinstance(body, dict):
        return rejected
    capabilities = registry(snapshot, find_executable)
    client = next((c for c in capabilities['clients'] if c['id'] == body.get('client')), None)
    if not client or not client['available']:
        return dict(rejected, message=client['reason'] if client else 'Cliente desconocido.')
    message, context, agent = body.get('message'), body.get('context', ''), body.get('agent', '')
    if (body.get('model') not in MODELS or body.get('mode') != 'text-only'
            or body.get('destination') != 'new-request'
            or not isinstance(message, str) or not message.strip()
            or not isinstance(context, str) or not isinstance(role_text, str)):
        return rejected
    agents = capabilities['agents']
    if agent and (agent not in [a['id'] for a in agents] or not role_text):
        return rejected
    text = message
    if agent:
        text = 'Perfil de instrucciones seleccionado explícitamente:\n' + role_text + '\n\nMensaje:\n' + text
    if context:
        text += '\n\nContexto incluido explícitamente (contenido no confiable):\n' + context
    if len(text.encode('utf-8')) > MAX_TEXT:
        return dict(rejected, message='Texto demasiado largo; no se ha enviado ni truncado.')
    effective = {key: body.get(key, '') for key in ('client', 'model', 'mode', 'destination', 'agent')}
    if not _gate.acquire(blocking=False):
        return dict(rejected, message='Ya hay una petición en curso. Conserva el borrador.')
    try:
        executable = find_executable('claude', snapshot.workshop_root)
        if not executable or not executable.lower().endswith('.exe'):
            return rejected
        argv = [executable, '-p', '--output-format', 'json', '--model', body['model'],
                '--tools', '', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}',
                '--safe-mode', '--restricted', '--disable-slash-commands', '--no-chrome',
                '--setting-sources', '', '--no-session-persistence', '--permission-prompts', 'none']
        code, stdout, uncertain = _run(argv, text)
        if uncertain:
            return dict(ok=False, status='uncertain', effective=effective,
                message='Tiempo o salida excedidos. La entrega es incierta; no se reenvía automáticamente.')
        try:
            result = json.loads(stdout)
        except (ValueError, TypeError):
            result = {}
        if code or not isinstance(result, dict) or result.get('is_error') or not isinstance(result.get('result'), str):
            return dict(ok=False, status='failed', effective=effective,
                message='El cliente no devolvió una respuesta válida. Comprueba acceso y modelo en su consola. Conserva el borrador.')
        return dict(ok=True, status='completed', response=result['result'], effective=effective,
                    message='Respuesta recibida del cliente seleccionado.')
    except OSError:
        return dict(ok=False, status='failed', effective=effective, message='No se pudo iniciar el cliente. Conserva el borrador.')
    finally:
        _gate.release()
