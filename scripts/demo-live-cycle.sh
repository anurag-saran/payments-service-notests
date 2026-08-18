#!/usr/bin/env bash
# demo-live-cycle.sh — repeatable live pom.xml demo for payments-service-notests
# (REACHABILITY_ONLY — empty src/test/java). Watch upgrade-delta-live-pr-notests-…
#
#   ./scripts/demo-live-cycle.sh start    # branch + bump jackson → Lightwell + open PR
#   ./scripts/demo-live-cycle.sh finish   # close PR(s) without merge; ensure main is community
#   ./scripts/demo-live-cycle.sh status   # show jackson version on main + open demo PRs
#
# Baseline on main: community jackson 2.13.4.
# Demo PR: bumps to 2.13.4.rhlw-00001. Never merge — finish closes the PR so the
# next start can bump again.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

POM=pom.xml
COMMUNITY='2.13.4'
LIGHTWELL='2.13.4.rhlw-00001'
BRANCH_PREFIX='demo/live-jackson'
LABEL='demo-live-pom'

die() { echo "FATAL: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "'$1' required"; }

jackson_ver() {
  local f="${1:-$POM}"
  sed -n 's/.*<jackson.version>\([^<]*\)<\/jackson.version>.*/\1/p' "$f" | head -1
}

ensure_baseline() {
  local v
  v=$(jackson_ver "$POM")
  [ "$v" = "$COMMUNITY" ] || die \
    "$POM has jackson.version=$v (want $COMMUNITY on the branch you start from). Run: $0 finish"
}

cmd_status() {
  echo "jackson.version in $POM: $(jackson_ver "$POM")  (baseline=$COMMUNITY demo=$LIGHTWELL)"
  echo "branch: $(git rev-parse --abbrev-ref HEAD)  sha: $(git rev-parse --short HEAD)"
  if command -v gh >/dev/null; then
    echo "open demo PRs:"
    gh pr list --label "$LABEL" --state open 2>/dev/null || \
      gh pr list --search "head:$BRANCH_PREFIX" --state open 2>/dev/null || true
  fi
}

cmd_start() {
  need git
  need gh
  [ -f "$POM" ] || die "missing $POM"
  git rev-parse --is-inside-work-tree >/dev/null

  local base="${DEMO_BASE_BRANCH:-main}"
  echo "== sync $base =="
  git fetch origin "$base" 2>/dev/null || true
  git checkout "$base"
  git pull --ff-only origin "$base" 2>/dev/null || git pull --ff-only || true
  ensure_baseline

  if [ ! -f .tekton/pull-request-live.yaml ]; then
    echo "WARN: .tekton/pull-request-live.yaml missing — live pipeline will not fire."
    echo "      Ensure .upgrade-delta/ is present (see README)."
  fi

  local stamp branch
  stamp=$(date +%Y%m%d-%H%M)
  branch="${BRANCH_PREFIX}-${stamp}"
  echo "== create $branch =="
  git checkout -b "$branch"

  if grep -q "<jackson.version>${COMMUNITY}</jackson.version>" "$POM"; then
    sed -i.bak "s|<jackson.version>${COMMUNITY}</jackson.version>|<jackson.version>${LIGHTWELL}</jackson.version>|" "$POM"
    rm -f "${POM}.bak"
  else
    die "expected <jackson.version>${COMMUNITY}</jackson.version> in $POM"
  fi
  [ "$(jackson_ver "$POM")" = "$LIGHTWELL" ] || die "bump failed"

  git add "$POM"
  git commit -m "$(cat <<EOF
demo: adopt jackson-databind ${LIGHTWELL}

Live-pipeline demo trigger. Close without merging when done
(./scripts/demo-live-cycle.sh finish) so ${base} stays on community ${COMMUNITY}.
EOF
)"

  echo "== push + open PR =="
  git push -u origin HEAD

  local body
  body=$(cat <<EOF
## Live pom.xml demo (auto)

Bumps \`jackson.version\` \`${COMMUNITY}\` → \`${LIGHTWELL}\` in \`pom.xml\` so
\`upgrade-delta-live\` can grade a real Lightwell adoption.

### After the PipelineRun
**Do not merge.** Reset for the next demo:

\`\`\`bash
./scripts/demo-live-cycle.sh finish
\`\`\`

That closes this PR without merging so \`${base}\` keeps community jackson.

See upgrade-delta [docs/DEMO-LIVE-POM.md](https://github.com/anurag-saran/upgrade-delta/blob/main/docs/DEMO-LIVE-POM.md).
EOF
)

  local url
  url=$(gh pr create \
    --base "$base" \
    --title "demo: jackson-databind ${COMMUNITY} to ${LIGHTWELL} (live pipeline)" \
    --body "$body" \
    --label "$LABEL" 2>&1) || {
      url=$(gh pr create \
        --base "$base" \
        --title "demo: jackson-databind ${COMMUNITY} to ${LIGHTWELL} (live pipeline)" \
        --body "$body")
      gh label create "$LABEL" --description "Live pom.xml demo PR — close without merge" --color "0E8A16" 2>/dev/null || true
      local n
      n=$(gh pr view --json number -q .number)
      gh pr edit "$n" --add-label "$LABEL" 2>/dev/null || true
    }
  echo "$url"
  echo
  echo "Watch: OpenShift PipelineRun upgrade-delta-live-pr-notests-..."
  echo "Scorecard: https://scorecard-notests-upgrade-delta-demo.apps.asaran.na-launch.com/out/reports/scorecard.html"
  echo "When done:  ./scripts/demo-live-cycle.sh finish"
}

cmd_finish() {
  need git
  need gh
  local base="${DEMO_BASE_BRANCH:-main}"

  echo "== close open demo PRs (no merge) =="
  local nums
  nums=$(gh pr list --label "$LABEL" --state open --json number -q '.[].number' 2>/dev/null || true)
  if [ -z "$nums" ]; then
    nums=$(gh pr list --search "head:${BRANCH_PREFIX}" --state open --json number -q '.[].number' 2>/dev/null || true)
  fi
  if [ -z "$nums" ]; then
    echo "(no open demo PRs found)"
  else
    for n in $nums; do
      echo "closing PR #$n"
      gh pr close "$n" --comment \
        "Demo complete — closed without merge so \`${base}\` stays on community jackson (${COMMUNITY}) for the next \`./scripts/demo-live-cycle.sh start\`." \
        || true
    done
  fi

  echo "== ensure $base baseline =="
  git fetch origin "$base" 2>/dev/null || true
  git checkout "$base"
  git pull --ff-only origin "$base" 2>/dev/null || git pull --ff-only || true

  local v
  v=$(jackson_ver "$POM")
  if [ "$v" != "$COMMUNITY" ]; then
    echo "WARN: $base has jackson.version=$v — restoring community ${COMMUNITY}"
    sed -i.bak "s|<jackson.version>${v}</jackson.version>|<jackson.version>${COMMUNITY}</jackson.version>|" "$POM"
    rm -f "${POM}.bak"
    git add "$POM"
    git commit -m "demo: restore community jackson ${COMMUNITY} on ${base} after live demo"
    git push origin "$base"
  else
    echo "OK: $POM already on community ${COMMUNITY}"
  fi

  git branch --list "${BRANCH_PREFIX}-*" | while read -r b; do
    b=$(echo "$b" | tr -d ' *')
    [ -n "$b" ] && git branch -D "$b" 2>/dev/null || true
  done

  cmd_status
  echo "Ready for next: ./scripts/demo-live-cycle.sh start"
}

usage() {
  echo "Usage: $0 {start|finish|status}"
  echo "  start   — bump jackson to Lightwell on a new branch + open PR"
  echo "  finish  — close demo PR(s) without merge; restore community jackson on main if needed"
  echo "  status  — show current jackson version and open demo PRs"
}

case "${1:-}" in
  start)  cmd_start ;;
  finish) cmd_finish ;;
  status) cmd_status ;;
  *) usage; exit 2 ;;
esac
