"""Real filesystem conflict/path checks; local reader reuse without cloud requests."""
import io
import base64
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
import resource_interaction as resources


class ResourceInteractionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / 'infra/docs/sample.md'
        self.path.parent.mkdir(parents=True)
        self.path.write_text('# Sample\n\nThe document is for the user and it is readable.', encoding='utf-8')
        self.snapshot = SimpleNamespace(workshop_root=str(self.root), by_id={
            'sample': SimpleNamespace(path=str(self.path))})

    def test_explicit_save_and_conflict(self):
        loaded = resources.document(self.snapshot, {'id': 'sample'})
        self.assertTrue(loaded['editable'])
        result = resources.save(self.snapshot, dict(id='sample', version=loaded['version'], text='New draft'))
        self.assertTrue(result['ok'])
        self.assertEqual(self.path.read_text(), 'New draft')
        result = resources.save(self.snapshot, dict(id='sample', version=loaded['version'], text='Stale draft'))
        self.assertEqual(result['code'], 'conflict')
        self.assertEqual(self.path.read_text(), 'New draft')

    def test_external_change_conflict(self):
        loaded = resources.document(self.snapshot, {'id': 'sample'})
        self.path.write_text('External change')
        self.assertEqual(resources.save(self.snapshot, dict(id='sample', version=loaded['version'], text='Draft'))['code'], 'conflict')

    def test_protected_and_traversal(self):
        for path in ['../outside.md', 'infra/../docs/sample.md', 'C:/outside.md', '/outside.md',
                     'infra/.env', 'infra/.aws/test.md', 'infra/vendor/test.md', 'infra/clients/.agents/test.md']:
            with self.subTest(path=path), self.assertRaises(resources.ResourceError):
                resources.safe_path(self.snapshot, {'path': path})

    def test_policy_and_application_source_read_only(self):
        for relative in ['infra/AGENTS.md', 'applications/example/server.py', 'infra/clients/personal/codex/a.toml']:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('Original')
            with self.subTest(path=relative), self.assertRaises(resources.ResourceError):
                resources.save(self.snapshot, dict(path=relative, version=resources.version(b'Original'), text='Draft'))
            self.assertEqual(path.read_text(), 'Original')

    def test_symlink_rejected(self):
        link = self.root / 'infra/docs/link.md'
        try:
            link.symlink_to(self.path)
        except OSError:
            self.skipTest('Symlink creation not permitted')
        with self.assertRaises(resources.ResourceError):
            resources.safe_path(self.snapshot, {'path': 'infra/docs/link.md'})

    def test_binary_and_oversize(self):
        self.path.write_bytes(b'hello\x00world')
        with self.assertRaises(resources.ResourceError):
            resources.document(self.snapshot, {'id': 'sample'})
        self.path.write_bytes(b'a' * (resources.MAX_TEXT_BYTES + 1))
        with self.assertRaises(resources.ResourceError):
            resources.document(self.snapshot, {'id': 'sample'})

    def test_shared_identity_protected_and_regeneration(self):
        relative = 'infra/agents/quality/sample.md'
        path = self.root / relative
        path.parent.mkdir(parents=True)
        old = '---\nname: sample\ndescription: Sample\n---\nOriginal body'
        path.write_text(old, encoding='utf-8')
        loaded = resources.document(self.snapshot, {'path': relative})
        with self.assertRaises(resources.ResourceError):
            resources.save(self.snapshot, dict(path=relative, version=loaded['version'], text=old.replace('name: sample', 'name: renamed')))
        with self.assertRaises(resources.ResourceError):
            resources.save(self.snapshot, dict(path=relative, version=loaded['version'], text=old.replace('description: Sample', 'description: Sample\nname : ../../../../outside')))
        with patch.object(resources.subprocess, 'run') as run:
            result = resources.save(self.snapshot, dict(path=relative, version=loaded['version'], text=old.replace('Original body', 'New body')))
            self.assertTrue(result['ok'])
            self.assertEqual(run.call_args.args[0][-1], 'agents')

    def test_reader_markdown_and_spanish_skip(self):
        result = resources.read_document(self.snapshot, {'id': 'sample'})
        self.assertTrue(result['ok'])
        self.assertNotIn('#', result['original'])
        original = self.path.read_bytes()
        spanish = 'Este documento es para el usuario y está en español. La lectura de los documentos es muy útil.'
        with patch('reading_assistant.translate.translate_to_spanish') as translate:
            result = resources.translate_text({'text': spanish})
            self.assertTrue(result['skipped'])
            translate.assert_not_called()
        self.assertEqual(self.path.read_bytes(), original)

    def test_pasted_text_is_cleaned_and_not_persisted(self):
        result = resources.prepare_text({'text': '# Hola\n\nEste texto es para leer en español y contiene varias palabras.'})
        self.assertTrue(result['ok'])
        self.assertEqual(result['path'], 'Texto pegado')
        self.assertNotIn('#', result['original'])
        self.assertTrue(result['language']['is_spanish'])
        self.assertEqual(self.path.read_text(encoding='utf-8').startswith('# Sample'), True)

    def test_pasted_text_rejects_empty_and_oversized_content(self):
        for text in ['', '   ', 'x' * (resources.MAX_TEXT_BYTES + 1)]:
            with self.subTest(length=len(text)), self.assertRaises(resources.ResourceError):
                resources.prepare_text({'text': text})

    def test_uploaded_markdown_is_cleaned_and_unsupported_files_rejected(self):
        encoded = base64.b64encode(b'# Hola\n\nEste texto es para leer en espa\xc3\xb1ol y escuchar despues.').decode('ascii')
        result = resources.read_upload({'name': 'lectura.md', 'data': encoded})
        self.assertTrue(result['ok'])
        self.assertEqual(result['path'], 'lectura.md')
        self.assertNotIn('#', result['original'])
        self.assertTrue(result['language']['is_spanish'])
        for name in ('manual.pdf', '../lectura.md', 'lectura.txt\\other.md'):
            with self.subTest(name=name), self.assertRaises(resources.ResourceError):
                resources.read_upload({'name': name, 'data': encoded})

    def test_upload_base64_and_file_size_are_validated(self):
        with self.assertRaises(resources.ResourceError):
            resources.read_upload({'name': 'lectura.txt', 'data': 'not base64!'})
        oversized = base64.b64encode(b'a' * (resources.MAX_FILE_BYTES + 1)).decode('ascii')
        with self.assertRaises(resources.ResourceError):
            resources.read_upload({'name': 'lectura.txt', 'data': oversized})

    def test_txt_docx_and_unsupported(self):
        text = self.root / 'infra/docs/sample.txt'
        text.write_text('The text is for the user and it is readable.', encoding='utf-8')
        self.assertTrue(resources.read_document(self.snapshot, {'path': 'infra/docs/sample.txt'})['ok'])
        docx = self.root / 'infra/docs/sample.docx'
        with zipfile.ZipFile(docx, 'w') as archive:
            archive.writestr('word/document.xml', '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>The document is for the user.</w:t></w:r></w:p></w:body></w:document>')
        self.assertIn('document', resources.read_document(self.snapshot, {'path': 'infra/docs/sample.docx'})['original'])
        pdf = self.root / 'infra/docs/sample.pdf'
        pdf.write_bytes(b'%PDF')
        result = resources.handle('read', self.snapshot, {'path': 'infra/docs/sample.pdf'}, None)
        self.assertFalse(result['ok'])
        self.assertIn('PDF', result['message'])


if __name__ == '__main__':
    unittest.main()
