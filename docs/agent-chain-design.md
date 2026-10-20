# Ordered agent chains

Status: decision accepted; initial implementation complete (2026-10-20). Real account access and live chain execution remain unverified.

## Goal

Let the user choose a small ordered list of Workshop agents, give the chain a goal and give each agent a direction. Run the agents in order and pass each completed output to the next agent through the local UI.

## Research and decision

Claude Code documents print mode (`claude -p`) as a non-interactive query interface and supports reading prompt content from stdin. Its CLI provides JSON output, no-session-persistence, and flags that restrict built-in tools; the current Workshop transport already uses a fresh print-mode process, stdin, an isolated temporary directory, strict empty MCP configuration, restricted/safe mode, and no session persistence. The implementation therefore runs one verified tool-free Claude request per selected profile and chains plain-text results in the Workshop server. It does not depend on Claude's experimental agent teams, which target parallel collaboration and add coordination and token overhead. See [Claude CLI reference](https://code.claude.com/docs/en/cli-reference) and [agent teams guidance](https://code.claude.com/docs/en/agent-teams).

The transport requires Claude Code 2.1.259 or newer because `--permission-prompts none` is documented from that release. The local capability check runs only the fixed `claude.exe --version` command with stdin closed, an isolated working directory and a five-second timeout; it does not inspect credentials. Account/model access stays unknown until an explicitly started request succeeds.

## Product decisions

- The current React page is a sequential pipeline editor with 2–5 ordered, unique agents from the canonical Workshop agent and personal-assistant catalogues. Drag-independent move up/down controls keep the order keyboard accessible.
- One explicit goal, one selected Claude model, and optional per-agent directions apply to the run. Other client transports stay unavailable until independently verified.
- Each choice selects a canonical Workshop instruction profile passed as text to a new CLI request; it does not create or resume a native Claude subagent session.
- Each stage receives the original goal, its own direction, and the immediately preceding stage's output. Handoff text is labelled as untrusted data; each stage is a fresh request with no conversation history.
- The UI shows a separate status and output for every stage. The next request starts only after the preceding response is confirmed complete. Failure, timeout, invalid output, or ambiguous delivery stops the chain; no retry is automatic.
- Start is an explicit action that states how many model requests will be made. The UI says this can consume the selected account's quota. The application does not claim to know account access or estimate a price.
- A stop request prevents later stages from starting. An active CLI request cannot be interrupted through the verified transport, so the UI explains that it will finish first.
- One chain runs at a time. Run state and outputs stay in bounded server memory only; there is no database, file persistence, browser storage, or background scheduling. The page can recover the active/latest run after a browser refresh while the server remains running; server restart loses the run. The user can clear results.
- The chain is limited to five steps, bounded prompt and response sizes, and the existing request timeout/output controls. Agent profiles are read from canonical resources by ID. User content and model outputs never enter process arguments or server logs.
- Chaining transfers text, not tool access or modified client state. Every stage retains the existing no-tools, no-MCP, isolated, no-session-persistence transport.

## Acceptance criteria

1. Add, remove, select, and reorder 2–5 distinct canonical agents; preserve the configured order in the run.
2. Require a non-empty goal, an available verified Claude transport, and an explicit start click. Show the number of requests before start.
3. Run one stage at a time and visibly identify pending, running, completed, failed, uncertain, and cancelled states.
4. Pass exactly the previous completed output and original goal into the next step, with the current agent profile and optional direction.
5. Stop before any subsequent request after a failure or a stop request. Never retry an uncertain request.
6. Retain completed outputs for review until the user clears them or the server stops; safely render outputs as text.
7. Reject malformed, oversized, duplicate, unknown, or non-agent steps and keep all routes behind the existing Host, token, Origin, and JSON-size protections. Recover run state after page refresh without persisting outputs to disk.
8. Automated tests cover validation, ordering/handoff, stop/failure behavior, uncertainty, bounds, and the same-origin API. Production frontend build passes.

## Rollback and limits

Remove the chain panel and its start/status/stop/clear API routes; leave the existing reader, resource browser, client launchers, and single-request transport intact. No live chain is run during development. Account billing and model access remain dependent on the user's existing Claude CLI configuration.

## Verification record

Automated tests cover order and handoff, canonical-profile lookup, invalid/duplicate steps, oversized outputs, stop-after-current-stage, uncertain results, failures, memory-state recovery, explicit same-origin API protection and the existing server behavior. The production frontend build is required. No real Claude request is sent as part of development verification.
