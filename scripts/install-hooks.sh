#!/usr/bin/env bash
set -euo pipefail

if [ ! -d .git ]; then
  echo "run git init first"
  exit 1
fi

cat > .git/hooks/pre-push <<'EOF'
#!/usr/bin/env bash
exec scripts/pre-push-guard.sh
EOF

chmod +x .git/hooks/pre-push
echo "installed pre-push hook"
