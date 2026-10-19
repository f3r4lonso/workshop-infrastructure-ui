import { useCallback, useEffect, useEffectEvent, useMemo, useRef, useState } from 'react';
import { flushSync } from 'react-dom';
import { getClients, getData, launchClient, openItem, refreshData } from './api.js';
import { HOME, MESSAGES, TASK_FILTERS, isActiveTask } from './constants.js';
import { filterItems } from './search.js';
import { buildView, warningItems } from './view.js';
import Sidebar from './components/Sidebar.jsx';
import SearchBar from './components/SearchBar.jsx';
import HomeTiles from './components/HomeTiles.jsx';
import ResourceList from './components/ResourceList.jsx';
import DetailPanel from './components/DetailPanel.jsx';
import { AlertIcon } from './components/Icons.jsx';

const SEARCH_DEBOUNCE_MS = 150;
const TOAST_MS = 6000;
const LAUNCH_DONE_MS = 4000;
const STACKED_QUERY = '(max-width: 69.99rem)';
const EMPTY_SECTIONS = [];
const RELATED_SECTIONS = new Set(['Agentes', 'Skills', 'Asistentes']);

function isEditable(target) {
  return target instanceof HTMLElement && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName));
}

const listSkeleton = (
  <div className="list list--skeleton" aria-hidden="true">
    {Array.from({ length: 7 }, (_, index) => (
      <div key={index} className="row row--skeleton">
        <span className="skeleton skeleton--title" />
        <span className="skeleton skeleton--text" />
      </div>
    ))}
  </div>
);

export default function App() {
  const [data, setData] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [clients, setClients] = useState(null);
  const [clientsError, setClientsError] = useState('');
  const [section, setSection] = useState(HOME);
  const [query, setQuery] = useState('');
  const [activeQuery, setActiveQuery] = useState('');
  const [taskFilter, setTaskFilter] = useState('active');
  const [selectedKey, setSelectedKey] = useState(null);
  const [refreshing, setRefreshing] = useState(false);
  const [launchState, setLaunchState] = useState({});
  const [clientsAttempt, setClientsAttempt] = useState(0);
  const [toast, setToast] = useState(null);
  const [attempt, setAttempt] = useState(0);
  const searchRef = useRef(null);
  const listRef = useRef(null);
  const detailRef = useRef(null);
  const launchTimers = useRef(new Map());

  const notify = useCallback((message, tone = 'info') => {
    setToast({ message, tone, id: Date.now() });
  }, []);

  // Initial load: data and clients in parallel.
  useEffect(() => {
    let cancelled = false;
    getData().then(
      (json) => !cancelled && setData(json),
      (error) => !cancelled && setLoadError(error),
    );
    return () => {
      cancelled = true;
    };
  }, [attempt]);

  useEffect(() => {
    let cancelled = false;
    getClients().then(
      (list) => !cancelled && setClients(list),
      (error) =>
        !cancelled &&
        setClientsError(
          error.unreachable ? 'Sin conexión con el servidor local.' : 'No se pudo comprobar qué clientes están instalados.',
        ),
    );
    return () => {
      cancelled = true;
    };
  }, [attempt, clientsAttempt]);

  useEffect(() => {
    const timers = launchTimers.current;
    return () => timers.forEach((timer) => clearTimeout(timer));
  }, []);

  useEffect(() => {
    if (!toast) return undefined;
    const timer = setTimeout(() => setToast(null), TOAST_MS);
    return () => clearTimeout(timer);
  }, [toast]);

  // Debounce the search; clearing is applied immediately by the handlers.
  const trimmedQuery = query.trim();
  useEffect(() => {
    if (trimmedQuery === activeQuery) return undefined;
    const timer = setTimeout(() => setActiveQuery(trimmedQuery), SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [trimmedQuery, activeQuery]);

  const items = data?.items;
  const sections = data?.sections ?? EMPTY_SECTIONS;
  const warnings = useMemo(() => warningItems(data?.warnings), [data]);

  const counts = useMemo(() => {
    const map = new Map();
    for (const item of items ?? []) map.set(item.section, (map.get(item.section) ?? 0) + 1);
    return map;
  }, [items]);
  const activeTasks = useMemo(() => (items ?? []).filter(isActiveTask).length, [items]);

  const relatedLookup = useMemo(() => {
    const map = new Map();
    for (const item of items ?? []) {
      if (RELATED_SECTIONS.has(item.section) && !map.has(item.name)) map.set(item.name, item);
    }
    return map;
  }, [items]);

  const results = useMemo(
    () => (data && activeQuery ? filterItems(data.items, activeQuery, data.searchSynonyms) : null),
    [data, activeQuery],
  );

  const view = useMemo(
    () => (data ? buildView({ data, warnings, section, query: activeQuery, results, taskFilter }) : null),
    [data, warnings, section, activeQuery, results, taskFilter],
  );

  const selectedItem = view?.keys.get(selectedKey) ?? null;

  const focusSearch = useCallback((select = false) => {
    const input = searchRef.current;
    if (!input) return;
    input.focus();
    if (select) input.select();
  }, []);

  const clearSearch = useCallback(() => {
    setQuery('');
    setActiveQuery('');
    focusSearch();
  }, [focusSearch]);

  const handleQueryChange = useCallback((value) => {
    setQuery(value);
    if (!value.trim()) setActiveQuery('');
  }, []);

  const navigate = useCallback((name) => {
    setSection(name);
    setQuery('');
    setActiveQuery('');
    setSelectedKey(null);
  }, []);

  const searchFor = useCallback(
    (text) => {
      setQuery(text);
      setActiveQuery(text);
      setSelectedKey(null);
      focusSearch();
    },
    [focusSearch],
  );

  function focusFirstResult() {
    // Apply a pending (debounced) query first so the list reflects what was typed.
    if (trimmedQuery !== activeQuery) flushSync(() => setActiveQuery(trimmedQuery));
    const first = listRef.current?.querySelector('[role="option"]');
    first?.focus();
  }

  function handleSearchKeyDown(event) {
    if (event.key === 'ArrowDown' || event.key === 'Enter') {
      event.preventDefault();
      focusFirstResult();
    } else if (event.key === 'Escape') {
      event.preventDefault();
      if (query) clearSearch();
    }
  }

  // Global shortcuts: Ctrl+F or "/" focus search, Esc clears it. F5 is left to the browser.
  const onGlobalKeyDown = useEffectEvent((event) => {
    if ((event.ctrlKey || event.metaKey) && !event.altKey && event.key.toLowerCase() === 'f') {
      event.preventDefault();
      focusSearch(true);
    } else if (event.key === '/' && !event.ctrlKey && !event.metaKey && !event.altKey && !isEditable(event.target)) {
      event.preventDefault();
      focusSearch(true);
    } else if (event.key === 'Escape' && query && event.target !== searchRef.current) {
      event.preventDefault();
      clearSearch();
    }
  });
  useEffect(() => {
    const listener = (event) => onGlobalKeyDown(event);
    window.addEventListener('keydown', listener);
    return () => window.removeEventListener('keydown', listener);
  }, []);

  const handleOpen = useCallback(
    async (item, target) => {
      try {
        const result = await openItem(item.id, target);
        notify(result.message || (result.ok ? 'Abriendo…' : 'No se pudo abrir.'), result.ok ? 'info' : 'error');
      } catch (error) {
        notify(error.message, 'error');
      }
    },
    [notify],
  );

  const handleOpenKey = useCallback(
    (key) => {
      const item = view?.keys.get(key);
      if (!item) return;
      if (item.canOpenDocument) handleOpen(item, 'document');
      else if (!item.isWarning) notify('Este elemento no tiene un documento que abrir.', 'info');
    },
    [view, handleOpen, notify],
  );

  const handleCopy = useCallback(
    async (text) => {
      try {
        await navigator.clipboard.writeText(text);
        notify('Copiado. Pégalo en tu cliente de IA.', 'info');
        return true;
      } catch {
        notify('No se pudo copiar. Selecciona el texto del recuadro y pulsa Ctrl+C.', 'error');
        return false;
      }
    },
    [notify],
  );

  const setClientState = useCallback((id, state) => {
    clearTimeout(launchTimers.current.get(id));
    setLaunchState((previous) => ({ ...previous, [id]: state }));
    if (state?.phase === 'done') {
      launchTimers.current.set(
        id,
        setTimeout(() => setLaunchState((previous) => ({ ...previous, [id]: null })), LAUNCH_DONE_MS),
      );
    }
  }, []);

  const launchingRef = useRef(false);
  const handleLaunch = useCallback(
    async (client) => {
      if (!client.installed) {
        notify(`${client.name} no está instalado en este equipo.`, 'error');
        return;
      }
      if (launchingRef.current) {
        notify('Ya se está abriendo; espera un momento.', 'info');
        return;
      }
      launchingRef.current = true;
      setClientState(client.id, { phase: 'busy' });
      try {
        const result = await launchClient(client.id);
        const message = result.message || (result.ok ? `Abriendo ${client.name}…` : 'No se pudo abrir.');
        setClientState(client.id, result.ok ? { phase: 'done' } : { phase: 'error', message });
        notify(message, result.ok ? 'info' : 'error');
      } catch (error) {
        setClientState(client.id, { phase: 'error', message: error.message });
        notify(error.message, 'error');
      } finally {
        launchingRef.current = false;
      }
    },
    [notify, setClientState],
  );

  const retryClients = useCallback(() => {
    setClientsError('');
    setClients(null);
    setClientsAttempt((value) => value + 1);
  }, []);

  // Stacked layout only: bring the detail panel (below the list) into view after a click or Enter.
  const activateKey = useCallback((key) => {
    setSelectedKey(key);
    if (!window.matchMedia(STACKED_QUERY).matches) return;
    requestAnimationFrame(() => {
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      detailRef.current?.scrollIntoView({ block: 'start', behavior: reduce ? 'auto' : 'smooth' });
    });
  }, []);

  const backToList = useCallback(() => {
    const options = listRef.current?.querySelectorAll('[role="option"]') ?? [];
    const row = [...options].find((option) => option.dataset.key === selectedKey) ?? options[0];
    row?.focus();
  }, [selectedKey]);

  async function handleRefresh() {
    setRefreshing(true);
    try {
      const json = await refreshData();
      setData(json);
      notify('Datos actualizados.', 'info');
    } catch (error) {
      notify(error.message, 'error');
    } finally {
      setRefreshing(false);
    }
  }

  function retryLoad() {
    setLoadError(null);
    setClientsError('');
    setClients(null);
    setAttempt((value) => value + 1);
  }

  const loading = !data && !loadError;
  const showTiles = data && !activeQuery && section === HOME;
  const showTaskFilter = data && !activeQuery && section === 'Tareas';

  let content;
  if (loadError) {
    content = (
      <div className="load-error" role="alert">
        <AlertIcon size={28} />
        <p>{loadError.unreachable ? MESSAGES.unreachable : loadError.message}</p>
        <button type="button" className="button" onClick={retryLoad}>
          Reintentar
        </button>
      </div>
    );
  } else if (loading) {
    content = (
      <div aria-busy="true">
        <h1 className="page-title">Cargando…</h1>
        <div className="tiles tiles--skeleton" aria-hidden="true">
          {Array.from({ length: 7 }, (_, index) => (
            <span key={index} className="tile tile--skeleton" />
          ))}
        </div>
        <div className="workspace">{listSkeleton}</div>
      </div>
    );
  } else {
    content = (
      <>
        <div className="page-head">
          <div>
            <h1 className="page-title">{view.title}</h1>
            <p className="page-intro">{view.intro}</p>
          </div>
          {showTaskFilter ? (
            <div className="filter">
              <label htmlFor="task-filter">Estado</label>
              <select id="task-filter" value={taskFilter} onChange={(event) => setTaskFilter(event.target.value)}>
                {TASK_FILTERS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </div>
          ) : null}
        </div>

        {showTiles ? (
          <HomeTiles sections={sections} counts={counts} activeTasks={activeTasks} onNavigate={navigate} />
        ) : null}

        <div className="workspace">
          <ResourceList
            groups={view.groups}
            selectedKey={selectedKey}
            showType={view.showType}
            label={view.title}
            emptyMessage={view.emptyMessage}
            listRef={listRef}
            onSelect={setSelectedKey}
            onActivate={activateKey}
            onOpen={handleOpenKey}
            onExitTop={focusSearch}
          />
          <DetailPanel
            key={selectedItem ? selectedKey : 'none'}
            item={selectedItem}
            relatedLookup={relatedLookup}
            panelRef={detailRef}
            onBackToList={backToList}
            onOpen={handleOpen}
            onCopy={handleCopy}
            onSearch={searchFor}
          />
        </div>
      </>
    );
  }

  return (
    <div className="app">
      <a className="skip-link" href="#main">
        Saltar al contenido
      </a>
      <Sidebar
        sections={sections}
        counts={counts}
        current={activeQuery ? null : section}
        onNavigate={navigate}
        workshopRoot={data?.workshopRoot}
        loading={loading}
        clients={clients}
        clientsError={clientsError}
        launchState={launchState}
        onLaunch={handleLaunch}
        onRetryClients={retryClients}
      />
      <main id="main" className="main" tabIndex={-1}>
        <SearchBar
          value={query}
          onChange={handleQueryChange}
          onClear={clearSearch}
          onKeyDown={handleSearchKeyDown}
          inputRef={searchRef}
          onRefresh={handleRefresh}
          refreshing={refreshing}
          disabled={!data}
        />
        {content}
        <footer className="statusbar">
          {/* Persistent live region for result counts; when the list is empty its own status
              region announces the empty message instead, so the count is shown but not announced. */}
          <span role="status" aria-live="polite">
            {view ? (view.groups.length ? view.countText : '') : loading ? 'Cargando recursos…' : ''}
          </span>
          {view && !view.groups.length ? <span>{view.countText}</span> : null}
        </footer>
      </main>
      <div className="toast-region" role="status" aria-live="polite" aria-atomic="true">
        {toast ? (
          <div key={toast.id} className={`toast toast--${toast.tone}`}>
            {toast.message}
          </div>
        ) : null}
      </div>
    </div>
  );
}
