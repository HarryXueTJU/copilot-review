# Multi-Agent Compatibility Contract

2026-05-26

## Goal

Use one shared validation contract across all adapters so the state-machine
behavior remains consistent while tool mappings vary by platform.

## Covered Agents

- Claude Code
- GitHub Copilot (VS Code)
- GitHub Copilot CLI
- Codex

## Minimum Capability Contract

Every supported agent must pass all of the following:

1. Read/write state file at `.copilot-review/<owner>-<repo>-<pr>.json`.
2. Execute required `gh` and `git` commands.
3. Collect Copilot review comments and issue comments.
4. Perform one controlled IMPLEMENT step and persist metadata.
5. Resume from saved state.

## Standard Validation Scenarios

1. Environment gate
- Verify `gh auth status`, `git --version`, `jq --version`.

2. Collect gate
- Read `/pulls/{pr}/reviews`, `/pulls/{pr}/comments`, `/issues/{pr}/comments`.
- Confirm unhandled comment extraction.

3. Implement gate
- Apply one controlled change (or dry-run change), lint when available,
  and update state.

4. Resume gate
- Stop mid-loop, resume, verify state transition continuity.

5. Exit gate
- Simulate no-action rounds and verify smart-exit trigger.

## Compatibility Matrix

| Agent | Adapter | Status | Notes |
|------|---------|--------|-------|
| Claude Code | adapters/claude.md | supported | Canonical workflow origin. |
| GitHub Copilot (VS Code) | adapters/copilot.md | supported | Uses VS Code agent tool names. |
| GitHub Copilot CLI | adapters/copilot-cli.md | supported with limits | Requires explicit tool permissions in some runs. |
| Codex | adapters/codex.md | supported | Native shell/file mapping. |

## Status Labels

- `supported`: all scenarios pass.
- `supported with limits`: core loop passes with documented caveats.
- `unsupported`: one or more required scenarios fail.
