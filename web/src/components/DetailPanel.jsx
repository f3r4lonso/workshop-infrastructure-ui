import { useState } from 'react';
import AgentChain from './AgentChain.jsx';
import ResourceInteraction from './ResourceInteraction.jsx';

/** The selected-resource panel is now the reading assistant workspace. */
export default function DetailPanel({ item, resources = [], panelRef, onBackToList }) {
  const [activeTab, setActiveTab] = useState('reader');
  return (
    <aside ref={panelRef} className="detail reader-detail" aria-label="Herramientas del Workshop">
      {item ? <button type="button" className="back-link" onClick={onBackToList}>
        <span aria-hidden="true">↑ </span>Volver a los recursos
      </button> : null}
      <div className="assistant-tabs" role="group" aria-label="Herramientas del Workshop">
        <button type="button" id="reader-tab" aria-pressed={activeTab === 'reader'} aria-controls="reader-panel"
          className="assistant-tab" onClick={() => setActiveTab('reader')}>Lector</button>
        <button type="button" id="chain-tab" aria-pressed={activeTab === 'chain'} aria-controls="chain-panel"
          className="assistant-tab" onClick={() => setActiveTab('chain')}>Cadena de agentes</button>
      </div>
      <div id="reader-panel" role="region" aria-labelledby="reader-tab" hidden={activeTab !== 'reader'}>
        <ResourceInteraction key={item?.id || 'no-selection'} item={item} />
      </div>
      <div id="chain-panel" role="region" aria-labelledby="chain-tab" hidden={activeTab !== 'chain'}>
        {activeTab === 'chain' ? <AgentChain resources={resources} /> : null}
      </div>
    </aside>
  );
}
