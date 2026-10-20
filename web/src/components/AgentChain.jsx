import { useEffect, useRef, useState } from 'react';
import { interaction } from '../api.js';

const LIMIT = 5;
const TERMINAL = new Set(['completed', 'failed', 'uncertain', 'cancelled']);
const STATUS = {
  queued: 'En cola', running: 'En curso', stopping: 'Deteniendo después de la etapa actual',
  pending: 'Pendiente', completed: 'Completado', failed: 'Falló', uncertain: 'Resultado incierto',
  cancelled: 'No ejecutado',
};

export default function AgentChain({ resources = [] }) {
  const [registry, setRegistry] = useState(null);
  const [registryError, setRegistryError] = useState('');
  const [goal, setGoal] = useState('');
  const [model, setModel] = useState('');
  const [steps, setSteps] = useState([
    { key: 'step-1', agent: '', direction: '' },
    { key: 'step-2', agent: '', direction: '' },
  ]);
  const [run, setRun] = useState(null);
  const [busy, setBusy] = useState(false);
  const [restoring, setRestoring] = useState(true);
  const [notice, setNotice] = useState('');
  const counter = useRef(3);
  const active = run && ['queued', 'running', 'stopping'].includes(run.status);
  const locked = Boolean(run);
  const client = registry?.clients?.find((entry) => entry.id === 'claude');
  const agents = (registry?.agents ?? []).map((agent) => ({
    ...agent,
    resource: resources.find((resource) => resource.id === agent.id),
  }));

  useEffect(() => {
    let cancelled = false;
    interaction('registry', {}).then((result) => {
      if (cancelled) return;
      if (!result.ok) throw new Error(result.message || 'No se pudieron cargar los agentes.');
      setRegistry(result);
    }).catch((error) => {
      if (!cancelled) setRegistryError(error.message || 'No se pudieron cargar los agentes.');
    });
    interaction('chain-current', {}).then((result) => {
      if (!cancelled && result.ok && result.run) {
        setRun(result.run);
        setGoal(result.run.goal || '');
        setModel(result.run.model || '');
        setSteps(result.run.steps.map((step, index) => ({
          key: `restored-step-${index + 1}`, agent: step.agent, direction: step.direction || '',
        })));
        counter.current = result.run.steps.length + 1;
      }
    }).catch((error) => {
      if (!cancelled) setNotice(error.message || 'No se pudo recuperar la cadena anterior.');
    }).finally(() => {
      if (!cancelled) setRestoring(false);
    });
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    if (!run?.runId || TERMINAL.has(run.status)) return undefined;
    let cancelled = false;
    let timer;
    const poll = async () => {
      try {
        const result = await interaction('chain-status', { runId: run.runId, knownAt: run.updatedAt });
        if (cancelled) return;
        if (!result.ok) setNotice(result.message || 'No se pudo actualizar el estado de la cadena.');
        else setRun((previous) => result.unchanged && previous
          ? { ...previous, ...result, steps: previous.steps }
          : result);
      } catch (error) {
        if (!cancelled) setNotice(error.message || 'Se perdió la conexión con el servidor local; se comprobará de nuevo.');
      }
      if (!cancelled) timer = setTimeout(poll, 900);
    };
    timer = setTimeout(poll, 350);
    return () => { cancelled = true; clearTimeout(timer); };
  }, [run?.runId, run?.status, run?.updatedAt]);

  function updateStep(key, values) {
    setSteps((previous) => previous.map((step) => step.key === key ? { ...step, ...values } : step));
  }

  function moveStep(index, offset) {
    setSteps((previous) => {
      const next = [...previous];
      const target = index + offset;
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  }

  async function start() {
    setBusy(true);
    setNotice('');
    try {
      const result = await interaction('chain-start', {
        goal,
        model,
        steps: steps.map(({ agent, direction }) => ({ agent, direction })),
      });
      if (!result.ok) throw new Error(result.message || 'No se pudo iniciar la cadena.');
      setRun(result);
    } catch (error) {
      setNotice(error.message || 'No se pudo iniciar la cadena.');
    } finally {
      setBusy(false);
    }
  }

  async function stop() {
    if (!run?.runId) return;
    setBusy(true);
    try {
      const result = await interaction('chain-stop', { runId: run.runId });
      if (!result.ok) throw new Error(result.message || 'No se pudo detener la cadena.');
      setRun(result);
    } catch (error) {
      setNotice(error.message || 'No se pudo detener la cadena.');
    } finally {
      setBusy(false);
    }
  }

  async function clearResults() {
    setBusy(true);
    try {
      const result = await interaction('chain-clear', {});
      if (!result.ok) throw new Error(result.message || 'No se pudieron borrar los resultados.');
      setRun(null);
      setNotice(result.message);
    } catch (error) {
      setNotice(error.message || 'No se pudieron borrar los resultados.');
    } finally {
      setBusy(false);
    }
  }

  const usedAgents = new Set(steps.map((step) => step.agent).filter(Boolean));
  const canStart = !busy && !restoring && !locked && Boolean(goal.trim()) && Boolean(model) && Boolean(client?.available)
    && steps.length >= 2 && steps.every((step) => step.agent);

  return (
    <section className="chain-workspace" aria-labelledby="chain-title">
      <header className="chain-heading">
        <p className="reader-eyebrow">ORQUESTACIÓN SECUENCIAL</p>
        <h3 id="chain-title">Cadena de agentes</h3>
        <p>Ordena perfiles del Workshop. Cada agente recibe tu objetivo y la salida del agente anterior.</p>
      </header>

      <div className="chain-setup">
        <label className="interaction-field">Objetivo de la cadena
          <textarea rows={4} value={goal} maxLength={32000} disabled={locked || restoring}
            onChange={(event) => setGoal(event.target.value)} placeholder="Describe el resultado que quieres obtener…" />
        </label>

        <label className="interaction-field">Modelo de Claude
          <select value={model} disabled={locked || restoring || !client?.available} onChange={(event) => setModel(event.target.value)}>
            <option value="">Selecciona un modelo</option>
            {client?.models?.map((option) => <option key={option.id} value={option.id}>{option.label || option.id}</option>)}
          </select>
        </label>
        {registryError ? <p className="chain-error" role="alert">{registryError}</p> : null}
        {client ? <p className={client.available ? 'chain-availability' : 'chain-error'} role="status">
          {client.available ? `Transporte de Claude ${client.version ? `v${client.version}` : ''} disponible; el acceso de cuenta no está comprobado.` : client.reason}
        </p> : registryError ? null : <p role="status">Comprobando el transporte local…</p>}
      </div>

      <div className="chain-steps-heading">
        <div><h4>Orden de ejecución</h4><p>De 2 a 5 agentes distintos. El último resultado queda disponible para revisarlo.</p></div>
        <button type="button" className="button" disabled={locked || restoring || steps.length >= LIMIT || agents.length < steps.length + 1}
          onClick={() => setSteps((previous) => [...previous, { key: `step-${counter.current++}`, agent: '', direction: '' }])}>Añadir agente</button>
      </div>

      <ol className="chain-steps">
        {steps.map((step, index) => {
          const result = run?.steps?.[index];
          const selectedAgent = agents.find((agent) => agent.id === step.agent);
          return <li className={`chain-step${result ? ` chain-step--${result.status}` : ''}`} key={step.key}>
            <div className="chain-step-top">
              <span className="reader-step" aria-label={`Etapa ${index + 1}`}>{index + 1}</span>
              <label className="interaction-field">Agente
                <select value={step.agent} disabled={locked || restoring} onChange={(event) => updateStep(step.key, { agent: event.target.value })}>
                  <option value="">Selecciona un agente</option>
                  {agents.map((agent) => <option key={agent.id} value={agent.id}
                    disabled={usedAgents.has(agent.id) && step.agent !== agent.id}>{agent.name}{agent.resource?.area ? ` · ${agent.resource.area}` : ''}</option>)}
                </select>
              </label>
              <div className="chain-order-controls" aria-label={`Cambiar orden de la etapa ${index + 1}`}>
                <button type="button" className="chain-icon-button" aria-label="Subir etapa" title="Subir"
                  disabled={locked || restoring || index === 0} onClick={() => moveStep(index, -1)}>↑</button>
                <button type="button" className="chain-icon-button" aria-label="Bajar etapa" title="Bajar"
                  disabled={locked || restoring || index === steps.length - 1} onClick={() => moveStep(index, 1)}>↓</button>
                <button type="button" className="chain-icon-button chain-icon-button--remove" aria-label="Quitar agente" title="Quitar"
                  disabled={locked || restoring || steps.length <= 2} onClick={() => setSteps((previous) => previous.filter((candidate) => candidate.key !== step.key))}>×</button>
              </div>
            </div>
            {selectedAgent?.resource?.description ? <p className="chain-agent-description">{selectedAgent.resource.description}</p> : null}
            <label className="interaction-field">Instrucción para este agente (opcional)
              <textarea rows={2} maxLength={8000} value={step.direction} disabled={locked || restoring}
                onChange={(event) => updateStep(step.key, { direction: event.target.value })}
                placeholder={index === 0 ? 'Enfoque o criterio para el primer agente…' : 'Qué debe hacer este agente con el objetivo y la salida anterior…'} />
            </label>
            {result ? <div className="chain-result">
              <div className="chain-result-heading"><strong>{result.name}</strong><span className={`chain-status chain-status--${result.status}`}>{STATUS[result.status] || result.status}</span></div>
              {result.message ? <p>{result.message}</p> : null}
              {result.output ? <pre className="chain-output">{result.output}</pre> : null}
            </div> : null}
          </li>;
        })}
      </ol>

      <p className="chain-disclosure">Cada etapa crea una petición nueva de Claude y puede consumir tu cuota. El objetivo, las instrucciones, los perfiles elegidos y la salida anterior se envían al servicio de Claude al iniciar cada etapa. No se ejecutan herramientas ni se guarda el historial en disco.</p>
      <div className="chain-actions">
        {active ? <button type="button" className="button chain-stop" disabled={busy || run.status === 'stopping'} onClick={stop}>Detener después de esta etapa</button>
          : run ? <button type="button" className="button" disabled={busy} onClick={clearResults}>Borrar resultados</button>
            : null}
        {!run ? <button type="button" className="button button--primary" disabled={!canStart}
          onClick={start}>{busy ? 'Iniciando…' : `Iniciar cadena · ${steps.length} peticiones`}</button> : null}
      </div>
      <p className="chain-notice" role="status" aria-live="polite">{restoring ? 'Recuperando el estado de la última cadena…' : notice || (run ? `${STATUS[run.status] || run.status} · ${run.completed} de ${run.total} agentes completados. ${run.message}` : '')}</p>
    </section>
  );
}
