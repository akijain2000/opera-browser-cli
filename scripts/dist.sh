#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_ROOT="$(dirname "$SCRIPT_DIR")"
MCP_ROOT="$(dirname "$CLI_ROOT")/opera-devtools-mcp"

VERSION="$(node -p "require('$CLI_ROOT/package.json').version")"
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

# ── 6. Copy SKILL.md ────────────────────────────────────────────────────────
cp "$CLI_ROOT/SKILL.md" "$DIST_DIR/SKILL.md"

# ── 7. Create bin/opera-cli wrapper ──────────────────────────────────────────
cat > "$DIST_DIR/bin/opera-cli" << 'WRAPPER'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0")")" && pwd)"
DIST_ROOT="$(dirname "$SCRIPT_DIR")"

export OPERA_CLI_MCP_BIN="${OPERA_CLI_MCP_BIN:-$DIST_ROOT/opera-devtools-mcp/build/src/bin/opera-devtools-mcp.js}"
export NODE_PATH="$DIST_ROOT/opera-cli/node_modules${NODE_PATH:+:$NODE_PATH}"

exec node "$DIST_ROOT/opera-cli/dist/bin/opera-cli.js" "$@"
WRAPPER
chmod +x "$DIST_DIR/bin/opera-cli"

# ── 8. Create install.sh ────────────────────────────────────────────────────
cat > "$DIST_DIR/install.sh" << 'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INSTALL_DIR="$HOME/.opera-cli"

# 1. Copy dist to ~/.opera-cli/
if [ -d "$INSTALL_DIR" ]; then
  echo "Removing previous installation at $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"
fi
echo "Installing to $INSTALL_DIR..."
cp -R "$SCRIPT_DIR" "$INSTALL_DIR"

# 2. Symlink into PATH
TARGET="${1:-$HOME/.local/bin}"
mkdir -p "$TARGET"
ln -sf "$INSTALL_DIR/bin/opera-cli" "$TARGET/opera-cli"
echo "Installed opera-cli -> $TARGET/opera-cli"
echo "  Make sure $TARGET is in your PATH."

# 3. Install SKILL.md for Claude Code
SKILL_SRC="$INSTALL_DIR/SKILL.md"
SKILL_DST="$HOME/.claude/skills/opera-cli"
if [ -f "$SKILL_SRC" ]; then
  mkdir -p "$SKILL_DST"
  cp "$SKILL_SRC" "$SKILL_DST/SKILL.md"
  echo "Installed Claude skill -> $SKILL_DST/SKILL.md"
fi

echo ""
echo "Done. You can now delete this directory:"
echo "  rm -rf $SCRIPT_DIR"
INSTALLER
chmod +x "$DIST_DIR/install.sh"

# ── 9. Create archive ───────────────────────────────────────────────────────
echo "  -> Creating archive..."
(cd "$STAGING" && tar czf "$CLI_ROOT/$DIST_NAME.tar.gz" "$DIST_NAME")

# ── 10. Cleanup ──────────────────────────────────────────────────────────────
rm -rf "$STAGING"

ARCHIVE_SIZE="$(du -h "$CLI_ROOT/$DIST_NAME.tar.gz" | cut -f1)"
echo ""
echo "==> Done: $DIST_NAME.tar.gz ($ARCHIVE_SIZE)"
echo ""
echo "To install:"
echo "  tar xzf $DIST_NAME.tar.gz"
echo "  cd $DIST_NAME"
echo "  ./install.sh"
