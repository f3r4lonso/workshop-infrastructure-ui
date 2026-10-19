# Workshop Infrastructure UI

- **Purpose:** Local Windows utility for browsing the shared Workshop AI infrastructure's tasks, agents, skills, client guides, and help documents.
- **Stage:** Local MVP.
- **Run:** Double-click `INICIAR.cmd` or run it from PowerShell.
- **Stack:** Windows PowerShell 5.1 and built-in Windows Forms; no third-party runtime dependencies.
- **Constraints:** Read-only browser. It does not launch AI clients, inspect credentials, or change infrastructure files. Keep user-facing text in Spanish and technical documentation in English. Do not add dependencies without user approval.
- **Review:** Manually inspect keyboard flow, empty/error states, accessible labels/focus, path handling, and static code safety. No network listener.

Workspace and infrastructure security rules also apply.
