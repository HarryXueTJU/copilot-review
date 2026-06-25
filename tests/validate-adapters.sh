#!/bin/bash
# Validate adapter packaging across all supported agents.
# Run from repo root before committing adapter changes.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "FAIL: $1" >&2; exit 1; }
ok()   { echo "OK: $1"; }

AGENTS="claude copilot copilot-cli codex"

# --- SKILL.md basics ---
grep -q '^name: copilot-review$' SKILL.md \
  || fail "SKILL.md must keep the copilot-review skill name"
ok "SKILL.md name"

grep -q '^description: Use when ' SKILL.md \
  || fail "SKILL.md description should be a trigger phrase"
ok "SKILL.md description format"

# --- No stale agent references ---
if grep -qi 'gemini' SKILL.md README.md adapters/*.md 2>/dev/null; then
  fail "found Gemini references — remove or move to .superpowers/"
fi
ok "no stale Gemini references"

# --- State file path consistency ---
for f in SKILL.md README.md adapters/*.md; do
  if grep -q '\.claude/copilot-review' "$f" 2>/dev/null; then
    fail "$f references .claude/copilot-review/ — use .copilot-review/"
  fi
done
ok ".copilot-review/ path used everywhere"

# --- smartExit counter nesting ---
grep -q 'smartExit.consecutiveNoAction\|smartExit.*consecutiveNoAction' SKILL.md \
  || fail "SKILL.md must reference nested smartExit.consecutiveNoAction counter"
ok "smartExit counter uses nested path"

# --- No unsupported gh JSON fields ---
if grep -q 'detailsUrl' SKILL.md 2>/dev/null; then
  fail "gh pr checks JSON field 'detailsUrl' is not supported; use 'link'"
fi
ok "no unsupported gh JSON fields"

# --- Copilot re-request must use reviewer assignment ---
grep -q 'gh pr edit {pr} --repo {owner}/{repo} --add-reviewer @copilot' SKILL.md \
  || fail "SKILL.md must request Copilot review via gh pr edit --add-reviewer @copilot"
grep -q 'gh pr edit <pr> --repo <owner>/<repo> --add-reviewer @copilot' README.md \
  || fail "README must document gh pr edit --add-reviewer @copilot for review requests"
grep -q 'gh pr edit {pr} --repo {owner}/{repo} --add-reviewer @copilot' references/github-api.md \
  || fail "references/github-api.md must use gh pr edit --add-reviewer @copilot"

if grep -q 'gh pr comment {pr} --repo {owner}/{repo} --body "@copilot review this PR"' SKILL.md references/github-api.md; then
  fail "Do not use @copilot PR comments as the review request mechanism"
fi
ok "Copilot re-request command uses reviewer assignment"

# --- Each adapter exists ---
for agent in $AGENTS; do
  [ -f "adapters/$agent.md" ] || fail "missing adapters/$agent.md"
done
ok "all adapter files present"

# --- README install section covers each agent ---
for agent in $AGENTS; do
  grep -q "$agent" README.md \
    || fail "README installation section missing $agent"
done
ok "README covers all agents"

# --- SKILL.md installation table covers each agent (by adapter or name) ---
grep -q 'adapters/claude.md\|adapters/copilot-cli.md\|adapters/codex.md\|adapters/copilot.md' SKILL.md \
  || fail "SKILL.md installation table missing adapter references"
ok "SKILL.md installation table references adapters"

# --- Codex: adapter must warn it is not standalone ---
grep -q 'Do not install this adapter' adapters/codex.md \
  || fail "Codex adapter must warn it is not standalone"
ok "Codex adapter warns about non-standalone install"

# --- Codex: README must symlink canonical SKILL.md, not the adapter ---
grep -q 'ln -sf "$(pwd)/SKILL.md" ~/.agents/skills/copilot-review/SKILL.md' README.md \
  || fail "README Codex install must symlink canonical SKILL.md"
ok "Codex install uses canonical SKILL.md"

if grep -q 'ln -sf.*adapters/codex.md.*copilot-review/SKILL.md' README.md; then
  fail "README must not install Codex adapter as SKILL.md"
fi
ok "Codex adapter not installed as SKILL.md"

# --- README platform support table ---
for agent in $AGENTS; do
  grep -qi "$agent" README.md \
    || fail "README Platform Support table missing $agent"
done
ok "README Platform Support table covers all agents"

# --- SKILL.md platform tool mapping includes each agent ---
grep -q '### Claude Code' SKILL.md || fail "SKILL.md missing Claude Code tool mapping"
grep -q '### GitHub Copilot (VS Code)' SKILL.md || fail "SKILL.md missing Copilot (VS Code) tool mapping"
grep -q '### GitHub Copilot CLI' SKILL.md || fail "SKILL.md missing Copilot CLI tool mapping"
grep -q '### Codex' SKILL.md || fail "SKILL.md missing Codex tool mapping"
ok "SKILL.md tool mapping sections present for all agents"

echo ""
echo "=== All adapter validations passed ==="
