#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_ROOT="$(dirname "$SCRIPT_DIR")"
MCP_ROOT="$(dirname "$CLI_ROOT")/opera-devtools-mcp"

VERSION="$(node -p "require('$CLI_ROOT/package.json').version")"
MCP_VERSION="$(node -p "require('$MCP_ROOT/package.json').version")"
STAGING="$CLI_ROOT/.dist-staging"
DIST_NAME="opera-cli-${VERSION}"
DIST_DIR="$STAGING/$DIST_NAME"

echo "==> Building opera-cli v${VERSION}"

# ── 1. Build opera-devtools-mcp ──────────────────────────────────────────────
if [ ! -d "$MCP_ROOT" ]; then
  echo "ERROR: opera-devtools-mcp not found at $MCP_ROOT" >&2
  exit 1
fi

echo "  -> Building opera-devtools-mcp..."
(cd "$MCP_ROOT" && npm run bundle)

# ── 2. Build opera-cli ───────────────────────────────────────────────────────
echo "  -> Building opera-cli..."
(cd "$CLI_ROOT" && npm run build)

# ── 3. Prepare staging directory ─────────────────────────────────────────────
rm -rf "$STAGING"
mkdir -p "$DIST_DIR/bin" "$DIST_DIR/opera-cli" "$DIST_DIR/opera-devtools-mcp"

# ── 4. Copy opera-cli artifacts ──────────────────────────────────────────────
cp -R "$CLI_ROOT/dist" "$DIST_DIR/opera-cli/dist"
cp "$CLI_ROOT/package.json" "$DIST_DIR/opera-cli/"
cp "$CLI_ROOT/package-lock.json" "$DIST_DIR/opera-cli/"

# Install production-only dependencies
echo "  -> Installing production dependencies..."
(cd "$DIST_DIR/opera-cli" && npm ci --omit=dev --ignore-scripts 2>/dev/null)

# ── 5. Copy opera-devtools-mcp artifacts ─────────────────────────────────────
mkdir -p "$DIST_DIR/opera-devtools-mcp/build"
cp -R "$MCP_ROOT/build/src" "$DIST_DIR/opera-devtools-mcp/build/src"
cp "$MCP_ROOT/package.json" "$DIST_DIR/opera-devtools-mcp/"

# ── 6. Write VERSIONS manifest ───────────────────────────────────────────────
echo "opera-cli=${VERSION}" > "$DIST_DIR/VERSIONS"
echo "opera-devtools-mcp=${MCP_VERSION}" >> "$DIST_DIR/VERSIONS"

# ── 7. Copy SKILL.md ────────────────────────────────────────────────────────
cp "$CLI_ROOT/SKILL.md" "$DIST_DIR/SKILL.md"

# ── 8. Create bin/opera-cli wrapper ──────────────────────────────────────────
cat > "$DIST_DIR/bin/opera-cli" << 'WRAPPER'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0")")" && pwd)"
DIST_ROOT="$(dirname "$SCRIPT_DIR")"

MCP_BIN="$DIST_ROOT/opera-devtools-mcp/build/src/bin/opera-devtools-mcp.js"
export OPERA_CLI_MCP_BIN="${OPERA_CLI_MCP_BIN_OVERRIDE:-$MCP_BIN}"
export NODE_PATH="$DIST_ROOT/opera-cli/node_modules${NODE_PATH:+:$NODE_PATH}"

exec node "$DIST_ROOT/opera-cli/dist/bin/opera-cli.js" "$@"
WRAPPER
chmod +x "$DIST_DIR/bin/opera-cli"

# ── 9. Create install.sh ────────────────────────────────────────────────────
cat > "$DIST_DIR/install.sh" << 'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INSTALL_DIR="$HOME/.opera-cli"
MCP_BIN="$INSTALL_DIR/opera-devtools-mcp/build/src/bin/opera-devtools-mcp.js"

# 1. Stop running bridge so it doesn't keep using old binaries
PID_FILE="$INSTALL_DIR/bridge.pid"
if [ -f "$PID_FILE" ]; then
  BRIDGE_PID="$(node -p "JSON.parse(require('fs').readFileSync('$PID_FILE','utf-8')).pid" 2>/dev/null || true)"
  if [ -n "$BRIDGE_PID" ] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
    echo "Stopping running bridge (pid $BRIDGE_PID)..."
    kill "$BRIDGE_PID" 2>/dev/null || true
    for i in 1 2 3 4 5; do
      kill -0 "$BRIDGE_PID" 2>/dev/null || break
      sleep 0.5
    done
    kill -9 "$BRIDGE_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

# 2. Copy dist to ~/.opera-cli/
if [ -d "$INSTALL_DIR" ]; then
  echo "Removing previous installation at $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"
fi
echo "Installing to $INSTALL_DIR..."
cp -R "$SCRIPT_DIR" "$INSTALL_DIR"

# 3. Symlink into PATH
TARGET="${1:-$HOME/.local/bin}"
mkdir -p "$TARGET"
ln -sf "$INSTALL_DIR/bin/opera-cli" "$TARGET/opera-cli"
echo "Installed opera-cli -> $TARGET/opera-cli"
echo "  Make sure $TARGET is in your PATH."

# 4. Install SKILL.md for Claude Code
SKILL_SRC="$INSTALL_DIR/SKILL.md"
SKILL_DST="$HOME/.claude/skills/opera-cli"
if [ -f "$SKILL_SRC" ]; then
  mkdir -p "$SKILL_DST"
  cp "$SKILL_SRC" "$SKILL_DST/SKILL.md"
  echo "Installed Claude skill -> $SKILL_DST/SKILL.md"
fi

# 5. Update MCP configs to use installed opera-devtools-mcp
update_mcp_config() {
  local config_file="$1"
  local label="$2"
  [ -f "$config_file" ] || return 0

  node -e "(function(){
    const fs = require('fs');
    const p = '$config_file';
    const mcpBin = '$MCP_BIN';
    let cfg;
    try { cfg = JSON.parse(fs.readFileSync(p, 'utf-8')); } catch { return; }
    const servers = cfg.mcpServers || {};
    const key = Object.keys(servers).find(k => k.includes('opera-devtools'));
    if (!key) return;
    servers[key].command = 'node';
    servers[key].args = [mcpBin];
    cfg.mcpServers = servers;
    fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
    console.log('  Updated $label -> ' + p);
  })()" 2>/dev/null || true
}

update_mcp_config "$HOME/.cursor/mcp.json" "Cursor MCP config"
update_mcp_config "$HOME/Library/Application Support/Claude/claude_desktop_config.json" "Claude Desktop config"
update_mcp_config "$HOME/.claude.json" "Claude Code config"

# 6. Write version manifest
if [ -f "$INSTALL_DIR/VERSIONS" ]; then
  cp "$INSTALL_DIR/VERSIONS" "$INSTALL_DIR/VERSION"
fi

# 7. Print installed versions
echo ""
if [ -f "$INSTALL_DIR/VERSION" ]; then
  while IFS='=' read -r pkg ver; do
    echo "Installed ${pkg} v${ver}"
  done < "$INSTALL_DIR/VERSION"
fi

echo ""
echo "Done. You can now delete this directory:"
echo "  rm -rf $SCRIPT_DIR"
INSTALLER
chmod +x "$DIST_DIR/install.sh"

# ── 10. Create archive ──────────────────────────────────────────────────────
echo "  -> Creating archive..."
(cd "$STAGING" && tar czf "$CLI_ROOT/$DIST_NAME.tar.gz" "$DIST_NAME")

# ── 11. Cleanup ─────────────────────────────────────────────────────────────
rm -rf "$STAGING"

ARCHIVE_SIZE="$(du -h "$CLI_ROOT/$DIST_NAME.tar.gz" | cut -f1)"
echo ""
echo "==> Done: $DIST_NAME.tar.gz ($ARCHIVE_SIZE)"
echo ""
echo "To install:"
echo "  tar xzf $DIST_NAME.tar.gz"
echo "  cd $DIST_NAME"
echo "  ./install.sh"
