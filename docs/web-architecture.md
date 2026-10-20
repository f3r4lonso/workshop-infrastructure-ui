# Web version — architecture and API contract

> **v2 note (2026-10-20):** this app is merging into Workshop AI v2 (decisions D-V2-01/02 approved 2026-10-20; `infra/docs/workshop-ai-v2/architecture.md`), which keeps this security model as its minimum. §3 and §4 were corrected in V0 to describe the processes and file writes the server already has.

Current extensions: [interaction upgrade decision, eligibility and verification](interaction-upgrade.md) and [ordered agent-chain design](agent-chain-design.md). The React workspace exposes the reader and a sequential chain editor. Existing scoped editing and single-request dispatch routes remain on the server but are not exposed by the current UI. Original launch API protections remain applicable.

Interaction API: `POST /api/interaction/{document,save,read,prepare-text,upload,translate,reader-status,registry,dispatch,chain-start,chain-current,chain-status,chain-stop,chain-clear}`. All require token, Host and an explicit same-origin Origin. JSON is capped at 2 MB except `upload`, capped at 28 MiB to carry a 20 MB base64 file; other routes retain 4 KB. Document/read accept a catalogue `id` or workspace-relative `path`; only the reader permits DOCX. Document returns raw UTF-8 text, SHA-256 `version`, eligibility and reason. Save accepts `id`, `text`, `version`, returns conflict without overwriting on mismatch. Text editing and pasted-text preparation are capped at 1 MB. Read and in-memory upload reuse the sibling reader extraction/cleanup/detection, capped at 20 MB; uploads are not persisted. Translate accepts explicit text and uses only local Ollama, preserving its own length limits. Chain start validates 2–5 distinct canonical agent IDs and starts one bounded in-memory worker; current/status/stop/clear are same-origin POST actions. The page can recover the active/latest run while the server is running. No prompt, profile or output is logged or saved to disk. The fixed `GET /reader/speech-text.js` serves the reader's speech helper. No permissive CORS or cross-origin proxy is introduced.

Registry separates documented capabilities and public model aliases from unknown authentication/access. Refresh rescans executable availability; no credentials are inspected. Dispatch validates client/model/mode/agent/destination, passes all content through stdin, disables tools/integrations and uses an isolated working directory. New requests only; existing terminals are not destinations. Agent chains call this verified Claude transport once per stage, in order, and pass the previous response as untrusted text alongside the original goal. A failure, uncertain outcome or stop request prevents later stages; no request is retried. One chain runs at a time; active requests cannot be interrupted, and completed run state expires from bounded server memory or is cleared explicitly. Responses are plain escaped text. Output/time/concurrency are bounded. Adapter limitations and provenance are recorded in the interaction decision.

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
- Processes started: the four fixed client console commands; `os.startfile` on a validated `.md` file or folder;
  `<client> --version` (5-second timeout) to detect installed clients; the tool-free `claude -p` dispatch used by
  chains (request text on stdin only); and, after a successful agent save, `infra/scripts/codex-adapter.py` to
  regenerate adapters. No request value is ever placed in a command line.
- Static files are served only from `web/dist/` (path traversal rejected).
- The loader keeps the PowerShell version's exclusions: no secrets, generated adapters, vendored folders, junctions
  or out-of-workspace links. The only disk write is the guarded `save` route (allowlisted Workshop documents,
  hash-checked against the version the page loaded); no screen calls it yet.

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

Before: read-only, never launches AI clients. Now: it writes files only through the guarded `save` route (not yet
used by any screen); it may open `.md` files and folders,
start the four AI client CLIs in a new terminal window, and send an explicitly started, bounded chain of text-only
requests through the verified Claude transport. It still never runs scripts, installers, tasks or application
commands (those remain text to copy). Chain state is in-memory only, not a resumable client session.
