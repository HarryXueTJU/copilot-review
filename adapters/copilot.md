# Copilot Review — GitHub Copilot Adapter

The canonical skill lives at the plugin root `SKILL.md`.
Load and follow that file. This adapter maps tool references to
GitHub Copilot in VS Code (agent mode).

## Tool Mapping

| Skill Reference | GitHub Copilot Tool (VS Code) |
|----------------|--------------------------------|
| `bash` / `gh` | `run_in_terminal` |
| `read file` | `read_file` |
| `edit file` | `apply_patch` |
| `write file` | `create_file` |
| `spawn subagent` | `runSubagent` (`agentName: "Explore"` for read-only exploration) |
| parallel subagents | `multi_tool_use.parallel` with multiple `runSubagent` calls |
| file search | `grep_search`, `file_search`, `semantic_search` |
| task tracking | `manage_todo_list` |
| web fetch | `fetch_webpage` |

## Copilot-Specific Notes

- Use `run_in_terminal` for all `gh` commands.
- State file path is workspace-local:
	`.copilot-review/<owner>-<repo>-<prNumber>.json`.
- For state updates, read with `read_file` and write changes with `apply_patch`
	(or `create_file` if missing).
- Prefer `multi_tool_use.parallel` for independent read-only checks
	(review/comment fetches, search, and context reads).
- If your Copilot environment does not expose custom skill directories,
	keep this adapter as project documentation and copy its mapping into your
	user prompt/instructions file.
