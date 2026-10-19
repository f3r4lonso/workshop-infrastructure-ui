# Web version — architecture and API contract

Status: accepted (2026-10-19). Replaces the Windows Forms window at the owner's request ("hazla en un navegador en
React") and adds buttons that open the AI clients. This is a decision record: it changes the earlier boundary
"never launches AI clients" (see §4).

## 1. Shape

```text
INICIAR.cmd ──► python server\server.py ──► http://127.0.0.1:8770/  (opens the default browser)
                  │  stdlib only (http.server)
                  ├─ serves web\dist\ (React build)
                  └─ /api/*  (JSON)
web\  React 19 + Vite 7 (same stack as Trading-app); built once with `npm install && npm run build`
```

- `server/workshop_data.py` — port of the PowerShell loader: same sources, exclusions, warnings, usage lines,
  Spanish status labels, search synonyms and related-resource matching. Stdlib only.
- `server/server.py` — HTTP server bound to `127.0.0.1` only; serves the build and the API below.
- `web/` — the React app. Talks only to `/api/*` on the same origin.

## 2. API (all JSON, UTF-8)

`GET /api/data` →

```json
{
  "workshopRoot": "C:\\Users\\…\\workshop",
  "loadedMs": 410,
  "sections": ["Tareas", "Agentes", "Skills", "Documentos", "Aplicaciones", "Clientes IA", "Asistentes"],
  "typeLabels": {"Tareas": "Tarea", "...": "..."},
  "items": [
    {
      "id": "agentes:security-reviewer",          // "<section lower, no spaces/accents>:<name or relative path>", unique
      "section": "Agentes", "typeLabel": "Agente",
      "name": "security-reviewer", "title": "security-reviewer",
      "description": "…", "area": "Quality",
      "status": "",                               // raw catalogue status (tasks only)
      "statusLabel": "",                          // Spanish full label, e.g. "Activa, en espera (rev. 2, 2026-10-18)"
      "statusShort": "",                          // "Activa" | "En espera" | "Completada" | "Retirada" | "Sustituida" | ""
      "taskState": "",                            // "active" | "waiting" | "completed" | "retired" | "superseded" | "other" | ""
      "relativePath": "infra\\agents\\quality\\security-reviewer.md",
      "usage": "Usa el agente security-reviewer para ",   // text for Copiar; "" = nothing to copy
      "usageHint": "Pégalo en Claude Code y completa la frase con lo que necesitas.",
      "modified": "2026-10-19T03:19:00",
      "related": ["code-reviewer", "engineering-lifecycle"],  // tasks only: names of agents/skills/assistants the brief mentions
      "canOpenDocument": true, "canOpenFolder": true,
      "searchText": "security-reviewer … quality agente …"   // lower-case, accents removed
    }
  ],
  "warnings": ["…"],
  "searchSynonyms": {"seguridad": ["security", "secret"], "...": []}
}
```

`POST /api/refresh` → same body as `GET /api/data`, re-read from disk.

`POST /api/open` body `{"id": "<item id>", "target": "document" | "folder"}` → `{"ok": true, "message": "Abriendo …"}`
or `{"ok": false, "message": "<Spanish reason>"}`. The server resolves the path from its own item list by id;
the client never sends a path. Documents: only `.md` inside the workspace; folders: inside the workspace only.
Opened with the Windows file association (`os.startfile`).

`GET /api/clients` → `{"clients": [{"id": "claude", "name": "Claude Code", "installed": true, "command": "claude"}, …]}`
for exactly `claude`, `codex`, `gemini`, `copilot` (`installed` from `shutil.which`).

`POST /api/launch` body `{"client": "claude" | "codex" | "gemini" | "copilot"}` → opens a new terminal window in the
workspace root running that CLI with no arguments: Windows Terminal (`wt.exe -d <root> --title <name> cmd /k <command>`)
when available, else `cmd /c start "<name>" /D <root> cmd /k <command>`. Returns `{"ok": true, "message": "Abriendo Claude Code en una ventana nueva…"}`
or `{"ok": false, "message": "<Spanish reason, e.g. no está instalado>"}`.

Errors: unknown route 404, bad JSON 400, forbidden 403 — always `{"ok": false, "message": "<Spanish>"}`.

## 3. Security rules for the server

- Bind `127.0.0.1` only (port 8770; if busy, the next free port up to 8790).
- Every request: the `Host` header must be `127.0.0.1:<port>` or `localhost:<port>` (blocks DNS rebinding), else 403.
- Every `POST`: header `X-Workshop-Token` must equal a random token generated at start-up (`secrets.token_urlsafe(32)`)
  and injected into the served `index.html` as `<meta name="workshop-token" content="…">`; if an `Origin` header is
  present it must equal `http://127.0.0.1:<port>` or `http://localhost:<port>`. No CORS headers are ever sent.
- `POST` bodies are capped at 4 KB and must be JSON.
- The only processes started are the four fixed client commands and `os.startfile` on a validated `.md` file or folder.
  No request value is ever placed in a command line.
- Static files are served only from `web/dist/` (path traversal rejected).
- The loader keeps the PowerShell version's exclusions: no secrets, generated adapters, vendored folders, junctions
  or out-of-workspace links. Nothing is written to disk.

Accepted risk: any program already running on this PC as the same Windows user can read the page and its token from
`127.0.0.1` and press the same buttons. Such a program could start those clients itself, so the server adds no new
power for it. The token and Host/Origin checks exist to stop other websites and other machines.

Hardening added after the security review (2026-10-19):

- Clients resolve to absolute paths found on PATH only, never in the current folder or the workspace; the child
  environment sets `NoDefaultCurrentDirectoryInExePath=1`.
- No launch happens when a path contains shell metacharacters (`; & | ^ % " < >`).
- Each connection has a 10-second socket timeout.
- Each client has a 3-second launch debounce.
- A Content-Security-Policy is sent.
- Catalogue links must point to `.md` files.

## 4. Boundary change

Before: read-only, never launches AI clients. Now: still never writes files; it may open `.md` files and folders and
start the four AI client CLIs in a new terminal window in the workspace root, only when the user presses the button.
It still never runs scripts, installers, tasks or application commands (those remain text to copy). It is not a
session/handoff hub (that stays with Workshop AI).
