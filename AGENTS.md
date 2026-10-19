# Workshop Infrastructure UI

- **Purpose:** Local browser app that shows everything in the Workshop (tasks, agents, skills, documents, applications, AI-client guides, personal assistants) and opens the AI clients (Claude Code, Codex CLI, Gemini CLI, GitHub Copilot CLI).
- **Stage:** Local MVP, iteration 3: web version ([architecture and API contract](docs/web-architecture.md), [plan](docs/ui-development-plan.md), [review](docs/ui-review.md)).
- **Run:** Double-click `INICIAR.cmd` (first run builds the interface), or `python server\server.py` → http://127.0.0.1:8770/.
- **Test:** `python -m unittest discover -s tests -v`; front end: `cd web; npm run build`.
- **Stack:** Python 3.12 standard library (`server/`) + React 19 / Vite 7, plain JavaScript (`web/`). Exact pinned npm versions: react, react-dom, vite, @vitejs/plugin-react only. Do not add dependencies without user approval (run the `dependency-license-review` skill first).
- **Boundary:** Never writes files. It may open `.md` files and folders inside the workspace and start the four AI client CLIs in a new terminal window in the workspace root, only on a button press. It never runs scripts, installers, tasks or application commands; those stay as text to copy. Not a session/handoff hub (that is Workshop AI).
- **Server security (do not weaken):** bound to 127.0.0.1; Host check on every request; random token + Origin check on every POST; fixed command allow-list; no request data in command lines; no CORS headers. Details: `docs/web-architecture.md` §3.
- **Text:** user-facing text in Spanish; code, comments and docs in English.
- **Legacy:** `src/` holds the previous Windows Forms version (PowerShell 5.1); it is not maintained.

Workspace and infrastructure security rules also apply.
