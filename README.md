# Workshop Infrastructure UI

> **Merging into Workshop AI v2** (decisions D-V2-01/02, approved 2026-10-20): this code moves into
> `applications/workshop-ai/` (done in increment V1, 2026-10-20). This repository is now read-only history:
> develop the app in `workshop-ai`.
> Plan: `infra/docs/workshop-ai-v2/`.

A local web page that shows Workshop resources and opens AI clients. Its right workspace includes a Spanish
reading assistant and an ordered agent-chain builder that passes each completed response to the next selected
Workshop agent.

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

**Reading assistant:** the detail area is a dedicated reading workspace. Open the selected Workshop resource,
enter a Workshop-relative path, paste text, or choose a TXT, Markdown or DOCX file. Review the cleaned original,
request Spanish translation through local Ollama, and listen with browser speech controls. Uploads and pasted text
are processed in memory and are not saved to the Workshop.

**Agent chains:** choose 2–5 distinct agents, order them, add optional directions, select a Claude model, then
explicitly start the chain. Each stage receives your goal and the previous stage's output. A run may consume
account quota. The UI exposes the verified tool-free Claude transport only; access to the signed-in account is
not checked.

**Clientes de IA:** one button per client opens it in a new terminal window in the workspace folder. A client that
is not installed shows "No instalado".

**Keyboard:** Ctrl+F or `/` search, Esc clears it, ↓ or Enter moves to the results, and ↑/↓ move through them.
Selecting a supported document previews it in the right workspace; double-clicking opens it in the associated app.

## Boundary and security

Reading reuses the local reading assistant: text extraction and cleanup run locally, translation is sent to local Ollama only when requested, and browser voices may use an online speech service depending on the chosen voice. A chain sends the selected agent profiles, goal, directions and previous outputs to Claude only after the user starts it. Requests run sequentially; failures and uncertain outcomes stop later stages without retries. Run outputs stay in bounded server memory and are cleared by the user or when the server stops. See [chain design and limits](docs/agent-chain-design.md) and [interaction notes](docs/interaction-upgrade.md).

It opens `.md` files and folders inside the workspace and starts the four fixed AI client
CLIs only when you press their buttons. It never runs task or application commands. The local server
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
