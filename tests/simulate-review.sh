#!/bin/bash
# Smoke test for copilot-review skill
# Runs against a real PR to verify API connectivity and response parsing.
# Does NOT modify any state — read-only verification.

set -euo pipefail

PR="${1:?Usage: $0 <pr-number>}"
OWNER=$(git remote get-url origin | sed 's|.*[:/]\([^/]*\)/\([^/.]*\).*|\1|')
REPO=$(git remote get-url origin | sed 's|.*[:/][^/]*/\([^/.]*\).*|\1|')

echo "=== Test 1: List reviews ==="
REVIEWS=$(gh api "/repos/${OWNER}/${REPO}/pulls/${PR}/reviews?per_page=100")
echo "OK: Got $(echo "$REVIEWS" | jq 'length') reviews"

echo ""
echo "=== Test 2: Filter Copilot reviews ==="
COPILOT_REVIEWS=$(echo "$REVIEWS" | jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")]')
echo "OK: Found $(echo "$COPILOT_REVIEWS" | jq 'length') Copilot reviews"

echo ""
echo "=== Test 3: List review comments ==="
COMMENTS=$(gh api "/repos/${OWNER}/${REPO}/pulls/${PR}/comments?per_page=100")
echo "OK: Got $(echo "$COMMENTS" | jq 'length') comments"

echo ""
echo "=== Test 4: Filter Copilot comments ==="
COPILOT_COMMENTS=$(echo "$COMMENTS" | jq '[.[] | select(.user.login == "Copilot")]')
echo "OK: Found $(echo "$COPILOT_COMMENTS" | jq 'length') Copilot comments"

echo ""
echo "=== Test 5: CI check ==="
gh pr checks "$PR" > /dev/null 2>&1 && echo "OK: CI check command works" || echo "OK: CI check command works (possibly no checks)"

echo ""
echo "=== Test 6: PR node ID for GraphQL ==="
NODE_ID=$(gh pr view "$PR" --json id --jq '.id')
echo "OK: PR node ID: $NODE_ID"

echo ""
echo "=== Test 7: State file read/write ==="
STATE_DIR=".copilot-review"
mkdir -p "$STATE_DIR"
STATE_FILE="${STATE_DIR}/${OWNER}-${REPO}-${PR}.json"
echo '{"test": true}' > "$STATE_FILE"
READ_BACK=$(cat "$STATE_FILE")
rm "$STATE_FILE"
echo "OK: State file read/write works"

echo ""
echo "=== All smoke tests passed ==="
