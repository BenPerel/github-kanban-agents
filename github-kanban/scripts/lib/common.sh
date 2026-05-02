#!/usr/bin/env bash
# Shared utilities for github-kanban scripts.

# Locate .kanban-config.json, searching from the current git root.
# Honors CONFIG_PATH env var as an override.
find_config() {
  if [ -n "${CONFIG_PATH:-}" ]; then
    echo "$CONFIG_PATH"
    return
  fi
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ERROR: Not in a git repo" >&2; exit 1; }
  local config="$root/.kanban-config.json"
  if [ ! -f "$config" ]; then
    echo "ERROR: .kanban-config.json not found at $config" >&2
    echo "Run setup.sh first to generate it." >&2
    exit 1
  fi
  echo "$config"
}

# Read WIP limit for a stage from config, falling back to defaults.
# Usage: get_wip_limit <stage> <config_path>
get_wip_limit() {
  local stage="$1"
  local config="$2"
  local limit
  limit=$(jq -r --arg s "$stage" '.wip_limits[$s] // empty' "$config" 2>/dev/null)
  if [ -z "$limit" ]; then
    case "$stage" in
      backlog)      echo 20 ;;
      in-progress)  echo 3 ;;
      in-review)    echo 5 ;;
      *)            echo "" ;;
    esac
  else
    echo "$limit"
  fi
}
