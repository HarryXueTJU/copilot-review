# Copilot Review — Codex Adapter

The canonical skill lives at the plugin root `SKILL.md`.
Load and follow that file. This adapter maps Codex tool names.

## Tool Mapping

| Skill Reference | Codex Tool |
|----------------|-----------|
| `bash` / `gh` | Native shell tools |
| `read file` | Native file tools |
| `edit file` | Native file tools |
| `write file` | Native file tools |
| `spawn subagent` | `spawn_agent` |
| parallel subagents | multiple `spawn_agent` calls |
| wait for subagent | `wait_agent` |
| close subagent | `close_agent` |
| task tracking | `update_plan` |
| `Skill` tool | Skills load natively — just follow instructions |

## Codex-Specific Notes

- State file at `.copilot-review/<owner>-<repo>-<prNumber>.json`.
- Subagent dispatch requires multi-agent support. Add to `~/.codex/config.toml`:
  ```toml
  [agent]
  max_agents = 4
  ```
