# Copilot Review — Copilot CLI Adapter

The canonical skill lives at the plugin root `SKILL.md`.
Load and follow that file. This adapter maps Copilot CLI tool names.

## Tool Mapping

| Skill Reference | Copilot CLI Tool |
|----------------|-----------------|
| `bash` / `gh` | `bash` |
| `read file` | `view` |
| `edit file` | `edit` |
| `write file` | `create` |
| `spawn subagent` | `task` with `agent_type: "general-purpose"` or `"explore"` |
| parallel subagents | multiple `task` calls |
| subagent output | `read_agent`, `list_agents` |
| file search | `grep`, `glob` |
| task tracking | `sql` with built-in `todos` table |
| web fetch | `web_fetch` |

## Copilot CLI-Specific Notes

- Use `bash` for all `gh` commands.
- State file: use `view`/`create` on `.copilot-review/<owner>-<repo>-<prNumber>.json`.
- No `EnterPlanMode` equivalent — stay in the main session.
