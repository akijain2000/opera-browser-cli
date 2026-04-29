# Fix: streaming timeout reset on chunks + cleanup on cancellation

## Context

Opera AI streaming tools (`opera_do`, `opera_research`) can run for extended periods. Two problems:

1. **No cleanup on cancellation**: `dispatchWithStreamedResponse()` (`opera.ts:52-105`) registers CDP event listeners in a Promise that waits for `Opera.actionCompleted`/`Opera.actionFailed`. If the MCP SDK timeout fires or the bridge cancels the request, the SDK sends `notifications/cancelled` but the Promise and its listeners hang forever — leaking resources.

2. **Fixed timeout kills active streams**: The bridge passes `{ timeout: 300_000 }` (5 min) to `callTool`. The MCP SDK's `resetTimeoutOnProgress` only resets on `notifications/progress` (not `notifications/message` which we use for streaming logs). A long research call that streams chunks every few seconds is killed at 5 minutes regardless of activity.

## Root cause analysis

### Timeout chain (outside-in)

| Layer | Value | Mechanism |
|---|---|---|
| CLI HTTP socket | 20 min | `request({ timeout: 1_200_000 })` — idle socket timer, reset by streaming chunks |
| Bridge → MCP SDK | 5 min | `callTool(..., { timeout: 300_000 })` — SDK `setTimeout`, NOT reset by log notifications |
| MCP SDK default | 60 sec | `DEFAULT_REQUEST_TIMEOUT_MSEC` — used for non-Opera tools |
| SW retry loop | 4 sec total | 5 retries × 1 sec delay — guards initial `session.send()` only |
| Streaming event-listener Promise | **∞** | No timeout, no cleanup on cancellation |

### Why `resetTimeoutOnProgress` doesn't help

The SDK's `resetTimeoutOnProgress` only resets on `notifications/progress` (with a matching `progressToken`). Streaming chunks arrive via `notifications/message` (logging), which is a different notification type. The SDK ignores logging notifications for timeout purposes.

### Why the event-listener Promise leaks

When the MCP SDK's 5-minute timeout fires on the client (bridge) side:
1. SDK sends `notifications/cancelled` to `opera-devtools-mcp`
2. SDK rejects `callTool` → bridge closes the HTTP response with 500
3. `opera-devtools-mcp` receives cancellation → `extra.signal` aborts
4. BUT: nothing reads `extra.signal` — it is never forwarded to tool handlers
5. `dispatchWithStreamedResponse()` Promise keeps waiting for `Opera.actionCompleted` that may never come
6. CDP event listeners (`Opera.actionChunk`, `Opera.actionCompleted`, `Opera.actionFailed`) stay registered indefinitely

---

## Fix

### Part 1 — Bridge: AbortController with per-chunk timeout reset

**File**: `opera-cli/src/bridge.ts`

Replace `{ timeout: OPERA_AI_TIMEOUT }` with a bridge-managed `AbortController` whose timer resets each time a chunk arrives through `requestLoggers`:

```typescript
// In handleCallRequest, streaming path:
const controller = new AbortController();
let timer = setTimeout(() => controller.abort(), OPERA_AI_TIMEOUT);

// ... captureNextId / callTool setup (pass { signal: controller.signal } as options) ...

requestLoggers.set(mcpRequestId, (chunk) => {
  clearTimeout(timer);
  timer = setTimeout(() => controller.abort(), OPERA_AI_TIMEOUT);
  res.write(JSON.stringify({ log: chunk }) + "\n");
});

try {
  const result = await callPromise;
  // ... write result ...
} catch (error) {
  // ... write error (includes timeout/abort) ...
} finally {
  clearTimeout(timer);
  requestLoggers.delete(mcpRequestId);
}
```

**How it works**: Each streaming chunk resets the 5-minute timer. If no chunk arrives for 5 minutes, the `AbortController` fires. The MCP SDK then sends `notifications/cancelled` to `opera-devtools-mcp`, which triggers `extra.signal` on the server side. The bridge receives a rejection and returns a 500.

### Part 2 — Server: wire `extra.signal` into tool handlers

**File**: `opera-devtools-mcp/src/tools/ToolDefinition.ts`

Add `signal?: AbortSignal` to the `Request` interface:

```typescript
interface Request<Schema> {
  params: zod.objectOutputType<Schema, zod.ZodTypeAny>;
  signal?: AbortSignal;
}
```

**File**: `opera-devtools-mcp/src/index.ts`

Pass `extra.signal` when constructing the request object in `registerTool`:

```typescript
// page-scoped:
tool.handler({ params, page, signal: extra.signal }, response, context);
// non-page-scoped:
tool.handler({ params, signal: extra.signal }, response, context);
```

This makes `request.signal` available to all tool handlers. Only Opera streaming tools consume it today, but the infrastructure is available for other long-running tools (lighthouse, performance traces) in the future.

### Part 3 — Server: clean up listeners on cancellation

**File**: `opera-devtools-mcp/src/tools/opera.ts`

Add `signal?: AbortSignal` parameter to `dispatchWithStreamedResponse`. Inside the event-listener Promise, add an abort listener that calls `cleanup()` and `reject()`:

```typescript
const dispatchWithStreamedResponse = (
  session: CDPSession,
  payload: Record<string, unknown>,
  onChunkCallback?: (chunk: string) => void,
  signal?: AbortSignal,
): Promise<string> => {
  return withServiceWorkerRetry(() =>
    session.send('Opera.dispatchWithStreamedResponse', {payload}),
  ).then(raw => {
    const {correlationId} = raw as {correlationId: string};
    return new Promise<string>((resolve, reject) => {
      // ... existing onChunk, onCompleted, onFailed, cleanup ...

      // Early exit if already cancelled
      if (signal?.aborted) {
        reject(signal.reason);
        return;
      }
      // Clean up listeners when the MCP request is cancelled
      signal?.addEventListener('abort', () => {
        cleanup();
        reject(signal.reason);
      }, { once: true });

      session.on('Opera.actionChunk', onChunk);
      session.on('Opera.actionCompleted', onCompleted);
      session.on('Opera.actionFailed', onFailed);
    });
  });
};
```

In `operaDo` and `operaResearch` handlers, pass `request.signal`:

```typescript
const result = await dispatchWithStreamedResponse(
  session,
  { action: 'do', prompt: request.params.prompt },
  chunk => response.sendLog(chunk),
  request.signal,
);
```

---

## Correctness guarantees

| Scenario | Behaviour |
|---|---|
| Stream completes normally | Timer cleared in `finally`; listeners cleaned up by `onCompleted` ✓ |
| Stream active with chunks every minute | Timer resets on each chunk; 5-min idle timeout never fires ✓ |
| Stream stalls (no chunks for 5 min) | AbortController fires → SDK cancels → server cleans up listeners ✓ |
| Browser crashes mid-stream | No more chunks → timer fires after 5 min → cancellation + cleanup ✓ |
| Non-streaming Opera tool (chat, make) | Uses AbortController path (in OPERA_AI_TOOLS); no chunks emitted so timer acts as fixed 5-min hard timeout — same as previous `{ timeout }` ✓ |
| Multiple concurrent streams | Each has its own AbortController + timer; independent ✓ |

## Files changed

| File | Change |
|---|---|
| `opera-cli/src/bridge.ts` | Replace `{ timeout }` with AbortController + per-chunk timer reset |
| `opera-devtools-mcp/src/tools/ToolDefinition.ts` | Add `signal?: AbortSignal` to `Request` |
| `opera-devtools-mcp/src/index.ts` | Pass `extra.signal` in request object to handlers |
| `opera-devtools-mcp/src/tools/opera.ts` | Add signal to `dispatchWithStreamedResponse`; wire it in `operaDo`/`operaResearch` |

## Verification

1. `cd opera-cli && npx tsc --noEmit` — type check
2. `cd opera-cli && npx vitest run` — all tests pass
3. `cd opera-devtools-mcp && npm run build` — clean build
