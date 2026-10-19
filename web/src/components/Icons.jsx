// Inline SVG icons (decorative: always aria-hidden; the surrounding control carries the label).

function Svg({ children, size = 18, className = 'icon' }) {
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

export function SearchIcon(props) {
  return (
    <Svg {...props}>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.5-3.5" />
    </Svg>
  );
}

export function RefreshIcon(props) {
  return (
    <Svg {...props}>
      <path d="M20 11a8 8 0 1 0-2.3 5.7" />
      <path d="M20 4v7h-7" />
    </Svg>
  );
}

export function CloseIcon(props) {
  return (
    <Svg {...props}>
      <path d="M6 6l12 12M18 6 6 18" />
    </Svg>
  );
}

export function FolderIcon(props) {
  return (
    <Svg {...props}>
      <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z" />
    </Svg>
  );
}

export function DocumentIcon(props) {
  return (
    <Svg {...props}>
      <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8Z" />
      <path d="M14 3v5h5M9 13h6M9 17h6" />
    </Svg>
  );
}

export function CopyIcon(props) {
  return (
    <Svg {...props}>
      <rect x="9" y="9" width="11" height="11" rx="2" />
      <path d="M5 15V5a2 2 0 0 1 2-2h8" />
    </Svg>
  );
}

export function CheckIcon(props) {
  return (
    <Svg {...props}>
      <path d="m5 12 5 5L20 7" />
    </Svg>
  );
}

export function AlertIcon(props) {
  return (
    <Svg {...props}>
      <path d="M12 3 2 20h20Z" />
      <path d="M12 10v4M12 17h.01" />
    </Svg>
  );
}

/** One simple mark per AI client; unknown ids fall back to their initial. */
export function ClientIcon({ id, name }) {
  switch (id) {
    case 'claude':
      return (
        <span className="client-icon client-icon--claude" aria-hidden="true">
          <Svg size={16}>
            <path d="M12 3v18M3 12h18M5.6 5.6l12.8 12.8M18.4 5.6 5.6 18.4" />
          </Svg>
        </span>
      );
    case 'codex':
      return (
        <span className="client-icon client-icon--codex" aria-hidden="true">
          <Svg size={16}>
            <path d="m5 7 5 5-5 5M12 18h7" />
          </Svg>
        </span>
      );
    case 'gemini':
      return (
        <span className="client-icon client-icon--gemini" aria-hidden="true">
          <Svg size={16}>
            <path d="M12 2c.8 5.5 4.5 9.2 10 10-5.5.8-9.2 4.5-10 10-.8-5.5-4.5-9.2-10-10 5.5-.8 9.2-4.5 10-10Z" />
          </Svg>
        </span>
      );
    case 'copilot':
      return (
        <span className="client-icon client-icon--copilot" aria-hidden="true">
          <Svg size={16}>
            <rect x="3" y="7" width="18" height="12" rx="5" />
            <path d="M9 12v2M15 12v2M8 7V5M16 7V5" />
          </Svg>
        </span>
      );
    default:
      return (
        <span className="client-icon" aria-hidden="true">
          {(name || id || '?').charAt(0).toUpperCase()}
        </span>
      );
  }
}
