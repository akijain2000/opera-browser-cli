# Fix: parallel streaming chunk routing

## Problem

When two terminals run concurrent `opera-cli invoke-do` (or `research`) commands,
the streaming progress chunks appear in both terminals instead of only in the terminal
that fired each request.

### Root cause

`bridge.ts` maintained a single global variable `onLogMessage` that pointed to the HTTP
response writer for the "current" streaming call:

```typescript
let onLogMessage: ((data: unknown) => void) | undefined;
```

When request **A** arrived, `onLogMessage` was set to write into `res_A`.
When request **B** arrived concurrently, `onLogMessage` was overwritten to write into
`res_B`. From that point every MCP notification — regardless of which tool call
produced it — went to `res_B`. When **B** finished, the `finally` block restored
`onLogMessage` to its saved value (`res_A`), so remaining chunks from A started
flowing to `res_A`. The result was chunks split unpredictably between the two terminals.

The MCP SDK provides a `relatedRequestId` mechanism in its transport options, but the
`StdioClientTransport` ignores that field — it is only used by the HTTP/streamable
transports. So notifications arriving over stdio carry no built-in per-request
correlation.

### Why switching to `extra.sendNotification` did not fully fix it

Using `extra.sendNotification` (request-scoped on the server side) was the right
direction, but the routing gap is on the **client** (bridge) side: all notifications
still entered through a single `setNotificationHandler` callback that read the same
global `onLogMessage`.

---

## Fix

Two focused changes, one per repository. No custom tokens, no tool-schema changes,
no private SDK field access.

### 1 — `opera-devtools-mcp/src/index.ts` (MCP server)

Embed the server's natural per-request identity (`extra.requestId`) in the
notification's `logger` field. The `data` field stays a plain string so non-bridge
MCP hosts (Claude Desktop, VS Code, etc.) continue to render it as readable text.

```typescript
const logCallback = (message: string) => {
  // `logger` carries the MCP request ID so the opera-cli bridge can route
  // this chunk to the correct HTTP response (see bridge.ts requestLoggers).
  // `data` stays a plain string so non-bridge MCP hosts (Claude Desktop,
  // VS Code, etc.) continue to render it as readable text.
  void extra.sendNotification({
    method: 'notifications/message',
    params: { level: 'info', data: message, logger: String(extra.requestId) },
  });
};
```

`extra.requestId` is the JSON-RPC request ID that the MCP client used for this
`tools/call` invocation — it is unique per in-flight request and equals the ID that
the bridge sent.

**Why `logger`, not a structured `data` object?**
The MCP `LoggingMessageNotification` schema already includes an optional `logger`
string field (intended to identify the logger source). Using it keeps `data` as a
plain string, so all non-bridge consumers see readable log text without any change.
Embedding the ID in `data` (e.g. `{requestId, chunk}`) would break those consumers.

### 2 — `opera-cli/src/bridge.ts` (bridge / MCP client)

Replace the global `onLogMessage` with a `Map<requestId, chunkWriter>` and wrap
the transport's `send` method to capture the outgoing request ID for each
`callTool` call.

#### 2a — Transport wrapper (capture outgoing request ID)

```typescript
type IdResolver = { resolve: (id: string) => void; reject: (err: Error) => void };

export function wrapTransportForIdCapture(
  transport: StdioClientTransport,
): () => Promise<string> {
  const queue: IdResolver[] = [];
  const origSend = transport.send.bind(transport) as (
    msg: JSONRPCMessage,
    options?: TransportSendOptions,
  ) => Promise<void>;

  transport.send = (async (msg: JSONRPCMessage, options?: TransportSendOptions) => {
    if ("id" in msg && "method" in msg && queue.length > 0) {
      queue.shift()!.resolve(String((msg as { id: unknown }).id));
    }
    return origSend(msg, options);
  }) as unknown as StdioClientTransport["send"];

  // Drain pending captures on disconnect so handleCallRequest does not hang.
  const origOnClose = transport.onclose;
  transport.onclose = () => {
    const err = new Error("MCP transport disconnected");
    while (queue.length > 0) queue.shift()!.reject(err);
    origOnClose?.();
  };

  return () => new Promise<string>((resolve, reject) => queue.push({ resolve, reject }));
}
```

**How it works:** `client.callTool()` calls `transport.send(jsonrpcRequest)` *before*
its first `await` (the request ID is assigned synchronously in the MCP SDK's Promise
constructor). The wrapper intercepts this first send and resolves the pending promise
with that request ID. Single-threaded JS guarantees FIFO ordering even under
concurrent requests.

**INVARIANT:** The MCP SDK's `Client.request()` calls `transport.send()` synchronously
inside its Promise constructor. Verify this invariant when upgrading
`@modelcontextprotocol/sdk`.

#### 2b — Per-request notification routing

```typescript
// Replace the global onLogMessage with a Map
const requestLoggers = new Map<string, (chunk: string) => void>();

// In createBridgeClient():
client.setNotificationHandler(LoggingMessageNotificationSchema, (notification) => {
  const { data, logger } = notification.params;
  if (logger && requestLoggers.has(logger)) {
    const chunk = typeof data === "string" ? data : JSON.stringify(data);
    requestLoggers.get(logger)!(chunk);
  }
  // No matching logger: notification from a non-Opera tool or older server — ignore.
});
```

#### 2c — Updated `handleCallRequest`

```typescript
async function handleCallRequest(
  client: BridgeClient,
  req: IncomingMessage,
  res: ServerResponse,
  captureNextId?: () => Promise<string>,
): Promise<void> {
  const body = await readRequestBody(req);
  const payload = parseBridgeCallPayload(body);
  const isStreamable = OPERA_AI_TOOLS.has(payload.name);
  const options = isStreamable ? { timeout: OPERA_AI_TIMEOUT } : undefined;

  let mcpRequestId: string | undefined;
  if (isStreamable && captureNextId) {
    // Register the capture BEFORE calling callTool so the synchronous
    // transport.send fires into our queue before we await the result.
    const idCapture = captureNextId();
    const callPromise = client.callTool(
      { name: payload.name, arguments: payload.args },
      undefined,
      options,
    );
    mcpRequestId = await idCapture;
    requestLoggers.set(mcpRequestId, (chunk) => {
      res.write(JSON.stringify({ log: chunk }) + "\n");
    });
    try {
      const result = await callPromise;
      const text = extractToolText(getToolContent(result));
      res.statusCode = 200;
      res.end(JSON.stringify({ result: text }));
    } catch (error) {
      res.statusCode = 500;
      res.end(JSON.stringify({ error: getErrorMessage(error) }));
    } finally {
      requestLoggers.delete(mcpRequestId);
    }
    return;
  }

  // Non-streaming path (unchanged).
  try {
    const result = await client.callTool(
      { name: payload.name, arguments: payload.args },
      undefined,
      options,
    );
    const text = extractToolText(getToolContent(result));
    res.statusCode = 200;
    res.end(JSON.stringify({ result: text }));
  } catch (error) {
    res.statusCode = 500;
    res.end(JSON.stringify({ error: getErrorMessage(error) }));
  }
}
```

#### 2d — Thread `captureNextId` through callers

`handleBridgeRequest`, `createBridgeServer`, and `runBridge` each accept a
`captureNextId?: () => Promise<string>` parameter and pass it to `handleCallRequest`.

```typescript
// runBridge
const transport = createTransport();
const captureNextId = wrapTransportForIdCapture(transport);
const client = createBridgeClient();
await client.connect(transport);
const server = createBridgeServer(client, captureNextId);
```

---

## Correctness guarantees

| Scenario | Behaviour |
|---|---|
| Single streaming call | `captureNextId` → `callTool` → ID captured → logger registered → chunks routed ✓ |
| Two concurrent streaming calls | Each gets its own Map entry; notifications routed by their distinct `requestId` values ✓ |
| Non-streaming tool call | Falls through to the non-streaming path; no change ✓ |
| Transport disconnect mid-call | Pending `captureNextId` promises reject with `"MCP transport disconnected"` ✓ |
| Non-bridge MCP host (Claude Desktop, VS Code) | `data` stays a plain string; `logger` field is ignored — no behaviour change ✓ |

## Files changed

| File | Change |
|---|---|
| `opera-devtools-mcp/src/index.ts` | `logCallback` sends `String(extra.requestId)` in the `logger` field; `data` stays a plain string |
| `opera-cli/src/bridge.ts` | Replace global `onLogMessage`; add transport wrapper with FIFO queue and disconnect drain; update 4 function signatures; route chunks via `requestLoggers` Map keyed on `logger` field |
| `opera-cli/test/bridge.test.ts` | Unit tests for `wrapTransportForIdCapture` (FIFO, disconnect drain, forwarding) and `handleBridgeRequest` streaming path (single call, error path, concurrent routing) |
