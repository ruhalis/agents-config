#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Claude Code config from $REPO_DIR..."

# --- submodules ---
git -C "$REPO_DIR" submodule update --init --recursive

# --- statusline ---
if [ -d "$CLAUDE_DIR/statusline" ] && [ ! -L "$CLAUDE_DIR/statusline" ]; then
    echo "Backing up existing statusline to $CLAUDE_DIR/statusline.bak"
    mv "$CLAUDE_DIR/statusline" "$CLAUDE_DIR/statusline.bak"
fi
ln -sfn "$REPO_DIR/statusline" "$CLAUDE_DIR/statusline"
chmod +x "$REPO_DIR/statusline/statusline.sh"
echo "  statusline -> $CLAUDE_DIR/statusline"

# --- skills ---
mkdir -p "$CLAUDE_DIR/skills"
for skill_dir in "$REPO_DIR/skills"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$CLAUDE_DIR/skills/$skill_name"
    if [ -d "$target" ] && [ ! -L "$target" ]; then
        echo "Backing up existing skill $skill_name to ${target}.bak"
        mv "$target" "${target}.bak"
    fi
    ln -sfn "$skill_dir" "$target"
    echo "  skill: $skill_name -> $target"
done

# --- agents ---
mkdir -p "$CLAUDE_DIR/agents"
for agent_file in "$REPO_DIR/agents"/*.md; do
    [ -e "$agent_file" ] || continue
    agent_name=$(basename "$agent_file")
    target="$CLAUDE_DIR/agents/$agent_name"
    if [ -f "$target" ] && [ ! -L "$target" ]; then
        echo "Backing up existing agent $agent_name to ${target}.bak"
        mv "$target" "${target}.bak"
    fi
    ln -sfn "$agent_file" "$target"
    echo "  agent: $agent_name -> $target"
done

# --- global CLAUDE.md ---
claude_md_target="$CLAUDE_DIR/CLAUDE.md"
if [ -f "$claude_md_target" ] && [ ! -L "$claude_md_target" ]; then
    echo "Backing up existing CLAUDE.md to $CLAUDE_DIR/CLAUDE.md.bak"
    mv "$claude_md_target" "$CLAUDE_DIR/CLAUDE.md.bak"
fi
ln -sfn "$REPO_DIR/CLAUDE.md" "$claude_md_target"
echo "  CLAUDE.md -> $claude_md_target"

# --- settings.json ---
settings_target="$CLAUDE_DIR/settings.json"
if [ -f "$settings_target" ]; then
    echo "Backing up existing settings.json to $CLAUDE_DIR/settings.json.bak"
    cp "$settings_target" "$CLAUDE_DIR/settings.json.bak"
fi
cp "$REPO_DIR/settings.json" "$settings_target"
echo "  settings.json -> $settings_target"

# --- keybindings.json ---
kb_target="$CLAUDE_DIR/keybindings.json"
if [ -f "$kb_target" ]; then
    echo "Backing up existing keybindings.json to $CLAUDE_DIR/keybindings.json.bak"
    cp "$kb_target" "$CLAUDE_DIR/keybindings.json.bak"
fi
cp "$REPO_DIR/keybindings.json" "$kb_target"
echo "  keybindings.json -> $kb_target"

echo ""
echo "Done. Restart Claude Code for changes to take effect."
