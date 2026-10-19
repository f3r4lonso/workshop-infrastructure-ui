import { memo } from 'react';
import { HOME } from '../constants.js';
import ClientLaunchers from './ClientLaunchers.jsx';

/** Navy sidebar: brand, section navigation with counts, workspace folder and AI-client launchers. */
function Sidebar({ sections, counts, current, onNavigate, workshopRoot, loading, clients, clientsError, launchState, onLaunch, onRetryClients }) {
  const entries = [HOME, ...sections];
  return (
    <div className="sidebar">
      <div className="brand">
        <span className="brand-mark" aria-hidden="true">
          W
        </span>
        <span className="brand-text">
          <span className="brand-name">Workshop</span>
          <span className="brand-tagline">Todo lo que tengo</span>
        </span>
      </div>

      <nav className="nav" aria-label="Secciones">
        <ul>
          {entries.map((name) => {
            const isCurrent = name === current;
            const count = counts.get(name);
            return (
              <li key={name}>
                <button
                  type="button"
                  className="nav-item"
                  aria-current={isCurrent ? 'page' : undefined}
                  onClick={() => onNavigate(name)}
                >
                  <span className="nav-label">{name}</span>
                  {name === HOME ? null : loading ? (
                    <span className="nav-count nav-count--loading" aria-hidden="true" />
                  ) : (
                    <span className="nav-count">
                      {count ?? 0}
                      <span className="sr-only"> elementos</span>
                    </span>
                  )}
                </button>
              </li>
            );
          })}
        </ul>
      </nav>

      <ClientLaunchers
        clients={clients}
        error={clientsError}
        launchState={launchState}
        onLaunch={onLaunch}
        onRetry={onRetryClients}
      />

      {workshopRoot ? (
        <div className="root-folder">
          <span className="root-folder-label">Carpeta workshop</span>
          <span className="root-folder-path">{workshopRoot}</span>
        </div>
      ) : null}
    </div>
  );
}

export default memo(Sidebar);
