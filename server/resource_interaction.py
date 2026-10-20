"""Bounded canonical document editing and reuse of the local reader pipeline."""
from __future__ import annotations

import hashlib
import base64
import binascii
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading

import workshop_data

READER_ROOT = Path(__file__).resolve().parents[2] / 'ai-reading-assistant'
MAX_TEXT_BYTES = 1024 * 1024
MAX_FILE_BYTES = 20 * 1024 * 1024
_save_lock = threading.Lock()
_BLOCKED = {'.aws', '.ssh', '.agents', '__pycache__', 'dist', 'build', 'pilot-results',
            'secrets', 'credentials', 'config', 'configs'}


class ResourceError(Exception):
    pass


def safe_path(snapshot, body):
    root = Path(snapshot.workshop_root).absolute()
    if body.get('id'):
        item = snapshot.by_id.get(body['id']) if isinstance(body['id'], str) else None
        if item is None:
            raise ResourceError('Recurso desconocido. Pulsa Actualizar.')
        path = Path(item.path).absolute()
    else:
        relative = body.get('path')
        if not isinstance(relative, str) or not relative or len(relative) > 1000:
            raise ResourceError('Indica una ruta relativa del Workshop.')
        parts = relative.replace('\\', '/').split('/')
        if any(p in ('', '.', '..') or ':' in p for p in parts) or relative.startswith(('/', '\\')):
            raise ResourceError('Ruta no permitida.')
        path = root.joinpath(*parts)
    try:
        relative = path.relative_to(root)
    except ValueError:
        raise ResourceError('El archivo debe estar dentro del Workshop.') from None
    if (not relative.parts or any(p.startswith('.') or p.lower() in _BLOCKED for p in relative.parts)
            or workshop_data.is_excluded_path(str(path))
            or workshop_data.is_linked_path(str(path), str(root))):
        raise ResourceError('Archivo protegido, generado o enlazado: acceso no permitido.')
    if path.resolve() != path or not path.is_file():
        raise ResourceError('El archivo no existe o no es accesible.')
    return path, relative


def eligible(relative):
    parts = [p.lower() for p in relative.parts]
    if relative.suffix.lower() not in ('.md', '.txt'):
        return False
    if parts[0] == 'infra' and len(parts) >= 3 and parts[1] in ('docs', 'tasks', 'agents', 'skills'):
        return True
    return (len(parts) >= 3 and parts[0] == 'applications'
            and (parts[2] == 'docs' or (len(parts) == 3 and parts[2] == 'readme.md')))


def read_bytes(path, limit):
    with path.open('rb') as source:
        raw = source.read(limit + 1)
    if len(raw) > limit:
        raise ResourceError(f'El archivo supera el límite de {limit // 1024} KB; no se ha truncado.')
    return raw


def version(raw):
    return hashlib.sha256(raw).hexdigest()


def document(snapshot, body):
    path, relative = safe_path(snapshot, body)
    if path.suffix.lower() not in ('.md', '.markdown', '.txt'):
        raise ResourceError('Solo se pueden editar documentos de texto compatibles; usa Leer para DOCX.')
    raw = read_bytes(path, MAX_TEXT_BYTES)
    try:
        text = raw.decode('utf-8-sig')
    except UnicodeError:
        raise ResourceError('La edición requiere texto UTF-8.') from None
    if '\x00' in text:
        raise ResourceError('El archivo parece binario.')
    editable = eligible(relative)
    return dict(ok=True, text=text, version=version(raw), editable=editable, path=str(relative),
                reason='' if editable else 'Solo lectura: política, configuración o recurso fuera de las áreas editables.')


def _metadata(text):
    # Preserve the whole header, including unknown/duplicate keys and whitespace.
    # A partial field parser can disagree with the adapter's parser and permit identity changes.
    match = re.match(r'\A\ufeff?---[^\S\n]*\n.*?\n---[^\S\n]*(?:\n|\Z)',
                     text.replace('\r\n', '\n'), re.S)
    return match.group(0) if match else None


def save(snapshot, body):
    text = body.get('text')
    if not isinstance(text, str) or not text.strip() or '\x00' in text:
        raise ResourceError('El texto no puede estar vacío ni contener datos binarios.')
    raw = text.encode('utf-8')
    if len(raw) > MAX_TEXT_BYTES:
        raise ResourceError('El texto supera el límite de edición de 1 MB.')
    with _save_lock:
        path, relative = safe_path(snapshot, body)
        if not eligible(relative):
            raise ResourceError('Este recurso es de solo lectura.')
        old = read_bytes(path, MAX_TEXT_BYTES)
        if body.get('version') != version(old):
            return dict(ok=False, code='conflict', message='El archivo cambió fuera del editor. Conserva tu borrador y revisa el original.')
        parts = [p.lower() for p in relative.parts]
        shared = parts[:2] in (['infra', 'agents'], ['infra', 'skills'])
        if shared and (_metadata(old.decode('utf-8-sig')) is None or _metadata(text) != _metadata(old.decode('utf-8-sig'))):
            raise ResourceError('Mantén intacta la cabecera de metadatos: sus cambios requieren el flujo de mantenimiento.')
        # Revalidate immediately before opening. Same-user filesystem replacement races remain an OS-level risk.
        safe_path(snapshot, body)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='wb', prefix='.workshop-draft-', suffix='.tmp', dir=path.parent, delete=False) as target:
                temporary = Path(target.name)
                target.write(raw)
                target.flush()
                os.fsync(target.fileno())
            safe_path(snapshot, body)
            if version(read_bytes(path, MAX_TEXT_BYTES)) != body['version']:
                return dict(ok=False, code='conflict', message='El archivo cambió. El borrador se conserva.')
            os.replace(temporary, path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        maintenance = ''
        if parts[:2] == ['infra', 'agents']:
            adapter = Path(snapshot.workshop_root) / 'infra' / 'scripts' / 'codex-adapter.py'
            commands = ['agents', 'personal'] if len(parts) > 2 and parts[2] == 'personal-assistants' else ['agents']
            try:
                for command in commands:
                    subprocess.run([sys.executable, str(adapter), command], cwd=str(adapter.parent.parent),
                                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=30, check=True)
            except (OSError, subprocess.SubprocessError):
                maintenance = ' El original se guardó, pero falló la regeneración; ejecuta el mantenimiento antes de usar los adaptadores.'
        return dict(ok=True, version=version(raw), message='Guardado.' + maintenance, maintenanceRequired=bool(maintenance))


def reader_modules():
    if not (READER_ROOT / 'reading_assistant' / 'extract.py').is_file():
        raise ResourceError('No se encuentra ai-reading-assistant en applications.')
    if str(READER_ROOT) not in sys.path:
        sys.path.insert(0, str(READER_ROOT))
    from reading_assistant import clean, extract, language, translate
    return clean, extract, language, translate


def read_document(snapshot, body):
    clean, extract, language, _ = reader_modules()
    path, relative = safe_path(snapshot, body)
    if path.suffix.lower() not in extract.SUPPORTED_EXTENSIONS:
        raise ResourceError(extract.MSG_PDF if path.suffix.lower() == '.pdf' else extract.MSG_UNSUPPORTED)
    text = clean.clean_text(extract.extract_text(path.name, read_bytes(path, MAX_FILE_BYTES)))
    if not text.strip():
        raise ResourceError('No hay texto legible en el documento.')
    return dict(ok=True, original=text, language=language.detect_language(text), path=str(relative))


def prepare_text(body):
    """Clean and identify explicitly pasted text without persisting or logging it."""
    clean, _, language, _ = reader_modules()
    text = body.get('text')
    if not isinstance(text, str) or not text.strip() or '\x00' in text:
        raise ResourceError('Pega texto legible para preparar la lectura.')
    if len(text.encode('utf-8')) > MAX_TEXT_BYTES:
        raise ResourceError('El texto pegado supera el límite de 1 MB.')
    prepared = clean.clean_text(text)
    if not prepared.strip():
        raise ResourceError('No queda texto legible después de limpiarlo.')
    return dict(ok=True, original=prepared, language=language.detect_language(prepared), path='Texto pegado')


def read_upload(body):
    """Extract a user-selected supported file in memory, with the reader's 20 MB bound."""
    clean, extract, language, _ = reader_modules()
    name, encoded = body.get('name'), body.get('data')
    if not isinstance(name, str) or not name or len(name) > 255 or '/' in name or '\\' in name:
        raise ResourceError('Nombre de archivo no válido.')
    suffix = Path(name).suffix.lower()
    if suffix not in extract.SUPPORTED_EXTENSIONS:
        raise ResourceError(extract.MSG_PDF if suffix == '.pdf' else extract.MSG_UNSUPPORTED)
    if not isinstance(encoded, str) or len(encoded) > ((MAX_FILE_BYTES + 2) // 3) * 4:
        raise ResourceError('El archivo supera el límite de 20 MB.')
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError):
        raise ResourceError('No se pudo leer el archivo seleccionado.') from None
    if not raw or len(raw) > MAX_FILE_BYTES:
        raise ResourceError('El archivo está vacío o supera el límite de 20 MB.')
    text = clean.clean_text(extract.extract_text(name, raw))
    if not text.strip():
        raise ResourceError('No hay texto legible en el documento.')
    return dict(ok=True, original=text, language=language.detect_language(text), path=name)


def translate_text(body):
    _, _, language, translate = reader_modules()
    text = body.get('text')
    if not isinstance(text, str) or not text.strip():
        raise ResourceError('No hay texto para traducir.')
    skipped = language.detect_language(text)['is_spanish']
    return dict(ok=True, text=text if skipped else translate.translate_to_spanish(text), skipped=skipped)


def handle(action, snapshot, body, find_executable):
    try:
        if action == 'document':
            return document(snapshot, body)
        if action == 'save':
            return save(snapshot, body)
        if action == 'read':
            return read_document(snapshot, body)
        if action == 'prepare-text':
            return prepare_text(body)
        if action == 'upload':
            return read_upload(body)
        if action == 'translate':
            return translate_text(body)
        if action == 'reader-status':
            return dict(ok=True, **reader_modules()[3].availability())
        if action in ('registry', 'dispatch'):
            import client_dispatch
            if action == 'registry':
                return dict(ok=True, **client_dispatch.registry(snapshot, find_executable))
            profile = document(snapshot, {'id': body['agent']}) if body.get('agent') else None
            if profile and body.get('agentVersion') != profile['version']:
                return dict(ok=False, status='rejected', message='El perfil del agente cambió. Vuelve a cargarlo y revisarlo antes de enviar.')
            role = profile['text'] if profile else ''
            return client_dispatch.dispatch(body, snapshot, find_executable, role_text=role)
        raise ResourceError('Acción desconocida.')
    except (ResourceError, OSError, UnicodeError, ValueError, TypeError) as error:
        return dict(ok=False, message=str(error) if isinstance(error, ResourceError) else 'No se pudo procesar el recurso. Revisa permisos y formato.')
    except Exception as error:
        # Reader errors carry user-facing Spanish messages. Never expose other exception details.
        from reading_assistant.errors import UserFacingError
        return dict(ok=False, message=str(error) if isinstance(error, UserFacingError) else 'No se pudo completar la operación.')
