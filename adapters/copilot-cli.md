# Copilot Review — GitHub Copilot CLI Adapter

The canonical skill lives at the plugin root `SKILL.md`.
Load and follow that file. This adapter maps tool references to
GitHub Copilot CLI.

## Tool Mapping

| Skill Reference | GitHub Copilot CLI Capability |
|----------------|-------------------------------|
| `bash` / `gh` | `shell` tool (`--allow-tool='shell(gh:*)'` and `--allow-tool='shell(git:*)'`) |
| `read file` | Built-in read-only file tools |
| `edit file` | `write` tools (`--allow-tool=write`) |
| `write file` | `write` tools (`--allow-tool=write`) |
| `spawn subagent` | `/fleet` and `/tasks` (parallel subagent execution and task tracking) |
| web fetch | Built-in web fetch + URL permissions (`--allow-url` / `--allow-all-urls`) |

## Copilot CLI-Specific Notes

- Use `copilot` (not `gh copilot`) in this environment.
- Start sessions in the repo root so default path permissions include the codebase.
- For autonomous runs, use:
  `copilot -p "<prompt>" --allow-tool=write --allow-tool='shell(gh:*)' --allow-tool='shell(git:*)'`.
- If your environment prompts for each command, approve only the needed tools
  instead of using `--allow-all`.
- Keep state files at `.copilot-review/<owner>-<repo>-<prNumber>.json`.
- If your Copilot CLI setup does not expose a persistent skills directory,
  keep this adapter in the repository and copy its mapping into
  `.github/copilot-instructions.md`.
