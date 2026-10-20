import { useEffect, useRef, useState } from 'react';
import { interaction } from '../api.js';

export default function ResourceInteraction({ item }) {
  const [reader, setReader] = useState(null);
  const [translated, setTranslated] = useState('');
  const [readerPath, setReaderPath] = useState('');
  const [pastedText, setPastedText] = useState('');
  const [readerStatus, setReaderStatus] = useState(null);
  const [speed, setSpeed] = useState(1.2);
  const [speech, setSpeech] = useState('idle');
  const [busy, setBusy] = useState('');
  const [notice, setNotice] = useState('');
  const alive = useRef(true);
  const speechGeneration = useRef(0);
  const autoLoadedId = useRef(null);

  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
      speechGeneration.current++;
      window.speechSynthesis?.cancel();
    };
  }, []);

  async function run(label, action) {
    setBusy(label);
    setNotice('');
    try {
      await action();
    } catch (error) {
      if (alive.current) setNotice(error.message || 'No se pudo completar la operación.');
    } finally {
      if (alive.current) setBusy('');
    }
  }

  async function call(action, body) {
    const result = await interaction(action, body);
    if (!result.ok) throw new Error(result.message || result.reason || 'Operación rechazada.');
    return result;
  }

  async function load() {
    const path = readerPath.trim();
    if (!path && !item?.id) throw new Error('Escribe una ruta relativa o elige un recurso del Workshop.');
    const result = await call('read', path ? { path } : { id: item.id });
    if (alive.current) {
      setReader(result);
      setTranslated('');
      setSpeech('idle');
      speechGeneration.current++;
      window.speechSynthesis?.cancel();
      setNotice('Texto preparado y limpio para leer.');
    }
  }

  useEffect(() => {
    const previewable = item?.canOpenDocument && /\.(txt|md|markdown|docx)$/i.test(item.relativePath || '');
    if (previewable && autoLoadedId.current !== item.id) {
      autoLoadedId.current = item.id;
      run('Cargando vista previa del documento', load);
    }
  }, [item?.id]);

  async function preparePastedText() {
    const result = await call('prepare-text', { text: pastedText });
    if (alive.current) {
      setReader(result);
      setTranslated('');
      setSpeech('idle');
      speechGeneration.current++;
      window.speechSynthesis?.cancel();
      setNotice('Texto preparado y limpio para leer.');
    }
  }

  async function uploadFile(file) {
    if (!file) return;
    const supported = /\.(txt|md|markdown|docx)$/i.test(file.name);
    if (!supported) {
      setNotice('Formato no admitido. Elige un archivo TXT, Markdown o DOCX.');
      return;
    }
    if (file.size > 20 * 1024 * 1024) {
      setNotice('El archivo supera el límite de 20 MB.');
      return;
    }
    await run('Extrayendo y preparando archivo', async () => {
      const bytes = new Uint8Array(await file.arrayBuffer());
      let binary = '';
      const chunkSize = 0x8000;
      for (let offset = 0; offset < bytes.length; offset += chunkSize) {
        binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
      }
      const result = await call('upload', { name: file.name, data: btoa(binary) });
      if (alive.current) {
        setReader(result);
        setTranslated('');
        setSpeech('idle');
        speechGeneration.current++;
        window.speechSynthesis?.cancel();
        setNotice('Archivo extraído y preparado. No se guardó en el Workshop.');
      }
    });
  }

  async function checkStatus() {
    const result = await call('reader-status', {});
    if (alive.current) setReaderStatus(result);
  }

  async function translate() {
    const result = await call('translate', { text: reader.original });
    if (alive.current) {
      setTranslated(result.text);
      setNotice(result.skipped ? 'El texto ya está en español; puedes escucharlo directamente.' : 'Traducción local lista.');
    }
  }

  async function speak() {
    if (!window.speechSynthesis || !window.SpeechSynthesisUtterance) throw new Error('Este navegador no permite lectura en voz alta.');
    const modulePath = '/reader/speech-text.js';
    const { splitParagraphs, buildChunks } = await import(/* @vite-ignore */ modulePath);
    if (!alive.current) return;
    const text = translated || reader?.original || '';
    const chunks = buildChunks(splitParagraphs(text));
    if (!chunks.length) throw new Error('No hay texto disponible para leer.');
    const generation = ++speechGeneration.current;
    window.speechSynthesis.cancel();
    let position = 0;
    const next = () => {
      if (!alive.current || generation !== speechGeneration.current) return;
      if (position >= chunks.length) { setSpeech('idle'); return; }
      const utterance = new SpeechSynthesisUtterance(chunks[position++].text);
      utterance.lang = translated || reader.language?.is_spanish ? 'es-ES' : '';
      utterance.rate = speed;
      utterance.onend = next;
      utterance.onerror = () => {
        if (alive.current && generation === speechGeneration.current) {
          setSpeech('idle');
          setNotice('La lectura se detuvo o no está disponible.');
        }
      };
      window.speechSynthesis.speak(utterance);
    };
    setSpeech('playing');
    next();
  }

  const spanish = translated || reader?.original || '';
  const speechLabel = speech === 'playing' ? 'Leyendo en voz alta' : speech === 'paused' ? 'Lectura en pausa' : 'Listo para escuchar';

  return (
    <section className="reader-workspace" aria-labelledby="reader-title">
      <header className="reader-heading">
        <div>
          <p className="reader-eyebrow">LECTURA ASISTIDA</p>
          <h3 id="reader-title">Prepara tu lectura</h3>
          <p>Abre un documento del Workshop, revisa el texto limpio, tradúcelo al español y escúchalo.</p>
        </div>
        <span className="reader-local-badge"><span aria-hidden="true">●</span> Procesamiento local</span>
      </header>

      <div className="reader-source">
        <div className="reader-source-title">
          <span className="reader-step">1</span>
          <div><strong>Elige el documento</strong><span>TXT, Markdown o DOCX</span></div>
        </div>
        <label className="interaction-field">
          Ruta relativa al Workshop
          <input value={readerPath} onChange={(event) => setReaderPath(event.target.value)} placeholder={item?.relativePath || 'applications/…/documento.md'} />
        </label>
        <div className="reader-source-actions">
          <button className="button button--primary" disabled={!!busy} onClick={() => run('Preparando documento', load)}>
            {busy === 'Preparando documento' ? 'Preparando…' : 'Abrir y preparar'}
          </button>
          <button className="reader-status-button" disabled={!!busy} onClick={() => run('Comprobando traducción local', checkStatus)}>Comprobar traducción local</button>
        </div>
        <div className="reader-input-options">
          <label className="interaction-field">Pegar texto
            <textarea rows={3} value={pastedText} onChange={(event) => setPastedText(event.target.value)} placeholder="Pega aquí el texto que quieres limpiar y leer…" />
            <button type="button" className="button" disabled={!!busy || !pastedText.trim()} onClick={() => run('Preparando texto pegado', preparePastedText)}>Preparar texto pegado</button>
          </label>
          <label className="interaction-field">O subir un archivo
            <input type="file" accept=".txt,.md,.markdown,.docx" disabled={!!busy} onChange={(event) => { const file = event.target.files?.[0]; if (file) uploadFile(file); event.target.value = ''; }} />
            <small>TXT, Markdown o DOCX · hasta 20 MB · no se guarda</small>
          </label>
        </div>
        {readerStatus ? <p className={`reader-model-state ${readerStatus.translation_available ? 'is-ready' : 'is-unavailable'}`} role="status">
          <span aria-hidden="true">{readerStatus.translation_available ? '●' : '○'}</span> Traducción local {readerStatus.translation_available ? 'disponible' : 'no disponible'}. {readerStatus.translation_message} {readerStatus.model ? `Modelo: ${readerStatus.model}.` : ''}
        </p> : <p className="reader-privacy">El documento se procesa en este equipo. Solo se envía a Ollama local si eliges traducir.</p>}
      </div>

      {reader ? <>
        <div className="reader-step-heading"><span className="reader-step">2</span><div><strong>Vista previa · {reader.path || 'Texto preparado'}</strong><span>{reader.language?.name ? `Idioma detectado: ${reader.language.name}` : 'Texto extraído y limpiado'}</span></div></div>
        <div className="reader-panes">
          <article className="reader-pane">
            <div className="reader-pane-head"><h4>Original</h4><span>{reader.language?.is_spanish ? 'Ya está en español' : reader.language?.name || 'Idioma detectado'}</span></div>
            <pre className="reader-text">{reader.original}</pre>
          </article>
          <article className={`reader-pane ${translated ? 'reader-pane--spanish' : 'reader-pane--empty'}`}>
            <div className="reader-pane-head"><h4>Español</h4><span>{translated ? 'Traducción lista' : 'Aún sin traducir'}</span></div>
            {translated ? <pre className="reader-text">{translated}</pre> : <div className="reader-empty">
              <span className="reader-empty-icon" aria-hidden="true">文</span>
              <p>{reader.language?.is_spanish ? 'El original ya está en español.' : 'La traducción aparecerá aquí y conservará el original.'}</p>
              {reader.language?.is_spanish ? null : <button className="button" disabled={!!busy} onClick={() => run('Traduciendo con Ollama local (no se puede cancelar)', translate)}>{busy.startsWith('Traduciendo') ? 'Traduciendo…' : 'Traducir al español'}</button>}
              <small>Se procesa únicamente con Ollama en este equipo.</small>
            </div>}
          </article>
        </div>

        <div className="reader-listen">
          <div className="reader-listen-copy"><span className="reader-step">3</span><div><strong>Escucha</strong><span>{speechLabel} · {translated ? 'versión en español' : 'texto original'}</span></div></div>
          <label className="reader-speed">Velocidad<select value={speed} onChange={(event) => setSpeed(Number(event.target.value))}>{[1, 1.2, 1.5, 1.75, 2].map((value) => <option key={value} value={value}>{String(value).replace('.', ',')}×</option>)}</select></label>
          <div className="reader-controls">
            <button className="button button--primary" disabled={!!busy || speech === 'playing'} onClick={() => run('Preparando voz', speak)}>{speech === 'paused' ? 'Reanudar lectura' : '▶  Leer en voz alta'}</button>
            <button className="button" disabled={speech !== 'playing'} onClick={() => { window.speechSynthesis.pause(); setSpeech('paused'); }}>Pausar</button>
            <button className="button" disabled={speech !== 'paused'} onClick={() => { window.speechSynthesis.resume(); setSpeech('playing'); }}>Continuar</button>
            <button className="button" disabled={speech === 'idle'} onClick={() => { speechGeneration.current++; window.speechSynthesis.cancel(); setSpeech('idle'); }}>Detener</button>
          </div>
        </div>
        <p className="reader-speech-privacy">Algunas voces del navegador pueden enviar el texto a un servicio de voz en línea.</p>
      </> : busy ? <div className="reader-first-use" aria-live="polite"><span aria-hidden="true">…</span><p>Preparando vista previa</p><small>Extrayendo y limpiando el texto del documento.</small></div> : <div className="reader-first-use"><span aria-hidden="true">Aa</span><p>Tu espacio de lectura aparecerá aquí</p><small>{item ? 'Abre el recurso seleccionado o pega texto / sube un archivo.' : 'Escribe una ruta del Workshop, pega texto o sube un archivo para empezar.'}</small></div>}
      <p className="reader-notice" role="status" aria-live="polite">{busy || notice}</p>
    </section>
  );
}
