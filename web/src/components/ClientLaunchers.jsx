import { memo } from 'react';
import { MESSAGES } from '../constants.js';
import { useMediaQuery } from '../hooks.js';
import { ClientIcon } from './Icons.jsx';

const NARROW_QUERY = '(max-width: 48rem)';
const TITLE = 'Abrir un cliente de IA';

function stateText(client, state) {
  if (!client.installed) return 'No instalado';
  if (state?.phase === 'busy') return 'Abriendo…';
  if (state?.phase === 'done') return 'Abierto ✓';
  return '';
}

function Body({ clients, error, launchState, onLaunch, onRetry }) {
  if (error) {
    return (
      <div className="clients-error">
        <p>{error}</p>
        <button type="button" className="clients-retry" onClick={onRetry}>
          Reintentar
        </button>
      </div>
    );
  }
  if (clients === null) {
    return (
      <ul className="clients-list" aria-hidden="true">
        {[0, 1, 2, 3].map((index) => (
          <li key={index}>
            <span className="client-button client-button--skeleton" />
          </li>
        ))}
      </ul>
    );
  }
  return (
    <ul className="clients-list">
      {clients.map((client) => {
        const state = launchState[client.id];
        const busy = state?.phase === 'busy';
        const text = stateText(client, state);
        const errorId = `client-error-${client.id}`;
        const hasError = state?.phase === 'error';
        return (
          <li key={client.id}>
            <button
              type="button"
              className="client-button"
              aria-disabled={!client.installed || busy ? 'true' : undefined}
              aria-busy={busy ? 'true' : undefined}
              aria-describedby={hasError ? errorId : undefined}
              onClick={() => onLaunch(client)}
            >
              <ClientIcon id={client.id} name={client.name} />
              <span className="client-text">
                <span className="sr-only">Abrir </span>
                <span className="client-name">{client.name}</span>
                {text ? <span className={`client-state${state?.phase === 'done' ? ' client-state--ok' : ''}`}>{text}</span> : null}
              </span>
            </button>
            {hasError ? (
              <p id={errorId} className="client-error-text">
                {state.message}
              </p>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

/**
 * One button per AI client from GET /api/clients. On wide screens it is an always-visible block;
 * on narrow screens it collapses into a closed <details> so the search stays above the fold.
 * The block title is a label, not a heading, so the page <h1> stays the first heading.
 */
function ClientLaunchers(props) {
  const narrow = useMediaQuery(NARROW_QUERY);
  const count = props.clients?.length ?? 4;

  if (narrow) {
    return (
      <details className="clients clients--collapsible">
        <summary className="clients-summary">
          {TITLE} ({count})
        </summary>
        <p className="clients-note">{MESSAGES.launchNote}</p>
        <Body {...props} />
      </details>
    );
  }
  return (
    <section className="clients" aria-labelledby="clients-title">
      <p id="clients-title" className="clients-title">
        {TITLE}
      </p>
      <p className="clients-note">{MESSAGES.launchNote}</p>
      <Body {...props} />
    </section>
  );
}

export default memo(ClientLaunchers);
