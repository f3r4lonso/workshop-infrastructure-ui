# UI development plan — "see everything I have"

Status: proposed (2026-10-19). Waiting for the owner's approval at Gate A before any build work.

## 1. Goal

A trader with no developer background opens one window and can, in under a minute, see **everything available in
the Workshop**: agents, skills, tasks, documents, applications, AI-client guides and personal assistants. They can
find any item by typing a word, understand what it is for in plain Spanish, know how to use it, and open its source.

## 2. Boundary (unchanged)

- **Read-only browser.** It reads Markdown and opens files or folders with their Windows association. It never runs
  scripts, AI clients or installers and never writes files. Copying text to the clipboard is allowed.
- **Not the Workshop AI client hub.** The product vision (§17.1) makes the VS Code extension the main UI for client
  sessions, checkpoints and handoffs, with no stand-alone desktop app. The open question of a Workshop AI desktop
  app ([discovery brief](../../../infra/docs/workshop-ai-desktop-app-discovery-brief.md)) is not answered or reopened
  here. No chat, no client launching, no handoffs.
- **Same stack:** Windows PowerShell 5.1 + built-in Windows Forms, no dependencies. Extend `src/main.ps1`; do not
  rebuild.

## 3. Inputs and what each changes in the plan

| Source | Finding used |
|---|---|
| Prompt review of the [task brief](../../../infra/tasks/workshop-infrastructure-windows-ui.md) (`prompt-reviewer`, 2026-10-19, score 3.3/5) | The brief doesn't name all resource types, the source of truth, testable usability criteria, a read-only ban on scripts, the existing app or a plan gate. The current app shows 4 of the infra documents and no applications. It lists a generated adapter file as a client guide, and search only works inside one section. |
| [Product vision](../../../infra/docs/workshop-ai-product-vision.md) | FR-04: the lists must match the catalogue rows, copying no bodies. FR-14: no screens or options without a defined workflow. NFR-06: advanced controls stay out of the way. §17.1: there is no client hub in this app. |
| [Token-optimization review](../../../infra/docs/token-optimization-candidate-review.md) | Adopt no external tools; stay dependency-free. Apply its "catalogues before bodies" and "measured or it doesn't ship" principles. The app can save tokens indirectly: "copy how to use" gives a short prompt with a file path instead of pasted content. Claim no saving without measurement. |
| [Desktop-app discovery brief](../../../infra/docs/workshop-ai-desktop-app-discovery-brief.md) | The real need may be to *know what exists and continue work*. This app covers "know what exists" without touching the provider-terms risk. Its §1 cites a path under `documents/` that does not exist (housekeeping, §8). |

## 4. Screens (Spanish UI text)

```text
┌──────────────┬───────────────────────────────────────────────────────────┐
│ Workshop     │  [ Buscar en todo…                                    ]   │
│              │                                                           │
│ ▸ Inicio     │  Inicio                                                   │
│   Tareas  6  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────┐           │
│   Agentes 22 │  │Tareas  │ │Agentes │ │Skills  │ │Documentos│  …        │
│   Skills  29 │  │6 activas│ │  22    │ │  29    │ │   44     │           │
│   Documentos │  └────────┘ └────────┘ └────────┘ └──────────┘           │
│   Aplicaciones│ Tareas activas: ollama…, workshop-ai-product-foundation…  │
│   Clientes IA│  Modificado recientemente: …                              │
│   Asistentes │  Avisos: 5 documentos no figuran en el mapa del workshop  │
│              │                                                           │
│ Carpeta: …   │                                                           │
├──────────────┴───────────────────────────────────────────────────────────┤
│ Estado: 145 recursos cargados                                            │
└──────────────────────────────────────────────────────────────────────────┘
```

- **Inicio (new home):** one tile per type with its count, active tasks, the 5 most recently changed items, and
  warnings (catalogue rows without a file, files without a catalogue row, documents missing from the workspace map).
  Clicking a tile opens that section.
- **Sections:** Tareas (status filter, active first), Agentes and Skills (grouped by area, from the catalogues),
  Documentos (all of `infra/docs/` plus app `docs/`, grouped by place), Aplicaciones (stack and launch command as
  text, from `WORKSHOP-CONTEXT.md` §2), Clientes IA (`infra/clients/*/README.md` only), Asistentes personales.
- **Global search** in the top bar searches every type by name, description and area, and labels each result with
  its type.
- **Detail pane:** Spanish type label, description, status, area, location. Then **Cómo usarlo**: for a skill `/name`
  (Claude) and `$name` (Codex); for an agent "Usa el agente <name> …"; for a task "Ejecuta la tarea en
  `infra/tasks/<file>`". Each comes with a **Copiar** button. Actions: **Abrir documento**, **Abrir carpeta**.
  **Relacionado:** for a task, the agents and skills it mentions by name.

## 5. Phases

| Phase | Work | Done when |
|---|---|---|
| 0. Brief | Apply the review's rewrites R1–R3 to the task brief, plus a plan gate and the verification steps. Align the catalogue row. | Owner approves the brief diff. |
| 1. Data | Catalogue-driven loader with a disk fallback. Fixed exclusions: `clients/.codex/`, `clients/.agents/`, `vendor/`, `node_modules/`, `.venv/`, secrets patterns. Adds the Documentos, Aplicaciones and Asistentes types, plus the catalogue-vs-disk check. | Counts match the catalogues (22 agents, 29 skills, 12 tasks). The generated adapter file no longer appears. |
| 2. Inicio + search | Home screen, tiles, warnings, global search. | An item of each type is found from the home screen in one search. |
| 3. Detail | "Cómo usarlo" with copy, related items, open folder. | Each type shows a correct usage line. Copying doesn't write any file. |
| 4. Polish | Keyboard order, 200% scaling, high contrast, narrow window, empty and error states, ≤ 2 s load. | Manual checklist done, or each item reported as not checked. |
| 5. Hand-over | README, `ui-review.md`, project page `infra/docs/projects/workshop-infrastructure-ui/`, `WORKSHOP-CONTEXT.md` entry. | Docs updated in the same change. |

## 6. Verification

- Parser check under PowerShell 5.1 and a **launch smoke test**: the window opens, loads, and closes without error.
- Count check against each catalogue, and a check that no excluded path appears.
- A non-UI test script for the loader functions: parsing, exclusions, usage lines.
- Manual first-use test by the owner: find one named agent, skill, task and application without help.
- Report run, passed, failed and not-checked items separately.

## 7. Decisions for the owner (Gate A)

1. Approve this scope and the phase order.
2. May the app copy usage text to the clipboard? (Proposed: yes; it changes no file.)
3. Show completed, retired and superseded tasks? (Proposed: hidden behind the status filter; active shown first.)
4. Applications: open the README only, never launch? (Proposed: yes; the launch command is shown as text.)
5. Approve the brief rewrite in phase 0.

## 8. Housekeeping found while planning

- Git can't read this repository from the owner's account ("dubious ownership"): it was created by the Codex sandbox
  user. The fix is one `git config --global --add safe.directory` entry, or a change of folder ownership. It needs
  the owner's approval.
- The app has no commits yet.
- Five infra documents are not linked from `WORKSHOP-CONTEXT.md`: `workshop.md`, the two language-coverage
  documents, the Suno research and the desktop-app brief.
- The discovery brief's usage line points to `documents/…`. The file is in `infra/docs/`.
