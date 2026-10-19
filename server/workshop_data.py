"""Data layer for Workshop Infrastructure UI (port of src/loader.ps1).

Everything is read-only: files are read as text and nothing is executed or written.
Standard library only.
"""

from __future__ import annotations

import os
import re
import stat
import time
import unicodedata
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import unquote

SECTIONS: list[str] = ["Tareas", "Agentes", "Skills", "Documentos", "Aplicaciones", "Clientes IA", "Asistentes"]
TYPE_LABELS: dict[str, str] = {
    "Tareas": "Tarea",
    "Agentes": "Agente",
    "Skills": "Skill",
    "Documentos": "Documento",
    "Aplicaciones": "Aplicación",
    "Clientes IA": "Guía de cliente IA",
    "Asistentes": "Asistente personal",
}

# Folders that are generated, vendored or private, and file names that may hold secrets.
# PowerShell's -match is case-insensitive, hence re.IGNORECASE.
EXCLUDED_FOLDER_RE = re.compile(
    r"\\(vendor|node_modules|\.venv|\.git|\.claude|\.codex|\.gemini|clients\\\.codex|clients\\\.agents)(\\|$)",
    re.IGNORECASE,
)
EXCLUDED_NAME_RE = re.compile(
    r"^(\.env.*|auth\.json|\.credentials\.json|settings\.local\.json"
    r"|.*(secret|token|credential).*\.(json|txt|ya?ml|ini|xml|config|toml)|.*\.(key|pem|pfx|p12))$",
    re.IGNORECASE,
)

# Claude Code loads the shared agents, skills and personal assistants from the "workshop" plugin
# (infra/.claude-plugin/plugin.json), so their names carry this prefix there. Codex CLI has no prefix.
PLUGIN_PREFIX = "workshop:"

UNREADABLE = "No se pudo leer el archivo. Comprueba los permisos y pulsa Actualizar."
NOT_CATALOGUED_AREA = "Sin catálogo"
_FILE_ATTRIBUTE_HIDDEN = getattr(stat, "FILE_ATTRIBUTE_HIDDEN", 2)

# Spanish search words mapped to the English stems used in catalogue descriptions (matched as substrings).
SEARCH_SYNONYMS: dict[str, list[str]] = {
    "seguridad": ["security", "secret"], "secretos": ["secret"], "revisor": ["review"], "revisar": ["review"],
    "revision": ["review"], "auditar": ["audit"], "auditoria": ["audit"], "diseno": ["design"],
    "disenar": ["design"], "interfaz": ["interface", "ui"], "pantalla": ["ui", "screen"], "prueba": ["test"],
    "pruebas": ["test"], "probar": ["test"], "accesibilidad": ["accessib", "wcag"], "teclado": ["keyboard"],
    "errores": ["error", "debug"], "fallo": ["error", "fail", "debug"], "depurar": ["debug"], "riesgo": ["risk"],
    "estrategia": ["strategy"], "datos": ["data"], "mercado": ["market"], "ordenes": ["order"], "orden": ["order"],
    "musica": ["music"], "cancion": ["music", "track"], "escribir": ["writ"], "redactar": ["writ"],
    "traducir": ["translat"], "traduccion": ["translat"], "planificar": ["plan"], "idea": ["idea"],
    "documentacion": ["doc"], "rendimiento": ["performance"], "dependencias": ["dependenc"], "licencia": ["license"],
    "precio": ["price", "market", "candle"], "precios": ["price", "market", "candle"],
    "dinero": ["capital", "money", "risk"],
    "operar": ["trad", "order"], "operaciones": ["trad", "order"], "bot": ["algo", "bot", "strateg"],
    "notas": ["note", "doc"],
    "velas": ["candle"], "graficos": ["chart"], "bolsa": ["exchange", "market"], "agente": ["agent"],
    "agentes": ["agent"],
    "tarea": ["task"], "tareas": ["task"], "leer": ["read"], "voz": ["aloud", "voice"],
    "activa": ["active"], "activas": ["active"], "completada": ["completed"], "completadas": ["completed"],
    "repositorio": ["repo"], "ramas": ["branch"], "subir": ["push"], "extension": ["extension"],
}

STATUS_WORDS: dict[str, str] = {
    "active": "Activa", "waiting": "Activa, en espera", "completed": "Completada",
    "retired": "Retirada", "superseded": "Sustituida",
}
SHORT_STATUS: dict[str, str] = {
    "active": "Activa", "waiting": "En espera", "completed": "Completada",
    "retired": "Retirada", "superseded": "Sustituida",
}


@dataclass
class Resource:
    section: str
    type_label: str
    name: str
    title: str
    description: str
    status: str
    area: str
    path: str
    relative_path: str
    usage: str
    usage_hint: str
    modified: datetime | None
    search_text: str


@dataclass
class WorkshopData:
    infra_root: str
    workshop_root: str
    items: list[Resource] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


# --- Path rules ---------------------------------------------------------------------------------------------

def _windows_path(path: str) -> str:
    return path.replace("/", "\\")


def is_excluded_path(path: str) -> bool:
    if not path:
        return True
    path = _windows_path(path)
    if EXCLUDED_FOLDER_RE.search(path):
        return True
    return bool(EXCLUDED_NAME_RE.match(ntpath_basename(path)))


def ntpath_basename(path: str) -> str:
    return path.rstrip("\\").rsplit("\\", 1)[-1] if "\\" in path else path


def _is_link(path: str) -> bool:
    """True for a junction or symbolic link (the path itself, not its target)."""
    p = Path(path)
    try:
        return p.is_symlink() or p.is_junction()
    except OSError:
        return False


def is_linked_path(path: str, root: str) -> bool:
    """True when the path, or any folder between it and the root, is a junction or symbolic link."""
    root_path = root.rstrip("\\")
    current = path
    while current and len(current) > len(root_path):
        if _is_link(current):
            return True
        parent = os.path.dirname(current)
        if parent == current:
            break
        current = parent
    return False


def is_inside_root(path: str, root: str) -> bool:
    return bool(path) and path.lower().startswith(root.rstrip("\\").lower() + "\\")


def is_allowed_path(path: str, workshop_root: str) -> bool:
    """A path the app may list: inside the workspace, not excluded, not reached through a junction or link."""
    if not is_inside_root(path, workshop_root):
        return False
    if is_excluded_path(path):
        return False
    return not is_linked_path(path, workshop_root)


def relative_workshop_path(path: str, workshop_root: str) -> str:
    root = workshop_root.rstrip("\\")
    if workshop_root and path.lower().startswith(root.lower() + "\\"):
        return path[len(root) + 1:]
    return path


_INVALID_PATH_CHARS = re.compile(r'[<>"|?*\x00-\x1f]')


def resolve_link(base_folder: str, link: str) -> str:
    """Resolves a relative catalogue link. Returns '' for absolute links, links with a scheme, non-.md targets or unresolvable ones."""
    clean = unquote(link.strip().split("#")[0]).replace("/", "\\")
    if not clean or ":" in clean or clean.startswith("\\"):
        return ""
    if _INVALID_PATH_CHARS.search(clean):
        return ""
    try:
        path = os.path.normpath(os.path.join(base_folder, clean))
    except (ValueError, OSError):
        return ""
    # Catalogue rows only ever point at Markdown files; anything else is treated as an invalid link.
    return path if path.lower().endswith(".md") else ""


# --- Text helpers -------------------------------------------------------------------------------------------

def read_text_file(path: str) -> str:
    # newline='' keeps CRLF so the regexes behave as in .NET; utf-8-sig drops a BOM like ReadAllText does.
    with open(path, encoding="utf-8-sig", errors="replace", newline="") as handle:
        return handle.read()


def remove_diacritics(text: str | None) -> str:
    if not text:
        return ""
    decomposed = unicodedata.normalize("NFD", text)
    stripped = "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")
    return unicodedata.normalize("NFC", stripped).lower()


_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]*\)")


def to_plain_text(text: str | None) -> str:
    """Turns a Markdown table cell into plain text: links become their label, code ticks and bold marks go."""
    if not text:
        return ""
    plain = _LINK_RE.sub(r"\1", text)
    return plain.replace("`", "").replace("**", "").strip()


_FENCE_RE = re.compile(r"^```.*?^```", re.M | re.S)
_TITLE_RE = re.compile(r"^#\s+(.+?)\s*$", re.M)
_FRONT_MATTER_RE = re.compile(r"\A\ufeff?---\r?\n(.*?)\r?\n---", re.S)
_FRONT_MATTER_STRIP_RE = re.compile(r"\A\ufeff?---\r?\n.*?\r?\n---\r?\n", re.S)


def get_title(text: str, fallback: str) -> str:
    match = _TITLE_RE.search(_FENCE_RE.sub("", text))
    if match:
        return to_plain_text(match.group(1))
    return fallback


def get_field(text: str, name: str) -> str:
    """Reads a field from the YAML front matter only (the block between the first two --- lines)."""
    front = _FRONT_MATTER_RE.search(text)
    if not front:
        return ""
    pattern = r"^" + re.escape(name) + r"""[:][ \t]*(?:"([^"]*)"|'([^']*)'|([^\r\n]+?))[ \t]*$"""
    match = re.search(pattern, front.group(1), re.M)
    if not match:
        return ""
    for group in (1, 2, 3):
        value = match.group(group)
        if value is not None:
            value = value.strip()
            return "" if value in (">", "|", ">-", "|-") else value
    return ""


def get_first_paragraph(text: str, heading: str) -> str:
    section = re.search(
        r"^##\s+(?:\d+\.\s*)?" + re.escape(heading) + r"\s*\r?\n(.*?)(?=^##\s|\Z)", text, re.M | re.S
    )
    if not section:
        return ""
    paragraph: list[str] = []
    for line in re.split(r"\r?\n", section.group(1)):
        trimmed = line.strip()
        if not trimmed:
            if paragraph:
                break
            continue
        if trimmed.startswith(("- ", "|", "```")):
            break
        paragraph.append(trimmed)
    return to_plain_text(" ".join(paragraph))


_SKIP_PARAGRAPH_RE = re.compile(r"^(#|\||>|---|[-*+]\s|\d+\.\s|Status:|Last checked:|<)", re.IGNORECASE)


def get_document_summary(text: str) -> str:
    """A short summary for documents without a catalogue row: a known section, else the first prose paragraph."""
    for heading in ("Purpose", "Objective", "Overview", "Goal", "Summary"):
        paragraph = get_first_paragraph(text, heading)
        if paragraph:
            return paragraph
    body = _FRONT_MATTER_STRIP_RE.sub("", text, count=1)
    body = _FENCE_RE.sub("", body)
    for paragraph in re.split(r"(?:\r?\n){2,}", body):
        lines = [line.strip() for line in re.split(r"\r?\n", paragraph)]
        lines = [line for line in lines if line]
        if not lines:
            continue
        if _SKIP_PARAGRAPH_RE.match(lines[0]):
            continue
        summary = to_plain_text(" ".join(lines))
        if len(summary) > 400:
            summary = summary[:397].rstrip() + "…"
        return summary
    return ""


# --- Status and usage ---------------------------------------------------------------------------------------

def get_task_state(status: str | None) -> str:
    """active, waiting (active but starts only after another task), completed, retired, superseded or other."""
    status = status or ""
    if re.match(r"\s*active", status, re.IGNORECASE):
        if re.search(r"starts only after", status, re.IGNORECASE):
            return "waiting"
        return "active"
    for state in ("completed", "retired", "superseded"):
        if re.match(r"\s*" + state, status, re.IGNORECASE):
            return state
    return "other"


def get_status_label(status: str | None) -> str:
    """Spanish status for display: the state word plus any date or revision in parentheses."""
    if not status:
        return ""
    state = get_task_state(status)
    if state not in STATUS_WORDS:
        return status
    detail = re.search(r"\(([^)]*)\)", status.split(";")[0])
    if detail:
        return f"{STATUS_WORDS[state]} ({detail.group(1)})"
    return STATUS_WORDS[state]


def get_usage(section: str, name: str, relative_path: str, command: str = "", status: str = "") -> tuple[str, str]:
    """Returns (copy, hint). Copy is pasted as-is into an AI client or terminal; an empty copy disables the button."""
    copy = f"Lee el documento {relative_path}"
    hint = "Pégalo en tu cliente de IA para que lo use como contexto, o pulsa «Abrir documento» para leerlo."
    if section == "Tareas":
        state = get_task_state(status)
        if state == "active":
            copy = f"Ejecuta la tarea en {relative_path}"
            hint = ("Pégalo en tu cliente de IA (Claude Code, Codex…) abierto en la carpeta workshop. "
                    "La tarea se detiene en cada aprobación.")
        elif state == "waiting":
            copy = f"Ejecuta la tarea en {relative_path}"
            hint = ("En espera: empieza solo cuando termine la tarea de la que depende. "
                    "Comprueba su estado antes de ejecutarla.")
        else:
            copy = ""
            hint = (f"No ejecutar: tarea {get_status_label(status).lower()}. "
                    "Se conserva como registro; ábrela solo para consultarla.")
    elif section == "Agentes":
        copy = f"Usa el agente {PLUGIN_PREFIX}{name} para "
        hint = "Pégalo en Claude Code y completa la frase con lo que necesitas."
    elif section == "Skills":
        copy = f"/{PLUGIN_PREFIX}{name}"
        hint = f"Escríbelo en Claude Code. En Codex CLI escribe ${name}."
    elif section == "Asistentes":
        copy = f"claude --agent {PLUGIN_PREFIX}{name}"
        hint = "Escríbelo en una terminal abierta en la carpeta workshop."
    elif section == "Aplicaciones":
        if command:
            copy = command
            hint = f"Escríbelo tú en una terminal dentro de applications\\{name}. Esta ventana no inicia aplicaciones."
        else:
            copy = f"Lee las instrucciones en {relative_path}"
    return copy, hint


def _modified(path: str) -> datetime | None:
    try:
        return datetime.fromtimestamp(os.stat(path).st_mtime).replace(microsecond=0)
    except (OSError, ValueError):
        return None


def new_resource(section: str, name: str, workshop_root: str, path: str = "", title: str = "",
                 description: str = "", status: str = "", area: str = "", command: str = "") -> Resource:
    relative = relative_workshop_path(path, workshop_root)
    title = title or name
    type_label = TYPE_LABELS[section]
    copy, hint = get_usage(section, name, relative, command, status)
    search = remove_diacritics(" ".join([name, title, description or "", area, status, type_label, relative]))
    return Resource(
        section=section, type_label=type_label, name=name, title=title, description=description or "",
        status=status, area=area, path=path, relative_path=relative, usage=copy, usage_hint=hint,
        modified=_modified(path) if path else None, search_text=search,
    )


# --- Directory listing (mirrors Get-ChildItem without -Force: hidden items are skipped) --------------------

def _visible_entries(folder: str) -> list[os.DirEntry[str]]:
    try:
        with os.scandir(folder) as it:
            entries = []
            for entry in it:
                try:
                    attributes = getattr(entry.stat(follow_symlinks=False), "st_file_attributes", 0)
                except OSError:
                    continue
                if attributes & _FILE_ATTRIBUTE_HIDDEN:
                    continue
                entries.append(entry)
    except OSError:
        return []
    return sorted(entries, key=lambda e: e.name.lower())


def _is_dir(entry: os.DirEntry[str]) -> bool:
    try:
        return entry.is_dir()
    except OSError:
        return False


def _is_file(entry: os.DirEntry[str]) -> bool:
    try:
        return entry.is_file()
    except OSError:
        return False


def list_files(folder: str, suffix: str = ".md", recurse: bool = False) -> list[str]:
    """Files in a folder (optionally recursive). Linked folders are not entered: they are never listed anyway."""
    result: list[str] = []
    entries = _visible_entries(folder)
    result.extend(e.path for e in entries if _is_file(e) and e.name.lower().endswith(suffix))
    if recurse:
        for entry in entries:
            if _is_dir(entry) and not _is_link(entry.path):
                result.extend(list_files(entry.path, suffix, recurse=True))
    return result


def list_dirs(folder: str) -> list[os.DirEntry[str]]:
    return [e for e in _visible_entries(folder) if _is_dir(e)]


# --- Catalogue sections -------------------------------------------------------------------------------------

@dataclass
class CatalogueRow:
    name: str
    link: str
    use: str
    status: str = ""
    area: str = ""


_TASK_ROW_RE = re.compile(r"^\|\s*\[([^\]]+)\]\(([^)]+)\)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|", re.M)
_AREA_ROW_RE = re.compile(r"^\|\s*([^|\[]+?)\s*\|\s*\[([^\]]+)\]\(([^)]+)\)\s*\|\s*([^|]+?)\s*\|", re.M)


def parse_catalogue_table(text: str, section: str) -> list[CatalogueRow]:
    """Agents and skills: | Area | [name](link) | use | ... ; tasks: | [name](link) | status | purpose | ..."""
    if section == "Tareas":
        return [CatalogueRow(name=m.group(1).strip(), link=m.group(2), status=to_plain_text(m.group(3)),
                             use=to_plain_text(m.group(4))) for m in _TASK_ROW_RE.finditer(text)]
    return [CatalogueRow(area=m.group(1).strip(), name=m.group(2).strip(), link=m.group(3),
                         use=to_plain_text(m.group(4))) for m in _AREA_ROW_RE.finditer(text)]


def _disk_catalogue_files(infra_root: str, section: str) -> list[str]:
    if section == "Tareas":
        folder = os.path.join(infra_root, "tasks")
        return [f for f in list_files(folder) if os.path.basename(f).lower() != "readme.md"]
    if section == "Agentes":
        folder = os.path.join(infra_root, "agents")
        return [f for f in list_files(folder, recurse=True)
                if "\\personal-assistants\\" not in f.lower() and os.path.basename(f).lower() != "readme.md"]
    if section == "Skills":
        folder = os.path.join(infra_root, "skills")
        candidates = (os.path.join(d.path, "SKILL.md") for d in list_dirs(folder))
        return [c for c in candidates if os.path.isfile(c)]
    return []


def _disk_name(path: str, section: str) -> str:
    if section == "Skills":
        return os.path.basename(os.path.dirname(path))
    return os.path.splitext(os.path.basename(path))[0]


CATALOGUE_FILES = {"Tareas": "tasks.md", "Agentes": "agents.md", "Skills": "skills.md"}


def get_catalogue_resources(infra_root: str, workshop_root: str, section: str, warnings: list[str]) -> list[Resource]:
    """Catalogue rows are the source of truth; files on disk are a fallback and a consistency check."""
    catalogue_name = CATALOGUE_FILES[section]
    catalogue_path = os.path.join(infra_root, "docs", "catalogues", catalogue_name)
    items: list[Resource] = []
    disk_files = [f for f in _disk_catalogue_files(infra_root, section) if is_allowed_path(f, workshop_root)]
    listed: set[str] = set()
    has_catalogue = os.path.isfile(catalogue_path)

    if has_catalogue:
        for row in parse_catalogue_table(read_text_file(catalogue_path), section):
            path = resolve_link(os.path.dirname(catalogue_path), row.link)
            if not path or not is_allowed_path(path, workshop_root):
                warnings.append(f"El catálogo {catalogue_name} cita '{row.name}' con un enlace no válido "
                                f"o fuera del Workshop; se omite.")
                continue
            listed.add(path.lower())
            if not os.path.isfile(path):
                warnings.append(f"El catálogo {catalogue_name} cita '{row.name}', pero su archivo no existe.")
                continue
            title = row.name
            if section == "Tareas":
                try:
                    title = get_title(read_text_file(path), row.name)
                except OSError:
                    title = row.name
                title = re.sub(r"^TASK PROMPT\s*[—:-]+\s*", "", title, flags=re.IGNORECASE)
            items.append(new_resource(section, row.name, workshop_root, path=path, title=title,
                                      description=row.use, status=row.status, area=row.area))
    else:
        warnings.append(f"No se encontró el catálogo {catalogue_name}; se muestran los archivos encontrados en disco.")

    for file in disk_files:
        if file.lower() in listed:
            continue
        name = _disk_name(file, section)
        description = ""
        status = ""
        try:
            body = read_text_file(file)
            description = get_field(body, "description") or get_document_summary(body)
            status_match = re.search(r"^Status:\s*(.+?)\s*$", body, re.M)
            if status_match:
                status = status_match.group(1).strip()
        except OSError:
            description = UNREADABLE
        if has_catalogue:
            warnings.append(f"'{name}' existe en disco pero no figura en el catálogo {catalogue_name}.")
        items.append(new_resource(section, name, workshop_root, path=file, description=description,
                                  status=status, area=NOT_CATALOGUED_AREA))
    return items


# --- Documents ----------------------------------------------------------------------------------------------

def get_document_area(relative_path: str) -> str:
    folder = os.path.dirname(relative_path)
    if not folder:
        return "Workshop"
    folder = folder.replace("\\", "/")
    match = re.match(r"applications/([^/]+)", folder, re.IGNORECASE)
    if match:
        return match.group(1)
    if re.match(r"infra/docs/projects", folder, re.IGNORECASE):
        return "infra/docs/projects"
    return folder


def get_document_resources(infra_root: str, workshop_root: str, context_text: str,
                           warnings: list[str]) -> list[Resource]:
    files: list[str] = []
    context_file = os.path.join(workshop_root, "WORKSHOP-CONTEXT.md")
    if os.path.isfile(context_file):
        files.append(context_file)
    for name in ("README.md", "SECURITY.md"):
        path = os.path.join(infra_root, name)
        if os.path.isfile(path):
            files.append(path)
    docs_folder = os.path.join(infra_root, "docs")
    if os.path.isdir(docs_folder):
        files.extend(list_files(docs_folder, recurse=True))
        if context_text:
            lowered = context_text.lower()
            for file in list_files(docs_folder):
                base = os.path.basename(file)
                if base.lower() not in lowered:
                    warnings.append(f"El documento infra/docs/{base} no figura en el mapa WORKSHOP-CONTEXT.md.")
    applications = os.path.join(workshop_root, "applications")
    for app in list_dirs(applications):
        app_docs = os.path.join(app.path, "docs")
        if os.path.isdir(app_docs):
            files.extend(list_files(app_docs))

    items: list[Resource] = []
    for path in files:
        if not is_allowed_path(path, workshop_root):
            continue
        relative = relative_workshop_path(path, workshop_root)
        name = os.path.splitext(os.path.basename(path))[0]
        title = name
        try:
            body = read_text_file(path)
            title = get_title(body, name)
            description = get_document_summary(body)
        except OSError:
            description = UNREADABLE
        items.append(new_resource("Documentos", name, workshop_root, path=path, title=title,
                                  description=description, area=get_document_area(relative)))
    return items


# --- Applications -------------------------------------------------------------------------------------------

_APP_TABLE_RE = re.compile(r"^\|\s*Application\s*\|.*?(?=^\s*$|\Z)", re.M | re.S)
_APP_ROW_RE = re.compile(r"^\|\s*([A-Za-z0-9._-]+)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|", re.M)
_APP_TREE_RE = re.compile(r"^[│ ]*[├└]──\s+([A-Za-z0-9._-]+)/\s{2,}(.+?)\s*$", re.M)


def get_application_resources(workshop_root: str, context_text: str, warnings: list[str]) -> list[Resource]:
    """Applications come from the table in WORKSHOP-CONTEXT.md section 2; folders missing from it are still shown."""
    items: list[Resource] = []
    applications = os.path.join(workshop_root, "applications")
    rows: dict[str, dict[str, str]] = {}
    summaries: dict[str, str] = {}
    if context_text:
        table = _APP_TABLE_RE.search(context_text)
        if table:
            for m in _APP_ROW_RE.finditer(table.group(0)):
                name = m.group(1)
                if name.lower() == "application":
                    continue
                rows[name.lower()] = {"stack": to_plain_text(m.group(2)), "run": to_plain_text(m.group(3)),
                                      "rules": to_plain_text(m.group(4))}
        for m in _APP_TREE_RE.finditer(context_text):
            summaries[m.group(1).lower()] = m.group(2).strip()
    if not os.path.isdir(applications):
        return items

    for folder in list_dirs(applications):
        if not is_allowed_path(folder.path, workshop_root):
            continue
        key = folder.name.lower()
        path = folder.path
        for candidate in ("README.md", "AGENTS.md", "CLAUDE.md"):
            file = os.path.join(folder.path, candidate)
            if os.path.isfile(file):
                path = file
                break
        row = rows.get(key)
        description = summaries.get(key, "")
        if not description and path != folder.path:
            try:
                description = get_document_summary(read_text_file(path))
            except OSError:
                description = ""
        stack = ""
        command = ""
        if row:
            stack = row["stack"]
            command = row["run"]
            description = f"{description}\r\n\r\nTecnología: {stack}" if description else f"Tecnología: {stack}"
        elif context_text:
            warnings.append(f"La aplicación '{folder.name}' no figura en la tabla de aplicaciones de "
                            f"WORKSHOP-CONTEXT.md.")
        items.append(new_resource("Aplicaciones", folder.name, workshop_root, path=path, description=description,
                                  area=stack, command=command))
    return items


# --- Client guides and personal assistants ------------------------------------------------------------------

def get_simple_folder_resources(infra_root: str, workshop_root: str, section: str) -> list[Resource]:
    files: list[str] = []
    if section == "Clientes IA":
        folder = os.path.join(infra_root, "clients")
        candidates = (os.path.join(d.path, "README.md") for d in list_dirs(folder) if not d.name.startswith("."))
        files = [c for c in candidates if os.path.isfile(c)]
    else:
        folder = os.path.join(infra_root, "agents", "personal-assistants")
        files = [f for f in list_files(folder) if os.path.basename(f).lower() != "readme.md"]

    items: list[Resource] = []
    for file in files:
        if not is_allowed_path(file, workshop_root):
            continue
        if section == "Clientes IA":
            name = os.path.basename(os.path.dirname(file))
        else:
            name = os.path.splitext(os.path.basename(file))[0]
        title = name
        try:
            body = read_text_file(file)
            if section == "Clientes IA":
                title = get_title(body, name)
                description = get_document_summary(body)
            else:
                description = get_field(body, "description") or get_document_summary(body)
        except OSError:
            description = UNREADABLE
        items.append(new_resource(section, name, workshop_root, path=file, title=title, description=description))
    return items


# --- Entry points -------------------------------------------------------------------------------------------

def is_active_task(resource: Resource) -> bool:
    return resource.section == "Tareas" and get_task_state(resource.status) in ("active", "waiting")


def get_workshop_data(infra_root: str) -> WorkshopData:
    """Loads every resource type. Returns items, warnings and the folders used."""
    infra = os.path.abspath(infra_root).rstrip("\\")
    workshop_root = os.path.dirname(infra)
    data = WorkshopData(infra_root=infra, workshop_root=workshop_root)
    context_text = ""
    context_file = os.path.join(workshop_root, "WORKSHOP-CONTEXT.md")
    if os.path.isfile(context_file):
        context_text = read_text_file(context_file)
    else:
        data.warnings.append("No se encontró WORKSHOP-CONTEXT.md junto a la carpeta infra; "
                             "las aplicaciones se leen solo del disco.")

    for section in ("Tareas", "Agentes", "Skills"):
        data.items.extend(get_catalogue_resources(infra, workshop_root, section, data.warnings))
    data.items.extend(get_document_resources(infra, workshop_root, context_text, data.warnings))
    data.items.extend(get_application_resources(workshop_root, context_text, data.warnings))
    for section in ("Clientes IA", "Asistentes"):
        data.items.extend(get_simple_folder_resources(infra, workshop_root, section))
    return data


def word_matches(text: str, word: str) -> bool:
    """Words of three letters or fewer must match a whole word ("ui" must not match "build")."""
    if len(word) <= 3:
        return re.search(r"(?<![^\W_])" + re.escape(word) + r"(?![^\W_])", text) is not None
    return word in text


def query_words(query: str) -> list[str]:
    return [w for w in re.split(r"\s+", remove_diacritics(query)) if w]


def resource_matches(resource: Resource | dict[str, Any] | str, query: str) -> bool:
    """Every query word (or one of its English equivalents) must appear in the item's search text."""
    if isinstance(resource, str):
        text = resource
    elif isinstance(resource, dict):
        text = resource.get("searchText", "")
    else:
        text = resource.search_text
    for word in query_words(query):
        alternatives = [word, *SEARCH_SYNONYMS.get(word, [])]
        if not any(word_matches(text, alternative) for alternative in alternatives):
            return False
    return True


def get_related_resources(resource: Resource, all_items: Iterable[Resource]) -> list[Resource]:
    """For a task: the agents, skills and personal assistants its brief mentions by name."""
    if resource.section != "Tareas" or not os.path.isfile(resource.path):
        return []
    try:
        body = read_text_file(resource.path)
    except OSError:
        return []
    related: list[Resource] = []
    for candidate in all_items:
        if candidate.section not in ("Agentes", "Skills", "Asistentes"):
            continue
        if re.search(r"(?<![\w-])" + re.escape(candidate.name) + r"(?![\w-])", body, re.IGNORECASE):
            related.append(candidate)
    return related


# --- JSON shape for the web API -----------------------------------------------------------------------------

def section_key(section: str) -> str:
    return remove_diacritics(section).replace(" ", "")


def can_open_document(resource: Resource, workshop_root: str) -> bool:
    path = resource.path
    return (bool(path) and os.path.splitext(path)[1] == ".md" and is_inside_root(path, workshop_root)
            and os.path.isfile(path))


def resource_folder(resource: Resource, workshop_root: str) -> str:
    """The item's folder (itself when it is a folder), or '' when it is not inside the workspace."""
    if not resource.path:
        return ""
    folder = resource.path if os.path.isdir(resource.path) else os.path.dirname(resource.path)
    return folder if is_inside_root(folder, workshop_root) else ""


def can_open_folder(resource: Resource, workshop_root: str) -> bool:
    folder = resource_folder(resource, workshop_root)
    return bool(folder) and os.path.isdir(folder)


def assign_ids(items: list[Resource]) -> list[str]:
    """Stable, unique ids: '<section key>:<name>' (documents use their relative path)."""
    ids: list[str] = []
    seen: dict[str, int] = {}
    for item in items:
        suffix = item.relative_path.replace("\\", "/") if item.section == "Documentos" else item.name
        base = f"{section_key(item.section)}:{suffix}"
        count = seen.get(base.lower(), 0) + 1
        seen[base.lower()] = count
        ids.append(base if count == 1 else f"{base}~{count}")
    return ids


def resource_to_json(resource: Resource, item_id: str, workshop_root: str, related: list[str]) -> dict[str, Any]:
    is_task = resource.section == "Tareas"
    state = get_task_state(resource.status) if is_task else ""
    return {
        "id": item_id,
        "section": resource.section,
        "typeLabel": resource.type_label,
        "name": resource.name,
        "title": resource.title,
        "description": resource.description,
        "area": resource.area,
        "status": resource.status if is_task else "",
        "statusLabel": get_status_label(resource.status) if is_task else "",
        "statusShort": SHORT_STATUS.get(state, ""),
        "taskState": state,
        "relativePath": resource.relative_path,
        "usage": resource.usage,
        "usageHint": resource.usage_hint,
        "modified": resource.modified.isoformat() if resource.modified else "",
        "related": related,
        "canOpenDocument": can_open_document(resource, workshop_root),
        "canOpenFolder": can_open_folder(resource, workshop_root),
        "searchText": resource.search_text,
    }


@dataclass
class Snapshot:
    """A loaded data set: the JSON payload plus a server-side id -> resource map (paths never leave the server)."""
    payload: dict[str, Any]
    by_id: dict[str, Resource]
    workshop_root: str


def build_snapshot(infra_root: str) -> Snapshot:
    started = time.perf_counter()
    data = get_workshop_data(infra_root)
    ids = assign_ids(data.items)
    json_items: list[dict[str, Any]] = []
    for item_id, item in zip(ids, data.items):
        related: list[str] = []
        if item.section == "Tareas":
            for candidate in get_related_resources(item, data.items):
                if candidate.name not in related:
                    related.append(candidate.name)
        json_items.append(resource_to_json(item, item_id, data.workshop_root, related))
    payload = {
        "workshopRoot": data.workshop_root,
        "loadedMs": int((time.perf_counter() - started) * 1000),
        "sections": list(SECTIONS),
        "typeLabels": dict(TYPE_LABELS),
        "items": json_items,
        "warnings": list(data.warnings),
        "searchSynonyms": {k: list(v) for k, v in SEARCH_SYNONYMS.items()},
    }
    return Snapshot(payload=payload, by_id=dict(zip(ids, data.items)), workshop_root=data.workshop_root)
