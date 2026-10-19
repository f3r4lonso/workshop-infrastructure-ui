// Builds what the main area shows (title, intro, grouped rows, counts) from data + UI state. Pure.
import {
  GROUPED_SECTIONS,
  HOME,
  SECTION_INTROS,
  isActiveTask,
  passesTaskFilter,
  themeKey,
} from './constants.js';

const collator = new Intl.Collator('es', { sensitivity: 'base', numeric: true });
const titleOf = (item) => item.title || item.name || '';
const byTitle = (a, b) => collator.compare(titleOf(a), titleOf(b));
const byModifiedDesc = (a, b) => (b.modified || '').localeCompare(a.modified || '');

/** Loader warnings become selectable pseudo-items so they can be read in the detail panel. */
export function warningItems(warnings) {
  return (warnings ?? []).map((text, index) => ({
    id: `aviso:${index}`,
    section: 'Aviso',
    typeLabel: 'Aviso',
    name: '',
    title: text,
    description:
      'Algo no cuadra entre los catálogos, los archivos o el mapa del workshop. Pide a tu cliente de IA que lo revise.',
    area: '',
    statusShort: '',
    taskState: '',
    relativePath: '',
    usage: '',
    usageHint: '',
    related: [],
    canOpenDocument: false,
    canOpenFolder: false,
    isWarning: true,
  }));
}

function makeGroup(key, label, theme, items, variant = '') {
  return {
    key,
    label,
    theme,
    variant,
    entries: items.map((item) => ({ key: `${key}|${item.id}`, item })),
  };
}

function plural(count, one, many) {
  return `${count} ${count === 1 ? one : many}`;
}

/**
 * @returns {{title: string, intro: string, groups: Array, keys: Map<string, object>,
 *            showType: boolean, countText: string, emptyMessage: string}}
 */
export function buildView({ data, warnings, section, query, results, taskFilter }) {
  const items = data.items;
  const total = items.length;
  const groups = [];
  let title;
  let intro;
  let countText;
  let emptyMessage = 'No hay nada en esta sección.';
  let showType = true;

  if (results) {
    const bySection = new Map();
    for (const item of results) {
      const list = bySection.get(item.section);
      if (list) list.push(item);
      else bySection.set(item.section, [item]);
    }
    const order = [...(data.sections ?? []), ...bySection.keys()];
    const seen = new Set();
    for (const name of order) {
      if (seen.has(name) || !bySection.has(name)) continue;
      seen.add(name);
      groups.push(makeGroup(`search:${name}`, name, themeKey(name), bySection.get(name).toSorted(byTitle)));
    }
    title = 'Resultados de búsqueda';
    intro = `Buscando «${query}» en todas las secciones. Pulsa Esc para limpiar la búsqueda.`;
    countText = `${plural(results.length, 'resultado', 'resultados')} de ${total} recursos`;
    emptyMessage = `No hay resultados para «${query}». Prueba otra palabra o pulsa Esc.`;
  } else if (section === HOME) {
    const active = items.filter(isActiveTask).toSorted(byTitle);
    if (active.length) groups.push(makeGroup('home:active', 'Tareas activas', 'tareas', active));
    const recent = items.filter((item) => item.modified).toSorted(byModifiedDesc).slice(0, 5);
    if (recent.length) groups.push(makeGroup('home:recent', 'Modificado recientemente', 'otros', recent, 'date'));
    if (warnings.length) groups.push(makeGroup('home:warnings', 'Avisos', 'aviso', warnings));
    title = HOME;
    intro = SECTION_INTROS[HOME];
    countText = `${total} recursos cargados · ${plural(warnings.length, 'aviso', 'avisos')}`;
  } else {
    let list = items.filter((item) => item.section === section);
    showType = false;
    if (section === 'Tareas') {
      list = list
        .filter((item) => passesTaskFilter(item, taskFilter))
        .toSorted((a, b) => Number(isActiveTask(b)) - Number(isActiveTask(a)) || byTitle(a, b));
      groups.push(makeGroup(`section:${section}`, '', themeKey(section), list));
      emptyMessage = 'No hay tareas con este estado. Elige otro en «Estado».';
    } else if (GROUPED_SECTIONS.has(section)) {
      const byArea = new Map();
      for (const item of list) {
        const area = item.area || 'Otros';
        const bucket = byArea.get(area);
        if (bucket) bucket.push(item);
        else byArea.set(area, [item]);
      }
      const areas = [...byArea.keys()].toSorted(collator.compare);
      for (const area of areas) {
        groups.push(makeGroup(`area:${section}:${area}`, area, themeKey(section), byArea.get(area).toSorted(byTitle)));
      }
    } else {
      groups.push(makeGroup(`section:${section}`, '', themeKey(section), list.toSorted(byTitle)));
    }
    title = section;
    intro = SECTION_INTROS[section] ?? '';
    countText = `${plural(list.length, 'elemento', 'elementos')} en ${section} · ${total} recursos en total`;
  }

  const visibleGroups = groups.filter((group) => group.entries.length > 0);
  const keys = new Map();
  for (const group of visibleGroups) {
    for (const entry of group.entries) keys.set(entry.key, entry.item);
  }
  return { title, intro, groups: visibleGroups, keys, showType, countText, emptyMessage };
}
