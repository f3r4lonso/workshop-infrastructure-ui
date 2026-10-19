import { memo } from 'react';
import { themeKey } from '../constants.js';

/** Inicio: one tile per type with its count; clicking a tile opens that section. */
function HomeTiles({ sections, counts, activeTasks, onNavigate }) {
  return (
    <ul className="tiles" aria-label="Resumen por tipo">
      {sections.map((section) => {
        const isTasks = section === 'Tareas';
        return (
          <li key={section}>
            <button
              type="button"
              className={`tile theme-${themeKey(section)}`}
              onClick={() => onNavigate(section)}
            >
              <span className="tile-number">
                {isTasks ? activeTasks : counts.get(section) ?? 0}
                {isTasks ? <span className="tile-of"> de {counts.get(section) ?? 0}</span> : null}
              </span>
              <span className="tile-label">{isTasks ? 'Tareas activas' : section}</span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

export default memo(HomeTiles);
