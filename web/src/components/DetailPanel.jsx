import { useEffect, useState } from 'react';
import { MESSAGES, themeKey } from '../constants.js';
import { CheckIcon, CopyIcon, DocumentIcon, FolderIcon } from './Icons.jsx';

function metaLine(item) {
  const parts = [item.typeLabel || item.section];
  if (item.statusLabel) parts.push(item.statusLabel);
  else if (item.statusShort) parts.push(item.statusShort);
  if (item.area) parts.push(item.area);
  return parts.filter(Boolean).join(' · ');
}

function Related({ names, relatedLookup, onSearch }) {
  if (!names?.length) {
    return <p className="detail-text detail-muted">Esta tarea no menciona agentes ni skills por su nombre.</p>;
  }
  return (
    <ul className="related">
      {names.map((name) => {
        const match = relatedLookup.get(name);
        const type = match ? (match.typeLabel || match.section).toLowerCase() : '';
        return (
          <li key={name}>
            <button
              type="button"
              className={`related-chip theme-${match ? themeKey(match.section) : 'otros'}`}
              onClick={() => onSearch(name)}
              title={`Buscar ${name}`}
            >
              <span className="sr-only">Buscar </span>
              {name}
              {type ? <span className="related-type"> ({type})</span> : null}
            </button>
          </li>
        );
      })}
    </ul>
  );
}

/** Detail of the selected item: what it is for, how to use it (copyable) and open actions. */
export default function DetailPanel({ item, relatedLookup, panelRef, onBackToList, onOpen, onCopy, onSearch }) {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) return undefined;
    const timer = setTimeout(() => setCopied(false), 2000);
    return () => clearTimeout(timer);
  }, [copied]);

  if (!item) {
    return (
      <aside ref={panelRef} className="detail detail--empty" aria-label="Detalle">
        <p>{MESSAGES.emptyDetail}</p>
      </aside>
    );
  }

  const theme = themeKey(item.section);
  const hasUsage = Boolean(item.usage);

  async function handleCopy() {
    if (!hasUsage) return;
    if (await onCopy(item.usage)) setCopied(true);
  }

  return (
    <aside ref={panelRef} className={`detail theme-${theme}`} aria-labelledby="detail-title">
      <div className="detail-band" aria-hidden="true" />
      {/* Only visible in the stacked layout, where the panel sits below the list. */}
      <button type="button" className="back-link" onClick={onBackToList}>
        <span aria-hidden="true">↑ </span>Volver a la lista
      </button>
      <h2 id="detail-title" className="detail-title">
        {item.title || item.name}
      </h2>
      <p className="detail-meta">{metaLine(item)}</p>
      {item.relativePath ? <p className="detail-path">{item.relativePath}</p> : null}

      <h3 className="detail-heading">Para qué sirve</h3>
      <p className="detail-text">{item.description || 'Sin descripción.'}</p>

      {item.isWarning ? null : (
        <>
          <h3 className="detail-heading">Cómo usarlo</h3>
          <div className="usage">
            {hasUsage ? (
              <pre className="usage-code" tabIndex={0} role="group" aria-label="Texto para copiar">
                <code>{item.usage}</code>
              </pre>
            ) : (
              <p className="usage-none">No hay nada que copiar para este elemento.</p>
            )}
            <button type="button" className="button" onClick={handleCopy} disabled={!hasUsage}>
              {copied ? <CheckIcon /> : <CopyIcon />}
              <span>{copied ? 'Copiado' : 'Copiar'}</span>
            </button>
          </div>
          {item.usageHint ? <p className="detail-hint">{item.usageHint}</p> : null}
        </>
      )}

      {item.section === 'Tareas' ? (
        <>
          <h3 className="detail-heading">Relacionado</h3>
          <Related names={item.related} relatedLookup={relatedLookup} onSearch={onSearch} />
        </>
      ) : null}

      {item.canOpenFolder || item.canOpenDocument ? (
        <div className="detail-actions">
          <button
            type="button"
            className="button"
            disabled={!item.canOpenFolder}
            onClick={() => onOpen(item, 'folder')}
          >
            <FolderIcon />
            <span>Abrir carpeta</span>
          </button>
          <button
            type="button"
            className="button button--primary"
            disabled={!item.canOpenDocument}
            onClick={() => onOpen(item, 'document')}
          >
            <DocumentIcon />
            <span>Abrir documento</span>
          </button>
        </div>
      ) : null}
    </aside>
  );
}
