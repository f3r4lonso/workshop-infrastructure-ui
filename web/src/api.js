// Same-origin client for the local server (see docs/web-architecture.md §2).
import { MESSAGES } from './constants.js';

export class ApiError extends Error {
  constructor(message, { unreachable = false } = {}) {
    super(message);
    this.name = 'ApiError';
    this.unreachable = unreachable;
  }
}

let token = null;
function workshopToken() {
  if (token === null) {
    token = document.querySelector('meta[name="workshop-token"]')?.getAttribute('content') ?? '';
  }
  return token;
}

// Dev-only: when the backend is not running, `npm run dev` falls back to mock data.
// import.meta.env.DEV is false in production builds, so the mock module is tree-shaken away.
let mock = null;
async function devMock(error) {
  if (!import.meta.env.DEV) throw error;
  if (!mock) {
    mock = await import('./mock-data.js');
    console.warn('[workshop] API unavailable, using mock data (dev only).', error);
  }
  return mock;
}

async function request(path, { method = 'GET', body } = {}) {
  const headers = { Accept: 'application/json' };
  if (method === 'POST') {
    headers['Content-Type'] = 'application/json';
    headers['X-Workshop-Token'] = workshopToken();
  }
  let response;
  try {
    response = await fetch(`./api/${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      cache: 'no-store',
      credentials: 'same-origin',
    });
  } catch {
    throw new ApiError(MESSAGES.unreachable, { unreachable: true });
  }
  let json = null;
  try {
    json = await response.json();
  } catch {
    // Not JSON: a proxy error page or an unexpected response.
  }
  if (json && typeof json === 'object') {
    // Error bodies are {"ok": false, "message": "<Spanish>"}; callers read ok/message.
    if (!response.ok && json.ok !== false) throw new ApiError(json.message || MESSAGES.unexpected);
    return json;
  }
  const unreachable = response.status >= 500;
  throw new ApiError(unreachable ? MESSAGES.unreachable : MESSAGES.unexpected, { unreachable });
}

function assertData(json) {
  if (json.ok === false) throw new ApiError(json.message || MESSAGES.unexpected);
  if (!Array.isArray(json.items)) throw new ApiError(MESSAGES.unexpected);
  return json;
}

export async function getData() {
  if (mock) return mock.getData();
  try {
    return assertData(await request('data'));
  } catch (error) {
    return (await devMock(error)).getData();
  }
}

export async function refreshData() {
  if (mock) return mock.getData();
  return assertData(await request('refresh', { method: 'POST', body: {} }));
}

export async function getClients() {
  if (mock) return mock.getClients();
  try {
    const json = await request('clients');
    if (!Array.isArray(json.clients)) throw new ApiError(json.message || MESSAGES.unexpected);
    return json.clients;
  } catch (error) {
    return (await devMock(error)).getClients();
  }
}

/** Resolves to {ok, message}; server-side refusals come back as ok: false. */
export async function openItem(id, target) {
  if (mock) return mock.open(id, target);
  return request('open', { method: 'POST', body: { id, target } });
}

export async function launchClient(client) {
  if (mock) return mock.launch(client);
  return request('launch', { method: 'POST', body: { client } });
}

// Interaction never falls back to demo data: edits and dispatch need the real server.
export function interaction(action, body = {}) {
  return request(`interaction/${action}`, { method: 'POST', body });
}
