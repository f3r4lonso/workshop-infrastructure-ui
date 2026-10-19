"""Checks for server/server.py: security rules, API shape and static files.

The server runs in a thread on a free port against a temporary workspace and web/dist fixture.
os.startfile and subprocess.Popen are mocked: nothing is opened or launched.
"""

from __future__ import annotations

import http.client
import json
import os
import re
import shutil
import sys
import tempfile
import threading
import unittest
from typing import Any
from unittest import mock

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(APP_DIR, "server"))

import server  # noqa: E402

INDEX_HTML = '<!doctype html><html><head><title>Workshop</title></head><body><div id="root"></div></body></html>'


def write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


class ServerTests(unittest.TestCase):
    temp: str
    root: str
    state: server.AppState
    httpd: server.WorkshopServer

    @classmethod
    def setUpClass(cls) -> None:
        cls.temp = tempfile.mkdtemp(prefix="workshop-ui-server-")
        cls.root = os.path.join(cls.temp, "workshop")
        infra = os.path.join(cls.root, "infra")
        write(os.path.join(infra, "docs", "catalogues", "agents.md"),
              "| Area | Agent | Use | Access |\n|---|---|---|---|\n"
              "| Quality | [security-reviewer](../../agents/quality/security-reviewer.md) | Review security | RO |\n")
        write(os.path.join(infra, "agents", "quality", "security-reviewer.md"),
              "---\nname: security-reviewer\n---\n")
        write(os.path.join(infra, "README.md"), "# Infra\n\nShared infrastructure.\n")
        dist = os.path.join(cls.temp, "dist")
        write(os.path.join(dist, "index.html"), INDEX_HTML)
        write(os.path.join(dist, "assets", "app.js"), "console.log('ok');")
        write(os.path.join(dist, "assets", "app.css"), "body{}")
        write(os.path.join(cls.temp, "server.py"), "SECRET = 'outside dist'")

        cls.bin_dir = os.path.join(cls.temp, "bin")
        cls.wt_dir = os.path.join(cls.temp, "wt")
        cls.odd_dir = os.path.join(cls.temp, "odd&bin")
        for path in (os.path.join(cls.bin_dir, "claude.exe"), os.path.join(cls.bin_dir, "gemini.cmd"),
                     os.path.join(cls.wt_dir, "wt.exe"), os.path.join(cls.odd_dir, "claude.exe"),
                     os.path.join(cls.root, "fake-bin", "codex.exe"), os.path.join(cls.temp, "cwd", "copilot.exe")):
            write(path, "")
        cls.state = server.AppState(infra_root=infra, dist_dir=dist, quiet=True)
        cls.state.load()
        cls.httpd = server.create_server(cls.state, 0, 0)
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.httpd.shutdown()
        cls.httpd.server_close()
        shutil.rmtree(cls.temp, ignore_errors=True)

    def setUp(self) -> None:
        server.reset_launch_cooldown()

    # --- helpers ---
    def request(self, method: str, path: str, body: bytes | str | None = None,
                headers: dict[str, str] | None = None, host: str | None = None) -> tuple[int, dict[str, str], bytes]:
        conn = http.client.HTTPConnection("127.0.0.1", self.state.port, timeout=10)
        all_headers = {"Host": host or f"127.0.0.1:{self.state.port}"}
        all_headers.update(headers or {})
        if isinstance(body, str):
            body = body.encode("utf-8")
        conn.request(method, path, body=body, headers=all_headers)
        response = conn.getresponse()
        data = response.read()
        result = response.status, {k.lower(): v for k, v in response.getheaders()}, data
        conn.close()
        return result

    def post(self, path: str, payload: Any = None, token: str | None = None,
             headers: dict[str, str] | None = None) -> tuple[int, dict[str, Any]]:
        all_headers = {"Content-Type": "application/json",
                       "X-Workshop-Token": self.state.token if token is None else token}
        all_headers.update(headers or {})
        body = json.dumps(payload if payload is not None else {})
        status, _, data = self.request("POST", path, body, all_headers)
        return status, json.loads(data)

    # --- security ---
    def test_host_check_blocks_foreign_host(self) -> None:
        status, _, data = self.request("GET", "/api/data", host="evil.example")
        self.assertEqual(status, 403)
        self.assertFalse(json.loads(data)["ok"])
        status, _, _ = self.request("GET", "/", host=f"evil.example:{self.state.port}")
        self.assertEqual(status, 403)

    def test_localhost_host_accepted(self) -> None:
        status, _, _ = self.request("GET", "/api/clients", host=f"localhost:{self.state.port}")
        self.assertEqual(status, 200)

    def test_post_without_token_forbidden(self) -> None:
        status, _, data = self.request("POST", "/api/refresh", "{}", {"Content-Type": "application/json"})
        self.assertEqual(status, 403)
        self.assertFalse(json.loads(data)["ok"])

    def test_post_with_wrong_token_forbidden(self) -> None:
        status, body = self.post("/api/refresh", token="wrong")
        self.assertEqual(status, 403)
        self.assertFalse(body["ok"])

    def test_post_with_wrong_origin_forbidden(self) -> None:
        status, _ = self.post("/api/refresh", headers={"Origin": "http://evil.example"})
        self.assertEqual(status, 403)
        status, _ = self.post("/api/refresh", headers={"Origin": f"http://localhost:{self.state.port}"})
        self.assertEqual(status, 200)

    def test_post_body_over_4kb_rejected(self) -> None:
        payload = {"id": "x" * 5000, "target": "document"}
        with mock.patch("os.startfile", create=True) as startfile:
            status, body = self.post("/api/open", payload)
        self.assertEqual(status, 413)
        self.assertFalse(body["ok"])
        startfile.assert_not_called()

    def test_bad_json_rejected(self) -> None:
        headers = {"X-Workshop-Token": self.state.token, "Content-Type": "application/json"}
        for raw in ("{not json", "[1, 2]"):
            with self.subTest(raw=raw):
                status, _, data = self.request("POST", "/api/open", raw, headers)
                self.assertEqual(status, 400)
                self.assertFalse(json.loads(data)["ok"])

    def test_unknown_api_route_404(self) -> None:
        status, _, data = self.request("GET", "/api/nothing")
        self.assertEqual(status, 404)
        self.assertFalse(json.loads(data)["ok"])
        status, _ = self.post("/api/nothing")
        self.assertEqual(status, 404)

    def test_no_cors_headers(self) -> None:
        for method, path in (("GET", "/api/data"), ("GET", "/"), ("OPTIONS", "/api/open")):
            with self.subTest(path=path, method=method):
                _, headers, _ = self.request(method, path, headers={"Origin": "http://evil.example"})
                self.assertEqual([h for h in headers if h.startswith("access-control-")], [])

    # --- API ---
    def test_data_shape(self) -> None:
        status, headers, data = self.request("GET", "/api/data")
        self.assertEqual(status, 200)
        self.assertTrue(headers["content-type"].startswith("application/json"))
        payload = json.loads(data)
        for key in ("workshopRoot", "loadedMs", "sections", "typeLabels", "items", "warnings", "searchSynonyms"):
            self.assertIn(key, payload)
        self.assertEqual(payload["workshopRoot"], self.root)
        item = next(i for i in payload["items"] if i["id"] == "agentes:security-reviewer")
        for key in ("section", "typeLabel", "name", "title", "description", "area", "status", "statusLabel",
                    "statusShort", "taskState", "relativePath", "usage", "usageHint", "modified", "related",
                    "canOpenDocument", "canOpenFolder", "searchText"):
            self.assertIn(key, item)
        self.assertNotIn("path", item)
        self.assertIn("seguridad", payload["searchSynonyms"])

    def test_refresh_returns_data(self) -> None:
        status, body = self.post("/api/refresh")
        self.assertEqual(status, 200)
        self.assertIn("items", body)

    def test_open_unknown_id(self) -> None:
        with mock.patch("os.startfile", create=True) as startfile:
            status, body = self.post("/api/open", {"id": "agentes:nope", "target": "document"})
        self.assertEqual(status, 200)
        self.assertFalse(body["ok"])
        startfile.assert_not_called()

    def test_open_bad_target(self) -> None:
        with mock.patch("os.startfile", create=True) as startfile:
            _, body = self.post("/api/open", {"id": "agentes:security-reviewer", "target": "C:\\Windows"})
        self.assertFalse(body["ok"])
        startfile.assert_not_called()

    def test_open_document_and_folder(self) -> None:
        expected = os.path.join(self.root, "infra", "agents", "quality", "security-reviewer.md")
        with mock.patch("os.startfile", create=True) as startfile:
            _, body = self.post("/api/open", {"id": "agentes:security-reviewer", "target": "document"})
            self.assertTrue(body["ok"])
            startfile.assert_called_once_with(expected)
            startfile.reset_mock()
            _, body = self.post("/api/open", {"id": "agentes:security-reviewer", "target": "folder"})
            self.assertTrue(body["ok"])
            startfile.assert_called_once_with(os.path.dirname(expected))

    def test_launch_unknown_client(self) -> None:
        with mock.patch.object(server.subprocess, "Popen") as popen:
            status, body = self.post("/api/launch", {"client": "calc"})
            self.assertEqual(status, 400)
            self.assertFalse(body["ok"])
            status, body = self.post("/api/launch", {"client": "claude & calc"})
            self.assertEqual(status, 400)
            popen.assert_not_called()

    # --- client lookup and launch (PATH points at temporary folders; Popen is mocked) ---
    def fake_path(self, *folders: str, wt: bool = True) -> Any:
        entries = list(folders) + ([self.wt_dir] if wt else [])
        return mock.patch.dict(os.environ, {"PATH": os.pathsep.join(entries), "PATHEXT": ".COM;.EXE;.BAT;.CMD"})

    def test_clients_list(self) -> None:
        with self.fake_path(self.bin_dir):
            status, _, data = self.request("GET", "/api/clients")
        self.assertEqual(status, 200)
        clients = json.loads(data)["clients"]
        self.assertEqual([c["id"] for c in clients], ["claude", "codex", "gemini", "copilot"])
        self.assertEqual([c["installed"] for c in clients], [True, False, True, False])

    def test_lookup_skips_workspace_cwd_and_relative_entries(self) -> None:
        planted = os.path.join(self.root, "fake-bin")
        cwd_dir = os.path.join(self.temp, "cwd")
        previous = os.getcwd()
        os.chdir(cwd_dir)  # holds copilot.exe; the current directory must never be searched
        try:
            with self.fake_path(planted, ".", "cwd", self.bin_dir):
                self.assertIsNone(server.find_executable("codex", self.root))
                self.assertIsNone(server.find_executable("copilot", self.root))
                self.assertEqual(server.find_executable("claude", self.root),
                                 os.path.join(self.bin_dir, "claude.exe"))
                with mock.patch.object(server.subprocess, "Popen") as popen:
                    _, body = self.post("/api/launch", {"client": "codex"})
                self.assertFalse(body["ok"])
                popen.assert_not_called()
        finally:
            os.chdir(previous)

    def test_launch_with_windows_terminal(self) -> None:
        with self.fake_path(self.bin_dir), mock.patch.object(server.subprocess, "Popen") as popen:
            status, body = self.post("/api/launch", {"client": "claude"})
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])
        self.assertEqual(body["message"], "Abriendo Claude Code en una ventana nueva…")
        args, kwargs = popen.call_args
        self.assertEqual(args[0], [os.path.join(self.wt_dir, "wt.exe"), "-d", self.root, "--title", "Claude Code",
                                   "cmd", "/k", os.path.join(self.bin_dir, "claude.exe")])
        self.assertEqual(kwargs["cwd"], self.root)
        self.assertEqual(kwargs["env"]["NoDefaultCurrentDirectoryInExePath"], "1")
        self.assertNotIn("shell", kwargs)

    def test_launch_without_windows_terminal(self) -> None:
        with self.fake_path(self.bin_dir, wt=False), mock.patch.object(server.subprocess, "Popen") as popen:
            _, body = self.post("/api/launch", {"client": "gemini"})
        self.assertTrue(body["ok"])
        args, kwargs = popen.call_args
        self.assertEqual(args[0], ["cmd", "/c", "start", "Gemini CLI", "/D", self.root, "cmd", "/k",
                                   os.path.join(self.bin_dir, "gemini.cmd")])
        self.assertEqual(kwargs["cwd"], self.root)
        self.assertFalse(kwargs.get("shell", False))

    def test_launch_not_installed(self) -> None:
        with self.fake_path(), mock.patch.object(server.subprocess, "Popen") as popen:
            status, body = self.post("/api/launch", {"client": "copilot"})
        self.assertEqual(status, 200)
        self.assertFalse(body["ok"])
        self.assertIn("no está instalado", body["message"])
        popen.assert_not_called()

    def test_launch_refuses_special_characters(self) -> None:
        with self.fake_path(self.odd_dir), mock.patch.object(server.subprocess, "Popen") as popen:
            _, body = self.post("/api/launch", {"client": "claude"})
            self.assertFalse(body["ok"])
            self.assertIn("caracteres especiales", body["message"])
        with self.fake_path(self.bin_dir), mock.patch.object(server.subprocess, "Popen") as popen2:
            _, body = server.launch_client("gemini", os.path.join(self.temp, "a&b"))
            self.assertFalse(body["ok"])
            self.assertIn("caracteres especiales", body["message"])
        popen.assert_not_called()
        popen2.assert_not_called()

    def test_second_launch_within_3_seconds_ignored(self) -> None:
        with self.fake_path(self.bin_dir), mock.patch.object(server.subprocess, "Popen") as popen:
            _, first = self.post("/api/launch", {"client": "claude"})
            _, second = self.post("/api/launch", {"client": "claude"})
            _, other = self.post("/api/launch", {"client": "gemini"})
        self.assertTrue(first["ok"])
        self.assertEqual(second, {"ok": False, "message": "Ya se está abriendo; espera un momento."})
        self.assertTrue(other["ok"])
        self.assertEqual(popen.call_count, 2)

    # --- hardening ---
    def test_deeply_nested_json_rejected(self) -> None:
        headers = {"X-Workshop-Token": self.state.token, "Content-Type": "application/json"}
        status, _, data = self.request("POST", "/api/open", "[" * 2000 + "]" * 2000, headers)
        self.assertEqual(status, 400)
        self.assertFalse(json.loads(data)["ok"])

    def test_content_security_policy(self) -> None:
        for path in ("/", "/api/data", "/assets/app.js"):
            with self.subTest(path=path):
                _, headers, _ = self.request("GET", path)
                self.assertEqual(headers["content-security-policy"], server.CSP)
        self.assertIn("frame-ancestors 'none'", server.CSP)

    def test_built_index_has_no_inline_script(self) -> None:
        # Under the CSP (script-src falls back to 'self') an inline <script> in the real build would not run.
        index = os.path.join(server.DEFAULT_DIST, "index.html")
        if not os.path.isfile(index):
            self.skipTest("web/dist is not built")
        with open(index, encoding="utf-8") as handle:
            html = handle.read()
        for tag in re.findall(r"<script\b[^>]*>", html, re.IGNORECASE):
            self.assertRegex(tag, r"\bsrc=")
        self.assertNotRegex(html, r"(?i)\son[a-z]+\s*=")

    def test_socket_timeout(self) -> None:
        self.assertEqual(server.WorkshopHandler.timeout, 10)

    def test_log_strips_control_characters(self) -> None:
        handler = server.WorkshopHandler.__new__(server.WorkshopHandler)
        handler.server = mock.Mock(state=mock.Mock(quiet=False))
        handler.client_address = ("127.0.0.1", 1)
        with mock.patch.object(server.sys, "stderr") as stderr:
            handler.log_message("%s", "GET /\x1b[31mred\r\nfake line")
        written = stderr.write.call_args[0][0]
        self.assertNotIn("\x1b", written)
        self.assertNotIn("\r", written)
        self.assertEqual(written.count("\n"), 1)

    # --- static files ---
    def test_index_has_token_meta(self) -> None:
        status, headers, data = self.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertTrue(headers["content-type"].startswith("text/html"))
        html = data.decode("utf-8")
        self.assertIn(f'<meta name="workshop-token" content="{self.state.token}"></head>', html)

    def test_static_content_types(self) -> None:
        for path, prefix in (("/assets/app.js", "text/javascript"), ("/assets/app.css", "text/css")):
            with self.subTest(path=path):
                status, headers, _ = self.request("GET", path)
                self.assertEqual(status, 200)
                self.assertTrue(headers["content-type"].startswith(prefix))

    def test_spa_fallback(self) -> None:
        status, _, data = self.request("GET", "/agentes/security-reviewer")
        self.assertEqual(status, 200)
        self.assertIn(b"workshop-token", data)

    def test_traversal_blocked(self) -> None:
        for path in ("/../server.py", "/%2e%2e/server.py", "/assets/%2e%2e/%2e%2e/server.py",
                     "/..%2fserver.py", "/..%5cserver.py", "/assets/..\\..\\server.py", "/C:%5cWindows%5cwin.ini"):
            with self.subTest(path=path):
                status, _, data = self.request("GET", path)
                self.assertNotIn(b"outside dist", data)
                self.assertEqual(status, 403)

    def test_missing_build_page(self) -> None:
        html = server.render_index(os.path.join(self.temp, "no-dist"), "t").decode("utf-8")
        self.assertIn("npm install", html)
        self.assertIn("npm run build", html)


if __name__ == "__main__":
    unittest.main()
