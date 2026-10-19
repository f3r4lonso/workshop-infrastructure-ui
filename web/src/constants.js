// Shared labels, section metadata and task-state helpers (Spanish UI text).

export const HOME = 'Inicio';

export const SECTION_INTROS = {
  Inicio: 'Todo lo que hay en el Workshop. Elige una sección o escribe en el buscador.',
  Tareas: 'Encargos completos que se entregan a un cliente de IA. Ejecuta solo las activas.',
  Agentes: 'Roles especializados (revisor, diseñador, auditor…) que un cliente de IA puede usar.',
  Skills: 'Métodos y listas de comprobación que un cliente de IA sigue durante la sesión.',
  Documentos: 'Guías, políticas, investigaciones y planes del Workshop y de cada aplicación.',
  Aplicaciones: 'Las aplicaciones del Workshop. Esta página no las inicia: muestra cómo hacerlo.',
  'Clientes IA': 'Cómo encuentra y usa cada cliente de IA los recursos compartidos.',
  Asistentes: 'Tus asistentes personales: planificador, ingeniero de prompts y redactor.',
};

const THEME_KEYS = {
  Tareas: 'tareas',
  Agentes: 'agentes',
  Skills: 'skills',
  Documentos: 'documentos',
  Aplicaciones: 'aplicaciones',
  'Clientes IA': 'clientes',
  Asistentes: 'asistentes',
  Aviso: 'aviso',
};

/** CSS theme suffix for a section (colour accent per resource type). */
export function themeKey(section) {
  return THEME_KEYS[section] ?? 'otros';
}

/** Sections whose list is grouped by area. */
export const GROUPED_SECTIONS = new Set(['Agentes', 'Skills', 'Documentos']);

export const TASK_FILTERS = [
  { value: 'active', label: 'Activas' },
  { value: 'all', label: 'Todas' },
  { value: 'completed', label: 'Completadas' },
  { value: 'retired', label: 'Retiradas o sustituidas' },
];

export function isActiveTask(item) {
  return item.section === 'Tareas' && (item.taskState === 'active' || item.taskState === 'waiting');
}

export function passesTaskFilter(item, filter) {
  switch (filter) {
    case 'active':
      return isActiveTask(item);
    case 'completed':
      return item.taskState === 'completed';
    case 'retired':
      return item.taskState === 'retired' || item.taskState === 'superseded';
    default:
      return true;
  }
}

/** Pill colour for a task status. */
export function statusTone(item) {
  if (item.taskState === 'active') return 'active';
  if (item.taskState === 'waiting') return 'waiting';
  return 'other';
}

export const MESSAGES = {
  unreachable: 'No se puede conectar con el servidor local. Cierra esta pestaña y vuelve a abrir INICIAR.cmd.',
  unexpected: 'El servidor local respondió algo inesperado. Pulsa «Actualizar» o vuelve a abrir INICIAR.cmd.',
  emptyDetail: 'Selecciona algo de la lista para ver qué es y cómo usarlo.',
  launchNote: 'Se abre en una ventana nueva en la carpeta workshop',
};

const dateFormatter = new Intl.DateTimeFormat('es-ES', { day: 'numeric', month: 'short', year: 'numeric' });

export function formatDate(iso) {
  if (!iso) return '';
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? '' : dateFormatter.format(date);
}
