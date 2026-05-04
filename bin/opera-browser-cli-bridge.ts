#!/usr/bin/env tsx

import { getErrorMessage, runBridge } from "../src/bridge.js";

runBridge().catch((error) => {
  process.stderr.write(`[opera-browser-cli] Fatal: ${getErrorMessage(error)}\n`);
  process.exit(1);
});
