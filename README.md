# Workshop Infrastructure UI

A local web page that shows everything in the Workshop (tasks, agents, skills, documents, applications,
AI-client guides and personal assistants) and opens your AI clients (Claude Code, Codex CLI, Gemini CLI,
GitHub Copilot CLI) with one click. Find any item by typing, see what it is for and how to use it, copy the
ready-to-paste text, and open its document or folder.

## Start

Double-click `INICIAR.cmd`. It opens http://127.0.0.1:8770/ in your browser. Keep the black window open while you
use the page; close it to stop the app.

The first start builds the interface (`npm install` and `npm run build` in `web\`), which takes about a minute and
needs Node.js. Later starts are instant. Python 3.12 is required; no Python packages are installed.

## What it shows

| Section | Source of truth |
|---|---|
| Inicio | Counts per type, active tasks, the 5 most recently changed items, and warnings |
| Tareas | `infra/docs/catalogues/tasks.md` rows (status filter: active by default) |
| Agentes, Skills | `infra/docs/catalogues/agents.md` and `skills.md` rows, grouped by area |
| Documentos | `WORKSHOP-CONTEXT.md`, `infra/README.md`, `infra/SECURITY.md`, `infra/docs/**`, `applications/*/docs/*.md` |
| Aplicaciones | `applications/*` folders, described by the table in `WORKSHOP-CONTEXT.md` §2 |
| Clientes IA | `infra/clients/*/README.md` |
| Asistentes | `infra/agents/personal-assistants/*.md` |

**Detail panel:** what the item is for; **Cómo usarlo** with **Copiar** (ready-to-paste text: `/workshop:<skill>`,
`Usa el agente workshop:<agent> para `, the task path for active tasks, `claude --agent workshop:<assistant>`, an
application's start command as text) and where to paste it; **Relacionado** for tasks; **Abrir documento** and
**Abrir carpeta**.

**Clientes de IA:** one button per client opens it in a new terminal window in the workspace folder. A client that
is not installed shows "No instalado".

**Keyboard:** Ctrl+F or `/` search, Esc clears it, ↓ or Enter moves to the results, ↑/↓ move in the list, Enter
opens the document.

## Boundary and security

Never writes files. It opens only `.md` files and folders inside the workspace, and starts only the four AI client
CLIs, each only when you press its button. Task and application commands stay as text to copy. The local server
listens on 127.0.0.1 only and accepts actions only from its own page (Host check, a random per-start token, Origin
check, fixed command list). Details: [docs/web-architecture.md](docs/web-architecture.md).

## Files

- `server/workshop_data.py` reads the Workshop (stdlib only). `server/server.py` is the local server and API.
- `web/` holds the React 19 + Vite 7 interface; `web/dist/` is the build output (not committed).
- `tests/` holds the Python tests (`test_*.py`) and the legacy PowerShell loader test.
- `src/` holds the previous Windows Forms version (legacy, not maintained).
- `docs/` holds the plan, architecture and review record.

## Verify

```powershell
python -m unittest discover -s tests -v
cd web; npm run build
```
