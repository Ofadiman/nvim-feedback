#!/usr/bin/env bash

set -euo pipefail

skill_name="nvim-feedback-resolve"
repo_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_dir="$repo_root/skills/$skill_name"

if [ ! -d "$source_dir" ]; then
  echo "error: $source_dir does not exist" >&2
  exit 1
fi

for skills_dir in "$HOME/.claude/skills" "$HOME/.codex/skills"; do
  link="$skills_dir/$skill_name"

  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "error: $link already exists and is not a symlink, remove it manually first" >&2
    exit 1
  fi

  mkdir -p "$skills_dir"
  ln -s -f -n "$source_dir" "$link"
  echo "linked $link -> $source_dir"
done
