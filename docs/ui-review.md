# UI/UX review

## Iteration 3: web version (2026-10-19)

The owner rejected the desktop technology and asked for a React app in the browser, with buttons that open the AI
clients. Architecture, API and security rules: [web-architecture.md](web-architecture.md).

| Step | Who (Workshop role) | Result |
|---|---|---|
| Server + data port (Python stdlib) | `python-pro` | Port of the PowerShell loader; on the real workspace all 115 items match field by field |
| React interface | `frontend-developer` | Carries over the approved look: navy sidebar, tiles, two-line rows, group headers, detail panel; light and dark themes |
| Security review | `security-reviewer` | 0 blockers. 4 should-fix items applied: clients resolved only from PATH (a planted `claude.cmd` in the workspace can't run), metacharacter guard, socket timeout, CSP. Same-user local processes are an accepted risk |
| UX + accessibility review | `ui-ux-tester` + `accessibility-expert` | 0 blockers. 7 should-fix items applied: detail scrolls into view on narrow screens, announced result counts, 3:1 control borders, compact 2×2 launch buttons, search reachable on narrow screens, "Abrir un cliente de IA" label, launch progress feedback |

Verification:

- `python -m unittest discover -s tests`: 71 of 71 pass. Process starts and file opens are mocked.
- `npm run build`: succeeds, with a 79 kB gzip bundle.
- Live server checks:
  - the page carries its token;
  - a POST without the token returns 403;
  - a foreign Host returns 403;
  - the CSP header is present.
- Headless Edge screenshots were captured at 1366×860 and 1366×768 in light and dark themes, and at 500 px wide.

Not checked:

- Pressing the launch buttons for real.
- A real screen reader.
- Widths below 500 px. The headless browser cannot render them.
- The owner's own first-use test.

The Windows Forms version in `src/` is kept as legacy and is no longer maintained.

## Iteration 2 ("see everything I have")

Date: 2026-10-19. Plan: [ui-development-plan.md](ui-development-plan.md).

## Boundary (unchanged)

An infrastructure browser, not a Workshop AI client hub. It reads Markdown and opens `.md` files and folders with
their Windows association; it never runs scripts, AI clients or installers, never writes files, and copies text to
the clipboard only when the user presses **Copiar**.

## Gate A decisions applied

The owner asked to develop the project; the plan's proposed answers were applied:

1. Scope and phase order as planned.
2. Clipboard copy of usage text: yes.
3. Completed, retired and superseded tasks: hidden behind the status filter (default «Activas»), and marked
   "No ejecutar" with nothing to copy.
4. Applications: open the README or folder only; the launch command is shown and copied as text, never run.
5. Brief rewrite: the scope details were added to `infra/tasks/workshop-infrastructure-windows-ui.md`.

## What changed

- **Data layer** (`src/loader.ps1`, new, no UI): catalogue rows are the source of truth for tasks, agents and
  skills, with a disk fallback and consistency warnings; new types Documentos, Aplicaciones (from the
  `WORKSHOP-CONTEXT.md` §2 table) and Asistentes; Clientes IA lists only `infra/clients/*/README.md`.
  Exclusions: generated adapters, vendored and dependency folders, client config folders, secret-like files, links
  that leave the workspace, and anything reached through a junction or symbolic link.
- **Window** (`src/main.ps1`): Inicio home with tiles, active tasks, the 5 most recent changes and warnings; global
  search across every type (accent-insensitive, Spanish synonyms for common words, whole-word matching for short
  words); detail pane with **Cómo usarlo** + **Copiar**, a short explanation, **Relacionado** for tasks,
  **Abrir documento** and **Abrir carpeta**. Data is loaded once and re-read only on **Actualizar** / F5.
- **Launcher:** runs with `-ExecutionPolicy RemoteSigned` for that process only, so stock Windows installs whose
  default policy blocks scripts can start it; scripts downloaded from the internet stay blocked.

## Reviews run

| Reviewer (Workshop agent) | Blockers found | Outcome |
|---|---|---|
| `code-reviewer` + `security-reviewer` | 2: crash when selecting 3 of 12 tasks; third list column always blank | Both fixed and covered by tests |
| `accessibility-expert` (with `wcag-audit-patterns`) | 2: status messages not announced; detail pane clipped at minimum size | Status now exposes its text and raises a UI Automation notification where .NET supports it (not verified with a screen reader); main area scrolls instead of clipping |
| `ui-ux-tester` | 0 (10 defects) | Fixed: copy text ready to paste, taller usage box, inactive and waiting tasks, short-word and trader-word search, filter hidden during search, double render, Spanish status text, nav/tile counts, wording |

Should-fix items also fixed: hostile or malformed catalogue links (skipped with a warning instead of aborting the
load), out-of-workspace folders, junction following, links with spaces, front-matter-only field parsing, titles
inside code fences, visible focus border on flat buttons, current section shown in bold with a marker, tab order
(sections → search → list → detail), Esc anywhere clears the search, Enter in search goes to the list, tabbing into
the list selects the first item, long labels wrap, window size clamped to the screen, `&` no longer hidden in labels.

## Verification report

| Check | Result |
|---|---|
| PowerShell 5.1 parser, `main.ps1` and `loader.ps1` | Passed, 0 errors |
| `tests/loader.tests.ps1` (147 checks: parsing, exclusions, hostile links, junction, counts, usage lines, search, related list) | Passed, 147 of 147 |
| Counts vs catalogues | Passed: 12 tasks, 22 agents, 29 skills (plus 40 documents, 5 applications, 2 client guides, 3 assistants) |
| Load time ≤ 2 s | Passed: about 0.4 s for 113 resources |
| Launch smoke test (opens the window, visits every section, selects every task, runs 4 searches, closes) | Passed, exit code 0, 0 errors, about 3 s including PowerShell start-up |
| One search finds an item of each type | Passed (ui-ux-tester) |
| Copy writes no file | Passed by code review: clipboard only |
| Keyboard flow, focus visibility, Narrator/NVDA, 200% scaling, high contrast, 780×560 window | **Not checked**: needs a person at a Windows desktop |
| Owner's first-use test (find one agent, skill, task and application without help) | **Not checked** |

## Visual redesign (2026-10-19, after the owner's first look)

The owner found the first version visually poor. `ui-designer` restyled `src/main.ps1` in two passes. The result has:

- a navy sidebar with a bar marking the current section;
- a search field with an icon;
- coloured cards for each resource type on Inicio;
- custom-drawn two-line list rows with type and status labels and group header rows;
- a detail card beside the list, which moves below it on narrow windows.

`accessibility-expert` and `ui-ux-tester` reviewed the first pass and found no blockers. Their 11 should-fix items were applied in the second pass:

- unfocused selection made visible;
- safe fallbacks when custom drawing fails;
- sidebar contrast;
- stable layout between sections;
- empty detail state;
- short status labels;
- no section highlighted while searching;
- full detail card reachable at 780×560.

High-contrast mode keeps default drawing. Verified after the second pass:

- parser check: 0 errors;
- loader tests: 150 of 150 passed;
- smoke test: 0 errors;
- screenshots of five screens were captured and inspected.

To capture the screenshots again, set `WORKSHOP_UI_SCREENSHOT_DIR` to an existing folder and run `src\main.ps1`.

## Known limitations

- **Descriptions are in English** for agents, skills, tasks and most documents, because the catalogues are written in
  English and the app copies no bodies. UI text, statuses and usage hints are Spanish. A Spanish summary per item
  would need a maintained translation; this is an open decision for the owner.
- The process is DPI-unaware: at 200% Windows scales the whole window as a bitmap, so it stays laid out correctly but
  looks slightly blurry.
- High-contrast mode is read at start-up; switching it while the app is open needs a restart.
- The screen-reader announcement of status changes depends on the installed .NET Framework version and is
  unverified.
- "Relacionado" matches agent and skill names in the task brief text, so it only finds resources the brief names
  explicitly.
