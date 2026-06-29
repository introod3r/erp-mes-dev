#!/usr/bin/env bash
set -euo pipefail

REMOTE_URL="${1:-https://github.com/introod3r/erp-mes-dev.git}"

if [[ ! -d .git ]]; then
  git init
fi

git branch -M main
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

echo "Git remote configured:"
git remote -v

echo "Next steps:"
echo "  git add ."
echo "  git commit -m 'Initial ERP MES application'"
echo "  git push -u origin main"
