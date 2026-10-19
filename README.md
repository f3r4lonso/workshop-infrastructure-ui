# Workshop Infrastructure UI

A local, read-only Windows utility for finding shared Workshop resources and opening their canonical Markdown documents.

## Start

Double-click `INICIAR.cmd`. Windows PowerShell 5.1 and Windows Forms are built into supported Windows installations. No package install, network listener, or account login is required.

If the app cannot find the infrastructure folder automatically, choose the `infra` folder with **Elegir carpeta…**. The selected directory must contain `tasks/` and `agents/`.

## What it does

- Browse and search tasks, agents, skills, client guides, and core help documents.
- Filter tasks by their declared status.
- Open a selected resource's original Markdown file in its associated editor.
- Choose a different local `infra` folder when the default sibling folder is unavailable.

The app only reads Markdown files and opens them in the editor associated by Windows. It does not run AI clients, alter infrastructure files, inspect credentials, or communicate over the network.

## Review notes

The UI is designed around a keyboard-accessible navigation list, search, explicit selection, visible empty/error feedback, and one clear open-document action. See `AGENTS.md` for project constraints. Manual desktop and assistive-technology review remains necessary on a Windows machine.
