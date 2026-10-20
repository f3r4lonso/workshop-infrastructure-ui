# Workshop Infrastructure UI

- **Purpose:** Local browser app that shows everything in the Workshop (tasks, agents, skills, documents, applications, AI-client guides, personal assistants) and opens the AI clients (Claude Code, Codex CLI, Gemini CLI, GitHub Copilot CLI).
- **v2:** merging into Workshop AI v2 (D-V2-01/02, approved 2026-10-20); the move happens in increment V1 (`infra/docs/workshop-ai-v2/roadmap.md`). The app may write files only through the guarded `save` route and the v2 allowlist (D-V2-07).
- **Stage:** Local MVP, iteration 3: web version ([architecture and API contract](docs/web-architecture.md), [plan](docs/ui-development-plan.md), [review](docs/ui-review.md)).
- **Run:** Double-click `INICIAR.cmd` (first run builds the interface), or `python server\server.py` → http://127.0.0.1:8770/.
- **Test:** `python -m unittest discover -s tests -v`; front end: `cd web; npm run build`.
- **Stack:** Python 3.12 standard library (`server/`) + React 19 / Vite 7, plain JavaScript (`web/`). Exact pinned npm versions: react, react-dom, vite, @vitejs/plugin-react only. Do not add dependencies without user approval (run the `dependency-license-review` skill first).
- **Boundary:** The right workspace provides local reading and explicitly started sequential agent chains. A chain runs 2–5 unique canonical profiles through the verified tool-free Claude transport, passing each output to the next stage; each stage may consume account quota. Run state is bounded and memory-only. The reader may process selected or relative-path Workshop files, pasted text and supported uploads in memory; only an explicit translation sends reviewed text to local Ollama. Browser voices may use an online service. Details and limits: [agent-chain design](docs/agent-chain-design.md), [interaction notes](docs/interaction-upgrade.md). The app may open documents/folders and launch the four fixed client consoles on button press. No arbitrary application source edits, terminal input injection, installers, tasks or application commands.
- **Server security (do not weaken):** bound to 127.0.0.1; Host check on every request; random token + Origin check on every POST; fixed command allow-list; no request data in command lines; no CORS headers. Details: `docs/web-architecture.md` §3.
- **Text:** user-facing text in Spanish; code, comments and docs in English.
- **Legacy:** `src/` holds the previous Windows Forms version (PowerShell 5.1); it is not maintained.

Workspace and infrastructure security rules also apply.
