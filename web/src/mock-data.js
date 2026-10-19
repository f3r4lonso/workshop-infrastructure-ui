// DEV ONLY. Loaded by api.js through a dynamic import guarded by import.meta.env.DEV, so it never
// reaches the production bundle. Shapes follow docs/web-architecture.md §2.
import { normalizeText } from './search.js';

const SECTIONS = ['Tareas', 'Agentes', 'Skills', 'Documentos', 'Aplicaciones', 'Clientes IA', 'Asistentes'];
const TYPE_LABELS = {
  Tareas: 'Tarea',
  Agentes: 'Agente',
  Skills: 'Skill',
  Documentos: 'Documento',
  Aplicaciones: 'Aplicación',
  'Clientes IA': 'Cliente IA',
  Asistentes: 'Asistente',
};

const TASK_LABELS = {
  active: 'Activa',
  waiting: 'En espera',
  completed: 'Completada',
  retired: 'Retirada',
  superseded: 'Sustituida',
};

function item(section, name, description, extra = {}) {
  const typeLabel = TYPE_LABELS[section];
  const base = {
    id: `${normalizeText(section).replace(/\s+/g, '')}:${name}`,
    section,
    typeLabel,
    name,
    title: extra.title ?? name,
    description,
    area: '',
    status: '',
    statusLabel: '',
    statusShort: '',
    taskState: '',
    relativePath: `infra\\${normalizeText(section)}\\${name}.md`,
    usage: '',
    usageHint: '',
    modified: '2026-09-01T10:00:00',
    related: [],
    canOpenDocument: true,
    canOpenFolder: true,
    ...extra,
  };
  if (base.taskState && TASK_LABELS[base.taskState]) {
    base.statusShort = TASK_LABELS[base.taskState];
    base.statusLabel = `${base.statusShort} (rev. 1, 2026-10-18)`;
  }
  base.searchText = normalizeText(
    [base.name, base.title, base.description, base.area, base.statusLabel, typeLabel, base.relativePath].join(' '),
  );
  return base;
}

function task(name, title, description, taskState, extra = {}) {
  return item('Tareas', name, description, {
    title,
    taskState,
    status: taskState,
    relativePath: `infra\\tasks\\${name}.md`,
    usage: `Ejecuta la tarea en infra\\tasks\\${name}.md`,
    usageHint: 'Pégalo en tu cliente de IA (Claude Code, Codex…) abierto en la carpeta workshop. La tarea se detiene en cada aprobación.',
    ...extra,
  });
}

const ITEMS = [
  task('ai-spanish-reading-assistant', 'Build an AI Spanish Reading Assistant Web App', 'Build a local-first web app that prepares text locally, optionally translates it into Spanish, and reads it aloud at adjustable speeds', 'active', { modified: '2026-10-18T21:10:00', related: ['code-reviewer', 'engineering-lifecycle'] }),
  task('ollama-local-model-runtime', 'Incorporate the Ollama CLI as a Local Model Runtime', 'Install the Ollama CLI and approved local models, verify they run on the GPU and stay on localhost', 'active', { related: ['security-reviewer', 'dependency-license-review'] }),
  task('workshop-ai-shared-knowledge', 'Workshop AI: Shared Knowledge and Context Optimisation', 'Stage 2 proof of concept: project-local knowledge store', 'waiting'),
  task('workshop-infrastructure-web-ui', 'Workshop Infrastructure Web UI', 'Build a browser interface for the shared AI infrastructure', 'active', { modified: '2026-10-19T09:30:00' }),
  task('trading-journal', 'Trading Journal Export', 'Export trades to a CSV journal for review', 'completed'),
  task('old-dashboard', 'Old Dashboard Prototype', 'First dashboard attempt, replaced by the trading app', 'superseded'),
  item('Agentes', 'security-reviewer', 'Security review of any project or change: secrets, injection, auth', { area: 'Quality', usage: 'Usa el agente security-reviewer para ', usageHint: 'Pégalo en Claude Code y completa la frase con lo que necesitas.', relativePath: 'infra\\agents\\quality\\security-reviewer.md', modified: '2026-10-19T03:19:00' }),
  item('Agentes', 'code-reviewer', 'Review code for bugs, security, performance and readability', { area: 'Quality', usage: 'Usa el agente code-reviewer para ', usageHint: 'Pégalo en Claude Code y completa la frase con lo que necesitas.' }),
  item('Agentes', 'ui-designer', 'Design accessible user interfaces and design systems (WCAG)', { area: 'Design', usage: 'Usa el agente ui-designer para ' }),
  item('Agentes', 'market-data-analyst', 'Analyse market data, candles and price action for strategies', { area: 'Trading', usage: 'Usa el agente market-data-analyst para ' }),
  item('Skills', 'engineering-lifecycle', 'Plan, build, test and release changes step by step', { area: 'Engineering', usage: '/engineering-lifecycle', usageHint: 'En Claude Code escribe /engineering-lifecycle; en Codex, $engineering-lifecycle.' }),
  item('Skills', 'dependency-license-review', 'Check new dependencies for licence and supply-chain risk', { area: 'Quality', usage: '/dependency-license-review' }),
  item('Skills', 'vercel-react-best-practices', 'React and Next.js performance optimisation guidelines', { area: 'Engineering', usage: '/vercel-react-best-practices', modified: '2026-10-17T12:00:00' }),
  item('Documentos', 'security-policy', 'This repository is a public, reusable AI infrastructure: no secrets', { title: 'Security policy', area: 'infra/docs', relativePath: 'infra\\docs\\security.md' }),
  item('Documentos', 'contributor-guide', 'How to add, change or retire shared resources', { title: 'Contributor guide', area: 'infra/docs' }),
  item('Documentos', 'web-architecture', 'Web version — architecture and API contract', { title: 'Web architecture', area: 'workshop-infrastructure-ui', modified: '2026-10-19T08:00:00' }),
  item('Aplicaciones', 'Trading-app', 'Personal trading dashboard: React + FastAPI', { usage: 'cd applications\\Trading-app; npm run dev', usageHint: 'Cópialo y pídele a tu cliente de IA que lo ejecute.', canOpenDocument: true }),
  item('Aplicaciones', 'workshop-infrastructure-ui', 'This page: everything in the Workshop', { usage: 'INICIAR.cmd' }),
  item('Clientes IA', 'claude-code', 'How Claude Code finds the shared agents and skills', { title: 'Claude Code', relativePath: 'infra\\clients\\claude-code\\README.md' }),
  item('Clientes IA', 'codex', 'How Codex CLI uses AGENTS.md and the shared skills', { title: 'Codex CLI', relativePath: 'infra\\clients\\codex\\README.md' }),
  item('Asistentes', 'planner', 'Turns an idea into a plan with steps and risks', { title: 'Planificador', usage: 'Usa el asistente planner para ' }),
  item('Asistentes', 'writer', 'Writes and edits texts in Spanish or English', { title: 'Redactor', usage: 'Usa el asistente writer para ', canOpenFolder: false }),
];

const DATA = {
  workshopRoot: 'C:\\Users\\demo\\workshop',
  loadedMs: 12,
  sections: SECTIONS,
  typeLabels: TYPE_LABELS,
  items: ITEMS,
  warnings: ['2 documentos no figuran en el mapa del workshop (WORKSHOP-CONTEXT.md).'],
  searchSynonyms: {
    seguridad: ['security', 'secret'],
    revisor: ['review'],
    interfaz: ['interface', 'ui'],
    pantalla: ['ui', 'screen'],
    precio: ['price', 'market', 'candle'],
    tarea: ['task'],
    agente: ['agent'],
  },
};

const CLIENTS = [
  { id: 'claude', name: 'Claude Code', installed: true, command: 'claude' },
  { id: 'codex', name: 'Codex CLI', installed: true, command: 'codex' },
  { id: 'gemini', name: 'Gemini CLI', installed: false, command: 'gemini' },
  { id: 'copilot', name: 'GitHub Copilot CLI', installed: true, command: 'copilot' },
];

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export async function getData() {
  await delay(300);
  return structuredClone(DATA);
}

export async function getClients() {
  await delay(150);
  return structuredClone(CLIENTS);
}

export async function open(id, target) {
  await delay(100);
  const found = ITEMS.find((entry) => entry.id === id);
  if (!found) return { ok: false, message: 'No se encontró ese elemento.' };
  return { ok: true, message: `(simulado) Abriendo ${target === 'folder' ? 'la carpeta de' : ''} ${found.title}…` };
}

export async function launch(clientId) {
  await delay(200);
  const client = CLIENTS.find((entry) => entry.id === clientId);
  if (!client?.installed) return { ok: false, message: 'Ese cliente no está instalado.' };
  return { ok: true, message: `(simulado) Abriendo ${client.name} en una ventana nueva…` };
}
