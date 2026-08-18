# Contributing

## Local development

When working on the skill itself, symlink it from your clone instead of installing it, so edits take effect without reinstalling:

```sh
./scripts/link.sh
```

It links `skills/nvim-feedback-resolve` into `~/.claude/skills` and `~/.codex/skills`. Re-running it is safe, but it refuses to replace an existing non-symlink directory, so remove any copy installed by `skills add` first.
