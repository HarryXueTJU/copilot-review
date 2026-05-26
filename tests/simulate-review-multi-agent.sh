#!/bin/bash
# Multi-agent smoke skeleton for copilot-review.
# This script standardizes baseline checks and prints agent-specific run hints.

set -euo pipefail

AGENT="${1:-}"
PR="${2:-}"

if [[ -z "$AGENT" || -z "$PR" ]]; then
  echo "Usage: $0 <agent> <pr-number>"
  echo "Agents: claude | copilot-vscode | copilot-cli | codex"
  exit 1
fi

OWNER=$(git remote get-url origin | sed 's|.*[:/]\([^/]*\)/\([^/.]*\).*|\1|')
REPO=$(git remote get-url origin | sed 's|.*[:/][^/]*/\([^/.]*\).*|\1|')
STATE_FILE=".copilot-review/${OWNER}-${REPO}-${PR}.json"

echo "=== Baseline checks ==="
gh auth status >/dev/null 2>&1 && echo "OK: gh auth" || { echo "FAIL: gh auth"; exit 1; }
git --version >/dev/null 2>&1 && echo "OK: git" || { echo "FAIL: git"; exit 1; }
jq --version >/dev/null 2>&1 && echo "OK: jq" || { echo "FAIL: jq"; exit 1; }

echo ""
echo "=== API checks ==="
REVIEWS=$(gh api "/repos/${OWNER}/${REPO}/pulls/${PR}/reviews?per_page=100")
echo "OK: reviews fetched ($(echo "$REVIEWS" | jq 'length'))"
COMMENTS=$(gh api "/repos/${OWNER}/${REPO}/pulls/${PR}/comments?per_page=100")
echo "OK: review comments fetched ($(echo "$COMMENTS" | jq 'length'))"
ISSUE_COMMENTS=$(gh api "/repos/${OWNER}/${REPO}/issues/${PR}/comments?per_page=100")
echo "OK: issue comments fetched ($(echo "$ISSUE_COMMENTS" | jq 'length'))"

echo ""
echo "=== State path check ==="
mkdir -p .copilot-review
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"smoke": true, "currentState": "COLLECT"}' > "$STATE_FILE"
  echo "OK: created $STATE_FILE"
else
  echo "OK: found $STATE_FILE"
fi

cat <<EOF

=== Agent run hint ($AGENT) ===
Use this as a manual baseline prompt in the target agent:

"Run /copilot-review status for PR #$PR, then collect comments, and stop before
any file edits. Report the state transition and comment counts."

Adapter reference:
- claude: adapters/claude.md
- copilot-vscode: adapters/copilot.md
- copilot-cli: adapters/copilot-cli.md
- codex: adapters/codex.md
EOF

case "$AGENT" in
  claude|copilot-vscode|copilot-cli|codex)
    echo "OK: agent value accepted"
    ;;
  *)
    echo "FAIL: unknown agent '$AGENT'"
    exit 1
    ;;
esac

echo ""
echo "=== Smoke skeleton complete ==="
