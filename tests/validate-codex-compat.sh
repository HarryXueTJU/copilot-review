#!/bin/bash
# Validate the Codex-facing packaging contract without touching GitHub.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

grep -q '^name: copilot-review$' SKILL.md \
  || fail "canonical SKILL.md must keep the copilot-review skill name"

grep -q '^description: Use when ' SKILL.md \
  || fail "canonical SKILL.md description should be a trigger, not workflow summary"

grep -q 'ln -sf "$(pwd)/SKILL.md" ~/.agents/skills/copilot-review/SKILL.md' README.md \
  || fail "README Codex install must symlink the canonical SKILL.md"

grep -q 'mkdir -p ~/.agents/skills/copilot-review/adapters' README.md \
  || fail "README Codex install must create the adapters directory"

grep -q 'ln -sf "$(pwd)/adapters/codex.md" ~/.agents/skills/copilot-review/adapters/codex.md' README.md \
  || fail "README Codex install must symlink the Codex adapter to adapters/codex.md"

if grep -q 'copilot-review/codex-adapter.md' README.md adapters/codex.md SKILL.md; then
  fail "Codex adapter install path must be adapters/codex.md, not codex-adapter.md"
fi

if grep -q 'ln -sf "$(pwd)/adapters/codex.md" .*copilot-review/SKILL.md' README.md; then
  fail "README must not install the Codex adapter as SKILL.md"
fi

grep -q 'Do not install this adapter as Codex' adapters/codex.md \
  || fail "Codex adapter must warn that it is not standalone"

grep -q 'exec_command' SKILL.md \
  || fail "Codex tool mapping should mention shell execution"

grep -q 'apply_patch' SKILL.md \
  || fail "Codex tool mapping should mention patch editing"

grep -q 'smartExit.consecutiveNoAction' SKILL.md \
  || fail "state instructions must use the nested smartExit counter"

if grep -q 'detailsUrl' SKILL.md; then
  fail "gh pr checks JSON field detailsUrl is not supported; use link"
fi

echo "OK: Codex compatibility contract validated"
