import { memo, useId } from 'react';
import { formatDate, statusTone, themeKey } from '../constants.js';

function Pill({ tone, children }) {
  return <span className={`pill pill--${tone}`}>{children}</span>;
}

function RowDetail({ item, variant, showArea }) {
  if (item.statusShort) return <Pill tone={statusTone(item)}>{item.statusShort}</Pill>;
  if (variant === 'date') {
    const date = formatDate(item.modified);
    return date ? <span className="row-detail">{date}</span> : null;
  }
  if (showArea && item.area) return <span className="row-detail">{item.area}</span>;
  return null;
}

/**
 * Grouped listbox. Options use a roving tabindex; selection follows focus.
 * Keyboard: Up/Down/Home/End move, Enter opens the document, Up on the first row returns to search.
 */
function ResourceList(props) {
  const empty = props.groups.length === 0;
  // The status region stays mounted so screen readers announce the empty message when it appears.
  return (
    <div className="list-wrap">
      <div role="status" aria-live="polite" className={empty ? 'list list--empty' : undefined}>
        {empty ? <p className="empty-message">{props.emptyMessage}</p> : null}
      </div>
      {empty ? null : <Listbox {...props} />}
    </div>
  );
}

function Listbox({ groups, selectedKey, showType, label, listRef, onSelect, onActivate, onOpen, onExitTop,
  collapsedGroups = {}, onToggleGroup }) {
  const baseId = useId();
  const visibleEntries = groups.filter((group) => !collapsedGroups[group.key]).flatMap((group) => group.entries);
  const hasSelection = visibleEntries.some((entry) => entry.key === selectedKey);
  const tabKey = hasSelection ? selectedKey : visibleEntries[0]?.key;

  function handleKeyDown(event) {
    if (event.altKey || event.ctrlKey || event.metaKey) return;
    const options = [...event.currentTarget.querySelectorAll('[role="option"]')];
    const index = options.indexOf(document.activeElement);
    if (index === -1) return;
    let target = null;
    switch (event.key) {
      case 'ArrowDown':
        target = options[Math.min(index + 1, options.length - 1)];
        break;
      case 'ArrowUp':
        if (index === 0) {
          event.preventDefault();
          onExitTop();
          return;
        }
        target = options[index - 1];
        break;
      case 'Home':
        target = options[0];
        break;
      case 'End':
        target = options[options.length - 1];
        break;
      case 'Enter':
        event.preventDefault();
        onActivate(options[index].dataset.key);
        return;
      default:
        return;
    }
    event.preventDefault();
    target?.focus();
  }

  function renderOption(entry, variant) {
    const { item } = entry;
    const selected = entry.key === selectedKey;
    return (
      <div
        key={entry.key}
        role="option"
        data-key={entry.key}
        aria-selected={selected}
        tabIndex={entry.key === tabKey ? 0 : -1}
        className={`row${item.isWarning ? ' row--warning' : ''}`}
        onFocus={() => onSelect(entry.key)}
        onClick={() => onActivate(entry.key)}
        onDoubleClick={() => onOpen(entry.key)}
      >
        <span className="row-main">
          <span className="row-title">{item.title || item.name}</span>
          {item.description && !item.isWarning ? <span className="row-desc">{item.description}</span> : null}
        </span>
        <span className="row-meta">
          {showType ? <Pill tone={themeKey(item.section)}>{item.typeLabel || item.section}</Pill> : null}
          <RowDetail item={item} variant={variant} showArea={!showType && variant !== 'date'} />
        </span>
      </div>
    );
  }

  return (
    <div className="list" aria-label={label} ref={listRef} onKeyDown={handleKeyDown}>
      {groups.map((group, groupIndex) => {
        const headerId = `${baseId}-g${groupIndex}`;
        const contentId = `${headerId}-content`;
        const collapsed = Boolean(collapsedGroups[group.key]);
        return (
          <div key={group.key} className="group">
            <button type="button" id={headerId} className={`group-header theme-${group.theme}`}
              aria-expanded={!collapsed} aria-controls={contentId} onClick={() => onToggleGroup?.(group.key)}>
              <span className="group-dot" aria-hidden="true" />
              <span aria-hidden="true">{collapsed ? '▸' : '▾'}</span>
              {group.label || label} <span className="group-count">({group.entries.length})</span>
            </button>
            <div id={contentId} role="listbox" aria-labelledby={headerId} hidden={collapsed}>
              {collapsed ? null : group.entries.map((entry) => renderOption(entry, group.variant))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default memo(ResourceList);
