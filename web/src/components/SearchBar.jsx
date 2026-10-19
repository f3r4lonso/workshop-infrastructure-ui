import { CloseIcon, RefreshIcon, SearchIcon } from './Icons.jsx';

/** Top bar: the big search field plus the "Actualizar" button. */
export default function SearchBar({ value, onChange, onClear, onKeyDown, inputRef, onRefresh, refreshing, disabled }) {
  return (
    <div className="topbar">
      <form className="search" role="search" onSubmit={(event) => event.preventDefault()}>
        <label htmlFor="search-input" className="sr-only">
          Buscar en todo el Workshop
        </label>
        <SearchIcon className="icon search-icon" size={20} />
        <input
          id="search-input"
          ref={inputRef}
          type="search"
          className="search-input"
          placeholder="Buscar en todo… (Ctrl+F)"
          autoComplete="off"
          spellCheck="false"
          aria-describedby="search-help"
          value={value}
          disabled={disabled}
          onChange={(event) => onChange(event.target.value)}
          onKeyDown={onKeyDown}
        />
        <span id="search-help" className="sr-only">
          Escribe una o varias palabras. Flecha abajo para ir a los resultados, Escape para borrar.
        </span>
        {value ? (
          <button type="button" className="search-clear" onClick={onClear} aria-label="Borrar la búsqueda">
            <CloseIcon size={18} />
          </button>
        ) : null}
      </form>
      <button type="button" className="button" onClick={onRefresh} disabled={refreshing || disabled} aria-busy={refreshing}>
        <RefreshIcon className={refreshing ? 'icon icon--spin' : 'icon'} />
        <span>{refreshing ? 'Actualizando…' : 'Actualizar'}</span>
      </button>
    </div>
  );
}
