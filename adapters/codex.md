---
name: copilot-review-codex-adapter
description: Use when adapting the copilot-review skill instructions to Codex tool names and sandbox behavior.
---

# Copilot Review — Codex Adapter

The canonical skill lives at the repository root `SKILL.md`.

Do not install this adapter as Codex's `SKILL.md`. Install the root `SKILL.md`
as `~/.agents/skills/copilot-review/SKILL.md`, then symlink this file as
`~/.agents/skills/copilot-review/adapters/codex.md`. This file only maps Codex
tool names and host behavior.

## Tool Mapping

| Skill Reference | Codex Tool |
|----------------|-----------|
| `bash` / `gh` | shell execution tool such as `exec_command` |
| `read file` | file read tools, or shell reads with `sed` / `rg` |
| `edit file` | patch editing tool such as `apply_patch` |
| `write state file` | patch editing tool; create `.copilot-review/` first if missing |
| parallel read-only work | `multi_tool_use.parallel` when available |
| spawn subagent | `spawn_agent` / `wait_agent` if multi-agent tools are available |
| task tracking | `update_plan` when available |
| skill loading | Codex loads the root `SKILL.md` from the skills directory |

## Codex-Specific Notes

- State file at `.copilot-review/<owner>-<repo>-<prNumber>.json`.
- Accept `/copilot-review <pr>`, `copilot-review <pr>`, and natural language
  requests such as "use copilot-review for PR <pr>" as equivalent invocation
  forms.
- If multi-agent tools are unavailable, evaluate Copilot comments sequentially
  and preserve the same state-machine transitions.
- If `gh`, `git`, or network commands are blocked by Codex sandboxing, save
  state and request permission instead of skipping the blocked step.
- Optional subagent dispatch requires multi-agent support. In Codex builds that
  expose this setting, add to `~/.codex/config.toml`:
  ```toml
  [agent]
  max_agents = 4
  ```
