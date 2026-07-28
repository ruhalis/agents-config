#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Backups must live outside ~/.claude/skills and ~/.claude/agents:
# Claude Code loads everything in those directories, .bak included.
BACKUP_DIR="$CLAUDE_DIR/backups/$(date +%Y%m%d-%H%M%S)"

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

# Sweep a directory clean: anything not symlinked into this repo is moved to
# the backup dir, so after install the directory mirrors the repo exactly.
sweep_dir() {
    local dir="$1" backup_subdir="$2"
    [ -d "$dir" ] || return 0
    local entry name
    for entry in "$dir"/* "$dir"/.[!.]*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        name=$(basename "$entry")
        if [ -L "$entry" ]; then
            case "$(readlink "$entry")" in
                "$REPO_DIR"/*) rm "$entry"; continue ;;  # stale repo link, will be recreated
            esac
        fi
        mkdir -p "$BACKUP_DIR/$backup_subdir"
        echo "Backing up existing $backup_subdir/$name to $BACKUP_DIR/$backup_subdir/$name"
        mv "$entry" "$BACKUP_DIR/$backup_subdir/$name"
    done
}

# --- skills ---
mkdir -p "$CLAUDE_DIR/skills"
sweep_dir "$CLAUDE_DIR/skills" "skills"
for skill_dir in "$REPO_DIR/skills"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$CLAUDE_DIR/skills/$skill_name"
    ln -sfn "${skill_dir%/}" "$target"
    echo "  skill: $skill_name -> $target"
done

# --- agents ---
mkdir -p "$CLAUDE_DIR/agents"
sweep_dir "$CLAUDE_DIR/agents" "agents"
for agent_file in "$REPO_DIR/agents"/*.md; do
    [ -e "$agent_file" ] || continue
    agent_name=$(basename "$agent_file")
    target="$CLAUDE_DIR/agents/$agent_name"
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
