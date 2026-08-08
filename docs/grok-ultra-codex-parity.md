# Grok Ultra versus Codex Ultra

Reference snapshots used for this comparison:

- Grok Ultra branch: `agent/grok-ultra-selfuse`
- Codex: `openai/codex@a7dcd20d3895ec4c9cbdde534745bbffbc2d2e28`

This document distinguishes **core user-facing collaboration parity** from exact implementation parity. The two products use different models, so equivalent client orchestration cannot guarantee identical answer quality.

## Core behavior already present

Grok Ultra currently provides:

- a first-class `grok-build-ultra` profile;
- proactive delegation guidance while the primary agent retains normal read/edit/terminal/test tools;
- the model-facing controls `spawn_agent`, `send_message`, `followup_task`, `wait_agent`, `interrupt_agent`, and `list_agents`;
- stable task names as child handles;
- parent-context inheritance and selected-Grok-model inheritance;
- optional child model and worktree isolation selection;
- atomic bounded admission of pending plus running interactive children;
- truthful acknowledgement of background startup;
- live message injection, terminal-child continuation, cancellation, completion surfacing, and final parent synthesis;
- highest-effective reasoning effort selection based on the chosen Grok model's advertised capability.

These cover the main workflow a user experiences as “Ultra”: the primary agent decides when parallel work is valuable, launches bounded collaborators, keeps working, steers them, waits only when blocked, and integrates their output.

## Reasoning-mode equivalence

Codex keeps `Ultra` as a client/session setting because it also selects the proactive Multi-Agent V2 policy. Before a model request is built, the current Codex client maps `ReasoningEffort::Ultra` to the wire-level `Max` effort. Therefore, Codex Ultra is not evidence of a separate server-side effort above `max`.

Grok Ultra follows the same product-level separation:

- the Ultra profile activates proactive multi-agent behavior;
- the selected Grok model remains unchanged;
- the request uses the strongest effort that the selected Grok model actually advertises, preferring `max` when available and degrading to another verified level rather than sending an unsupported value.

The remaining model difference is ordinary model capability: a Grok model and the model used by Codex can produce different results even with equivalent effort and orchestration.

## Remaining differences

### 1. Per-child spawn controls — meaningful but not required for the basic loop

Codex V2 can select per child:

- reasoning effort;
- service tier;
- context fork mode: none, all history, or the last N turns;
- role plus full-history precedence;
- canonical environment selections.

Grok Ultra currently supports task name, role/type, optional model, and optional worktree isolation. Its profile defaults to normalized parent-context inheritance rather than exposing `none/all/N` on each spawn.

### 2. Agent identity and tree topology — observability and recursive-management gap

Codex assigns canonical `AgentPath` identities, parent thread/turn provenance, role/nickname metadata, and can list a rooted agent tree. Grok Ultra uses session-scoped task-name handles and a flatter roster. It does not yet expose an equally rich recursive tree to the model or user.

### 3. Wait semantics — behavioral gap

Codex `wait_agent` V2 waits for agent-mailbox activity and can be interrupted by user steering; the event need not be terminal completion. Grok Ultra currently delegates to Grok Build's `WaitTasks` `WaitAny` path and returns when a selected child reaches a terminal state or the timeout expires.

Live correction remains available through `send_message`, but the wait primitive itself is less expressive.

### 4. Follow-up identity continuity — implementation gap

Codex can trigger a new turn on the same registered agent. Grok Ultra sends a live follow-up to a running child, but a completed/failed/cancelled child is resumed as a new background child with a new handle while retaining the persisted conversation.

The conversational continuity is retained; the registry identity is not.

### 5. Interrupt semantics — implementation gap

Codex can interrupt an agent's current work while keeping that registered agent available for later turns. Grok Ultra maps interruption onto the existing child cancellation path and relies on `followup_task` resume for subsequent work.

### 6. Message metadata and communication topology — implementation gap

Codex carries richer author/recipient paths, source metadata, and communication events. Grok Ultra currently carries plain-text parent-to-child instructions through the existing interjection channel and does not expose direct sibling-to-sibling routing.

### 7. Dedicated UI and telemetry — product gap

Codex has dedicated Ultra presentation, concurrency warnings, canonical activity items, nicknames, and multi-agent telemetry. Grok Ultra is selectable through `/agents` and uses Grok Build's existing child/task views, but it does not yet reproduce the full Codex Ultra visual language and analytics surface.

### 8. Proven outcome parity — still unverified

Compilation and deterministic runtime tests establish that the collaboration mechanics are connected. They do not establish equal quality on real repositories. Acceptance still requires repeated same-task trials across:

1. normal Grok Build;
2. Grok Ultra;
3. Codex Ultra.

Measure correctness, coverage, wall-clock time, token/cost use, duplicate work, conflicting writes, premature completion, useful child-result adoption, and required user intervention.

## Current assessment

Grok Ultra has **core workflow parity**, not exact feature parity. It is ready for isolated self-use evaluation, but it should not yet be described as indistinguishable from Codex Ultra.

The highest-impact remaining client-side improvements are:

1. per-child `fork_turns`, reasoning effort, and service-tier controls;
2. activity/mailbox-based `wait_agent` with user-steering wake-up;
3. stable same-agent continuation after completion/interruption;
4. canonical recursive agent paths and tree inspection;
5. dedicated Ultra activity UI and telemetry.
