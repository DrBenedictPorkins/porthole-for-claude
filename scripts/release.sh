#!/usr/bin/env bash
# scripts/release.sh — Cut a versioned release of Porthole for Claude (Chrome)
#
# Convention: manifest.json always carries the NEXT version (the one in active
# development). Cutting a release means tagging the current version, then
# immediately bumping manifest to the next minor so dev continues forward.
#
# Usage:
#   ./scripts/release.sh              # release at current manifest version
#   ./scripts/release.sh 1.17.0      # override release version

set -euo pipefail
cd "$(dirname "$0")/.."

# ── Guards ─────────────────────────────────────────────────────────────────────

BRANCH=$(git branch --show-current)
if [[ "$BRANCH" != "develop" ]]; then
  echo "ERROR: must be on 'develop' branch (currently '$BRANCH')" >&2
  exit 1
fi

# ── Version ────────────────────────────────────────────────────────────────────

CURRENT=$(python3 -c "import json; print(json.load(open('manifest.json'))['version'])")

if [[ $# -ge 1 ]]; then
  RELEASE="$1"
  if [[ "$RELEASE" != "$CURRENT" ]]; then
    echo "Overriding manifest version: $CURRENT → $RELEASE"
    python3 - "$RELEASE" <<'PYEOF'
import json, sys
v = sys.argv[1]
with open('manifest.json') as f: m = json.load(f)
m['version'] = v
with open('manifest.json', 'w') as f:
    json.dump(m, f, indent=2); f.write('\n')
PYEOF
    git add manifest.json
  fi
else
  RELEASE="$CURRENT"
fi

# Reject if tag already exists
if git rev-parse "v$RELEASE" &>/dev/null 2>&1; then
  echo "ERROR: tag v$RELEASE already exists — nothing to do" >&2
  exit 1
fi

# Bump minor for next dev cycle (X.Y.Z → X.Y+1.0)
IFS='.' read -r V_MAJOR V_MINOR V_PATCH <<< "$RELEASE"
NEXT="${V_MAJOR}.$((V_MINOR + 1)).0"

echo ""
echo "  Release : v$RELEASE"
echo "  Next    : v$NEXT"
echo "  Flow    : develop  →  tag v$RELEASE  →  merge main  →  bump to v$NEXT on develop"
echo ""
read -rp "Continue? [y/N] " OK
[[ "$OK" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
echo ""

# ── Write build-info.js ────────────────────────────────────────────────────────

BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > background/build-info.js << JSEOF
// Written by scripts/release.sh at release time. Do not edit manually.
window.PORTHOLE_BUILD = {
  version: '$RELEASE',
  date: '$BUILD_DATE',
};
JSEOF
echo "→ Wrote build-info.js ($RELEASE / $BUILD_DATE)"
git add background/build-info.js

# ── Stage any tracked modifications ────────────────────────────────────────────

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "→ Staging tracked changes..."
  git add -u
fi

# ── Update CHANGELOG ───────────────────────────────────────────────────────────

DATE=$(date +%Y-%m-%d)
python3 - "$RELEASE" "$DATE" <<'PYEOF'
import sys
release, date = sys.argv[1], sys.argv[2]
content = open('CHANGELOG.md').read()
if '## [Unreleased]' in content:
    content = content.replace('## [Unreleased]', f'## [{release}] - {date}', 1)
    open('CHANGELOG.md', 'w').write(content)
    print(f"  → CHANGELOG: [Unreleased] → [{release}] - {date}")
else:
    print("  WARNING: [Unreleased] section not found in CHANGELOG.md — skipping", file=sys.stderr)
PYEOF

git add CHANGELOG.md

# ── Commit & tag on develop ────────────────────────────────────────────────────

echo "→ Committing release..."
git commit -m "Release v$RELEASE"
git tag "v$RELEASE"
echo "  Tagged: v$RELEASE"

# ── Merge to main ──────────────────────────────────────────────────────────────

echo "→ Merging to main..."
git checkout main
git merge --no-ff develop -m "Merge develop → main for v$RELEASE"
git push origin main
git push origin "v$RELEASE"
echo "  Pushed main + tag v$RELEASE"
git checkout develop

# ── Build Chrome zip ───────────────────────────────────────────────────────────

ZIP="porthole-claude-${RELEASE}.zip"
rm -f "$ZIP"

echo "→ Building $ZIP..."
zip -r "$ZIP" \
  background/ \
  content/ \
  icons/ \
  manifest.json \
  options/ \
  sidebar/ \
  viewer/ \
  CHANGELOG.md \
  LICENSE \
  PRIVACY.md \
  README.md \
  -x "*.DS_Store" \
  -x "icons/*.svg" \
  -x "*/node_modules/*" \
  -x "*/__pycache__/*" \
  > /dev/null

SIZE=$(du -h "$ZIP" | cut -f1)
echo "  Built: $ZIP ($SIZE)"

# ── Bump to next version on develop ───────────────────────────────────────────

echo "→ Bumping manifest to v$NEXT..."
python3 - "$NEXT" <<'PYEOF'
import json, sys
v = sys.argv[1]
with open('manifest.json') as f: m = json.load(f)
m['version'] = v
with open('manifest.json', 'w') as f:
    json.dump(m, f, indent=2); f.write('\n')
PYEOF

echo "→ Adding [Unreleased] to CHANGELOG..."
python3 - <<'PYEOF'
content = open('CHANGELOG.md').read()
import re
content = re.sub(r'(# Changelog\n)', r'\1\n## [Unreleased]\n', content, count=1)
open('CHANGELOG.md', 'w').write(content)
PYEOF

git add manifest.json CHANGELOG.md
git commit -m "Begin v$NEXT"
git push origin develop

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo "  v$RELEASE released and tagged"
echo "  main updated"
echo "  develop now tracking v$NEXT"
echo ""
echo "  Submit to Chrome Web Store:"
echo "  https://chrome.google.com/webstore/devconsole"
echo "  File: $ZIP"
