# UI/UX review

## Planning boundary

The active task is an infrastructure browser, not a second Workshop AI client hub. Workshop AI's product vision names its VS Code extension as the main UI and treats a standalone orchestration app as undecided. This project therefore only reads shared infrastructure documents and opens them in the Windows-associated editor. It does not manage client sessions, task checkpoints, or handoffs.

## Primary flow

1. Open the app and land on active task resources.
2. Search or use the left navigation to browse tasks, agents, skills, client guides, and help documents.
3. Select a result and review its summary, declared status, and relative source path.
4. Open the canonical Markdown document.

## Visual and interaction decisions

- Native Windows Forms controls and Segoe UI keep the utility familiar and dependency-free.
- A persistent left navigation, searchable list, and detail pane support scanning without a dashboard full of decorative cards.
- The selected item is explicit; the only resource action is labeled “Abrir documento”.
- Search and task-status filters update the list immediately. Refresh rereads the source files.
- Missing infrastructure, no matches, missing files, and open failures show direct Spanish guidance.
- The layout supports window resizing; keyboard navigation uses standard Windows control behavior.

## Accessibility and limitations

- Controls have accessible names, visible text labels, and standard keyboard focus behavior.
- Status is written in text and errors use both text and a color change.
- Manual Windows screen-reader, high-contrast, 200% text-scaling, and narrow-window review was not available in this implementation session. These remain acceptance checks on a Windows desktop.
- The app intentionally does not execute scripts or inspect client installation/authentication state.

## Review outcome

Static UI/UX and accessibility reviews found and prompted fixes for Windows PowerShell 5.1 text encoding, the initial active-task filter, toolbar fit at minimum width, visibility of unreadable documents, status-bar width, high-contrast colors, and keyboard access to the resource summary. Those fixes are in the current source. The PowerShell 5.1 parser reports no syntax errors, and the built-in Windows Forms assembly loads in the current environment.

No app window was launched in this review. Confirm rendering and behavior on a Windows desktop, including Narrator or NVDA status announcements, 200% scaling, high contrast, minimum-window resizing, folder selection, and opening Markdown with and without a file association.
