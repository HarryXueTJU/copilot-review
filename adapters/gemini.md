# Copilot Review — Gemini CLI Adapter

The canonical skill lives at the plugin root `SKILL.md`.
Load and follow that file. This adapter maps Gemini CLI tool names.

## Tool Mapping

| Skill Reference | Gemini CLI Tool |
|----------------|----------------|
| `bash` / `gh` | `run_shell_command` |
| `read file` | `read_file` |
| `edit file` | `replace` |
| `write file` | `write_file` |
| `spawn subagent` | `@generalist` with inline prompt |
| parallel subagents | multiple `@generalist` calls in one message |
| file search | `grep_search`, `glob` |
| task tracking | `write_todos` |
| web search | `google_web_search` |
| web fetch | `web_fetch` |
| `Skill` tool | `activate_skill` |

## Gemini-Specific Notes

- Use `run_shell_command` for all `gh` commands.
- State file at `.copilot-review/<owner>-<repo>-<prNumber>.json`.
- Gemini CLI supports `enter_plan_mode` / `exit_plan_mode` for read-only research.
