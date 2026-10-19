"""Local web server for Workshop Infrastructure UI.

Serves the React build from web/dist and a small JSON API (contract: docs/web-architecture.md).
Bound to 127.0.0.1 only. Standard library only.

Usage: python server/server.py [--infra PATH] [--port N] [--no-browser]
"""

from __future__ import annotations

import argparse
import json
import os
import posixpath
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
import webbrowser
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import unquote, urlsplit

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import workshop_data  # noqa: E402

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_INFRA = os.path.normpath(os.path.join(APP_DIR, "..", "..", "infra"))
DEFAULT_DIST = os.path.join(APP_DIR, "web", "dist")
HOST = "127.0.0.1"
FIRST_PORT = 8770
LAST_PORT = 8790
MAX_BODY = 4 * 1024

# Fixed allow-list: client id -> (display name, command). Nothing from a request ever reaches a command line.
CLIENTS: dict[str, tuple[str, str]] = {
    "claude": ("Claude Code", "claude"),
    "codex": ("Codex CLI", "codex"),
    "gemini": ("Gemini CLI", "gemini"),
    "copilot": ("GitHub Copilot CLI", "copilot"),
}

CONTENT_TYPES: dict[str, str] = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".json": "application/json; charset=utf-8",
    ".woff2": "font/woff2",
    ".txt": "text/plain; charset=utf-8",
    ".map": "application/json; charset=utf-8",
}

MISSING_BUILD_PAGE = """<!doctype html>
<html lang="es">
<head><meta charset="utf-8"><title>Workshop</title></head>
<body style="font-family: Segoe UI, sans-serif; max-width: 40rem; margin: 3rem auto; line-height: 1.5">
<h1>Falta preparar la interfaz</h1>
<p>No se encontró <code>web\\dist\\index.html</code>. Abre una terminal en la carpeta <code>web</code> de esta
aplicación y ejecuta:</p>
<pre>npm install
npm run build</pre>
<p>Después recarga esta página. También puedes cerrar el servidor y hacer doble clic en <code>INICIAR.cmd</code>.</p>
</body>
</html>
"""

MSG_FORBIDDEN = "Petición no permitida."
MSG_NOT_FOUND = "No existe esa ruta."
MSG_BAD_JSON = "La petición no es JSON válido."
MSG_TOO_LARGE = "La petición es demasiado grande."
MSG_UNKNOWN_ITEM = "No se encontró este elemento. Pulsa Actualizar por si ha cambiado."
MSG_NO_DOCUMENT = "Este elemento no tiene un documento que se pueda abrir. Pulsa Actualizar por si ha cambiado."
MSG_NO_FOLDER = "La carpeta ya no existe. Pulsa Actualizar."
MSG_DOCUMENT_FAILED = ("No se pudo abrir el documento. Comprueba que Windows tenga una aplicación asociada "
                       "a los archivos .md.")
MSG_FOLDER_FAILED = "No se pudo abrir la carpeta en el Explorador de archivos."
MSG_BAD_TARGET = "Destino no válido: usa «document» o «folder»."
MSG_UNKNOWN_CLIENT = "Cliente de IA desconocido."
MSG_REFRESH_FAILED = "No se pudieron volver a leer los datos. Revisa la carpeta infra y vuelve a intentarlo."


@dataclass
class AppState:
    """Shared server state. The snapshot is swapped atomically under the lock on refresh."""
    infra_root: str
    dist_dir: str
    token: str = field(default_factory=lambda: secrets.token_urlsafe(32))
    port: int = 0
    quiet: bool = False
    snapshot: workshop_data.Snapshot | None = None
    lock: threading.Lock = field(default_factory=threading.Lock)

    def load(self) -> workshop_data.Snapshot:
        snapshot = workshop_data.build_snapshot(self.infra_root)
        with self.lock:
            self.snapshot = snapshot
        return snapshot

    def current(self) -> workshop_data.Snapshot:
        with self.lock:
            if self.snapshot is not None:
                return self.snapshot
        return self.load()

    def allowed_hosts(self) -> set[str]:
        return {f"127.0.0.1:{self.port}", f"localhost:{self.port}"}

    def allowed_origins(self) -> set[str]:
        return {f"http://127.0.0.1:{self.port}", f"http://localhost:{self.port}"}


def workspace_root(state: AppState) -> str:
    """The folder that contains infra\\."""
    return os.path.dirname(os.path.abspath(state.infra_root).rstrip("\\"))


# --- Actions ------------------------------------------------------------------------------------------------

# Characters that cmd.exe treats specially; a launch is refused if the root or executable path contains one.
_CMD_SPECIAL = set(';&|^%"<>')
LAUNCH_COOLDOWN_S = 3.0
_last_launch: dict[str, float] = {}
_launch_lock = threading.Lock()


def _inside(path: str, root: str) -> bool:
    base = os.path.normcase(os.path.abspath(root)).rstrip("\\")
    target = os.path.normcase(os.path.abspath(path))
    return target == base or target.startswith(base + "\\")


def find_executable(command: str, root: str) -> str | None:
    """Absolute path of a command found on PATH only.

    Unlike shutil.which on Windows, the current directory is never searched, relative PATH entries are ignored and
    any match inside the workspace root is rejected, so a fake client planted in the workspace is never run.
    """
    extensions = [""] if os.path.splitext(command)[1] else [
        e.lower() for e in (os.environ.get("PATHEXT") or ".COM;.EXE;.BAT;.CMD").split(";") if e]
    for entry in (os.environ.get("PATH") or "").split(os.pathsep):
        folder = entry.strip().strip('"')
        if not folder or not os.path.isabs(folder):
            continue
        for extension in extensions:
            candidate = os.path.abspath(os.path.join(folder, command + extension))
            if os.path.isfile(candidate) and not _inside(candidate, root):
                return candidate
    return None


def clients_payload(root: str) -> dict[str, Any]:
    return {"clients": [{"id": cid, "name": name, "installed": find_executable(cmd, root) is not None,
                         "command": cmd} for cid, (name, cmd) in CLIENTS.items()]}


def launch_command(name: str, executable: str, root: str) -> list[str]:
    """Argument list for a new terminal window in the workspace root running the client's absolute path."""
    wt = find_executable("wt", root)
    if wt and not (_CMD_SPECIAL & set(wt)):
        return [wt, "-d", root, "--title", name, "cmd", "/k", executable]
    return ["cmd", "/c", "start", name, "/D", root, "cmd", "/k", executable]


def reset_launch_cooldown() -> None:
    with _launch_lock:
        _last_launch.clear()


def launch_client(client_id: Any, root: str) -> tuple[HTTPStatus, dict[str, Any]]:
    if not isinstance(client_id, str) or client_id not in CLIENTS:
        return HTTPStatus.BAD_REQUEST, {"ok": False, "message": MSG_UNKNOWN_CLIENT}
    name, command = CLIENTS[client_id]
    executable = find_executable(command, root)
    if executable is None:
        return HTTPStatus.OK, {"ok": False, "message": f"{name} no está instalado o no está en el PATH."}
    if _CMD_SPECIAL & (set(root) | set(executable)):
        return HTTPStatus.OK, {"ok": False, "message": (
            f"No se abre {name}: la ruta de la carpeta workshop o del programa contiene caracteres especiales "
            '(; & | ^ % " < >).')}
    with _launch_lock:
        now = time.monotonic()
        last = _last_launch.get(client_id)
        if last is not None and now - last < LAUNCH_COOLDOWN_S:
            return HTTPStatus.OK, {"ok": False, "message": "Ya se está abriendo; espera un momento."}
        _last_launch[client_id] = now
    env = dict(os.environ)
    env["NoDefaultCurrentDirectoryInExePath"] = "1"
    try:
        subprocess.Popen(launch_command(name, executable, root), cwd=root, env=env, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)
    except OSError:
        return HTTPStatus.OK, {"ok": False, "message": f"No se pudo abrir {name}. Comprueba que esté instalado."}
    return HTTPStatus.OK, {"ok": True, "message": f"Abriendo {name} en una ventana nueva…"}


def open_item(snapshot: workshop_data.Snapshot, item_id: Any, target: Any) -> dict[str, Any]:
    """Opens an item's document or folder; the path always comes from the server's own item list."""
    if target not in ("document", "folder"):
        return {"ok": False, "message": MSG_BAD_TARGET}
    resource = snapshot.by_id.get(item_id) if isinstance(item_id, str) else None
    if resource is None:
        return {"ok": False, "message": MSG_UNKNOWN_ITEM}
    root = snapshot.workshop_root
    if target == "document":
        if not workshop_data.can_open_document(resource, root) or workshop_data.is_linked_path(resource.path, root):
            return {"ok": False, "message": MSG_NO_DOCUMENT}
        try:
            os.startfile(resource.path)  # type: ignore[attr-defined]
        except OSError:
            return {"ok": False, "message": MSG_DOCUMENT_FAILED}
        return {"ok": True, "message": f"Abriendo {resource.relative_path}"}
    folder = workshop_data.resource_folder(resource, root)
    if not folder or not os.path.isdir(folder) or workshop_data.is_linked_path(folder, root):
        return {"ok": False, "message": MSG_NO_FOLDER}
    try:
        os.startfile(folder)  # type: ignore[attr-defined]
    except OSError:
        return {"ok": False, "message": MSG_FOLDER_FAILED}
    relative = workshop_data.relative_workshop_path(folder, root)
    return {"ok": True, "message": f"Abriendo la carpeta {relative}"}


# --- Static files -------------------------------------------------------------------------------------------

_CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f-\x9f]")
CSP = ("default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; object-src 'none'; "
       "base-uri 'none'; frame-ancestors 'none'")
_UNSAFE_SEGMENT = re.compile(r'[\\:\x00-\x1f<>"|?*]')


def static_file_path(dist_dir: str, url_path: str) -> str | None:
    """Maps a URL path to a file under dist_dir. Returns None for traversal attempts or unsafe names."""
    decoded = unquote(url_path)
    segments = [s for s in decoded.split("/") if s]
    for segment in segments:
        if segment in (".", "..") or segment.strip(". ") == "" or _UNSAFE_SEGMENT.search(segment):
            return None
    base = os.path.abspath(dist_dir)
    candidate = os.path.abspath(os.path.join(base, *segments)) if segments else base
    try:
        if os.path.commonpath([base, candidate]) != base:
            return None
    except ValueError:
        return None
    return candidate


def render_index(dist_dir: str, token: str) -> bytes:
    index = os.path.join(dist_dir, "index.html")
    if not os.path.isfile(index):
        return MISSING_BUILD_PAGE.encode("utf-8")
    with open(index, encoding="utf-8") as handle:
        html = handle.read()
    meta = f'<meta name="workshop-token" content="{token}">'
    match = re.search(r"</head>", html, re.IGNORECASE)
    if match:
        html = html[:match.start()] + meta + html[match.start():]
    else:
        html = meta + html
    return html.encode("utf-8")


# --- HTTP ---------------------------------------------------------------------------------------------------

class WorkshopServer(ThreadingHTTPServer):
    # On Windows SO_REUSEADDR lets another process bind the same port; ask for exclusive use instead.
    allow_reuse_address = False
    daemon_threads = True

    def __init__(self, address: tuple[str, int], state: AppState) -> None:
        self.state = state
        super().__init__(address, WorkshopHandler)

    def server_bind(self) -> None:
        exclusive = getattr(socket, "SO_EXCLUSIVEADDRUSE", None)
        if exclusive is not None:
            self.socket.setsockopt(socket.SOL_SOCKET, exclusive, 1)
        super().server_bind()


class WorkshopHandler(BaseHTTPRequestHandler):
    server: WorkshopServer
    server_version = "Workshop"
    sys_version = ""
    protocol_version = "HTTP/1.1"
    timeout = 10  # seconds per socket operation: idle clients cannot hold a thread

    # -- helpers --
    @property
    def state(self) -> AppState:
        return self.server.state

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002 - signature from the base class
        if not self.state.quiet:
            message = _CONTROL_CHARS.sub("?", format % args)
            sys.stderr.write(f"{self.address_string()} {message}\n")

    def _send(self, status: int, body: bytes, content_type: str, cache: bool = False) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "public, max-age=3600" if cache else "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", CSP)
        if self.close_connection:
            self.send_header("Connection", "close")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._send(status, body, "application/json; charset=utf-8")

    def _error(self, status: int, message: str) -> None:
        self._json(status, {"ok": False, "message": message})

    def _host_ok(self) -> bool:
        host = (self.headers.get("Host") or "").strip().lower()
        return host in self.state.allowed_hosts()

    def _path(self) -> str:
        return urlsplit(self.path).path

    # -- verbs --
    def do_GET(self) -> None:  # noqa: N802 - name required by BaseHTTPRequestHandler
        if not self._host_ok():
            self._error(HTTPStatus.FORBIDDEN, MSG_FORBIDDEN)
            return
        path = self._path()
        if path == "/api/data":
            self._json(HTTPStatus.OK, self.state.current().payload)
        elif path == "/api/clients":
            self._json(HTTPStatus.OK, clients_payload(workspace_root(self.state)))
        elif path == "/api" or path.startswith("/api/"):
            self._error(HTTPStatus.NOT_FOUND, MSG_NOT_FOUND)
        else:
            self._serve_static(path)

    def do_HEAD(self) -> None:  # noqa: N802
        self.do_GET()

    def do_POST(self) -> None:  # noqa: N802
        if not self._host_ok() or not self._post_allowed():
            self.close_connection = True  # the unread body must not be parsed as a new request
            self._error(HTTPStatus.FORBIDDEN, MSG_FORBIDDEN)
            return
        body = self._read_json()
        if body is None:
            return
        path = self._path()
        if path == "/api/refresh":
            try:
                snapshot = self.state.load()
            except OSError:
                self._error(HTTPStatus.INTERNAL_SERVER_ERROR, MSG_REFRESH_FAILED)
                return
            self._json(HTTPStatus.OK, snapshot.payload)
        elif path == "/api/open":
            self._json(HTTPStatus.OK, open_item(self.state.current(), body.get("id"), body.get("target")))
        elif path == "/api/launch":
            status, payload = launch_client(body.get("client"), workspace_root(self.state))
            self._json(status, payload)
        else:
            self._error(HTTPStatus.NOT_FOUND, MSG_NOT_FOUND)

    def _reject_other(self) -> None:
        self.close_connection = True
        if not self._host_ok():
            self._error(HTTPStatus.FORBIDDEN, MSG_FORBIDDEN)
        else:
            self._error(HTTPStatus.METHOD_NOT_ALLOWED, "Método no permitido.")

    do_PUT = do_DELETE = do_PATCH = do_OPTIONS = _reject_other  # noqa: N815

    def _post_allowed(self) -> bool:
        token = self.headers.get("X-Workshop-Token") or ""
        if not secrets.compare_digest(token.encode("utf-8"), self.state.token.encode("utf-8")):
            return False
        origin = self.headers.get("Origin")
        return origin is None or origin in self.state.allowed_origins()

    def _read_json(self) -> dict[str, Any] | None:
        """Reads a capped JSON object body. Sends the error and returns None when it is not acceptable."""
        if self.headers.get("Transfer-Encoding"):
            self.close_connection = True
            self._error(HTTPStatus.BAD_REQUEST, MSG_BAD_JSON)
            return None
        try:
            length = int(self.headers.get("Content-Length") or "0")
        except ValueError:
            length = -1
        if length < 0:
            self.close_connection = True
            self._error(HTTPStatus.BAD_REQUEST, MSG_BAD_JSON)
            return None
        if length > MAX_BODY:
            self.close_connection = True
            self._error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, MSG_TOO_LARGE)
            return None
        raw = self.rfile.read(length) if length else b""
        if not raw.strip():
            return {}
        try:
            body = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError, RecursionError):
            self._error(HTTPStatus.BAD_REQUEST, MSG_BAD_JSON)
            return None
        if not isinstance(body, dict):
            self._error(HTTPStatus.BAD_REQUEST, MSG_BAD_JSON)
            return None
        return body

    def _serve_static(self, url_path: str) -> None:
        dist = self.state.dist_dir
        if url_path in ("/", "/index.html"):
            self._send(HTTPStatus.OK, render_index(dist, self.state.token), CONTENT_TYPES[".html"])
            return
        file_path = static_file_path(dist, url_path)
        if file_path is None:
            self._error(HTTPStatus.FORBIDDEN, MSG_FORBIDDEN)
            return
        if os.path.isfile(file_path) and not workshop_data.is_linked_path(file_path, os.path.abspath(dist)):
            extension = os.path.splitext(file_path)[1].lower()
            if extension == ".html":
                # Only index.html is served as HTML, always with the token injected.
                self._send(HTTPStatus.OK, render_index(dist, self.state.token), CONTENT_TYPES[".html"])
                return
            with open(file_path, "rb") as handle:
                data = handle.read()
            content_type = CONTENT_TYPES.get(extension, "application/octet-stream")
            self._send(HTTPStatus.OK, data, content_type, cache=url_path.startswith("/assets/"))
            return
        # SPA fallback: unknown non-API paths get the app shell.
        self._send(HTTPStatus.OK, render_index(dist, self.state.token), CONTENT_TYPES[".html"])


def create_server(state: AppState, first_port: int = FIRST_PORT, last_port: int = LAST_PORT) -> WorkshopServer:
    """Binds 127.0.0.1 on the first free port in the range and records it in the state."""
    last_error: OSError | None = None
    for port in range(first_port, last_port + 1):
        try:
            server = WorkshopServer((HOST, port), state)
        except OSError as error:
            last_error = error
            continue
        state.port = server.server_address[1]
        return server
    raise OSError(f"No hay ningún puerto libre entre {first_port} y {last_port}.") from last_error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Workshop Infrastructure UI (servidor local)")
    parser.add_argument("--infra", default=DEFAULT_INFRA, help="carpeta infra del Workshop")
    parser.add_argument("--port", type=int, default=FIRST_PORT, help="primer puerto a probar (por defecto 8770)")
    parser.add_argument("--no-browser", action="store_true", help="no abrir el navegador")
    args = parser.parse_args(argv)

    infra = os.path.abspath(args.infra)
    if not os.path.isdir(infra):
        print(f"No se encontró la carpeta infra: {infra}", file=sys.stderr)
        return 1
    state = AppState(infra_root=infra, dist_dir=DEFAULT_DIST)
    state.load()
    try:
        server = create_server(state, args.port, max(args.port, LAST_PORT))
    except OSError as error:
        print(str(error), file=sys.stderr)
        return 1
    url = f"http://127.0.0.1:{state.port}/"
    print(f"Workshop está en {url}  (Ctrl+C para cerrar)", flush=True)
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Cerrando Workshop.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
