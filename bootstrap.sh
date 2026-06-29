#!/usr/bin/env bash
#
# bootstrap.sh — clone (or top up) every vista-cloud-dev repo on a new machine.
#
# Reads the repo list from repos.txt (next to this script) and clones any that
# are missing into VCD_DIR. Idempotent and non-destructive: existing repos are
# left untouched (no pulls, no resets). Use ./git-update-repos to fast-forward.
#
# Usage:
#   gh repo clone vista-cloud-dev/workspace && cd workspace && ./bootstrap.sh
#   VCD_DIR=/path/to/dir ./bootstrap.sh
#
set -euo pipefail

ORG="vista-cloud-dev"
REQUIRED_GO="go1.26.3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/repos.txt"
# Default: clone alongside this repo (workspace sits inside the org dir).
VCD_DIR="${VCD_DIR:-$(dirname "$SCRIPT_DIR")}"

# Repos worked on from a branch other than the default (name -> branch).
# Single source of truth, shared with scripts/git-update-all-repos.
# shellcheck source=scripts/repo-branches.sh
source "$SCRIPT_DIR/scripts/repo-branches.sh"

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  BOLD=''; RED=''; GREEN=''; YELLOW=''; RESET=''
fi
say()  { printf '%s==> %s%s\n' "$BOLD" "$*" "$RESET"; }
ok()   { printf '  %s%s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '  %s%s%s\n' "$YELLOW" "$*" "$RESET"; }
err()  { printf '  %s%s%s\n' "$RED" "$*" "$RESET"; }

# --- preflight ---------------------------------------------------------------
say "Preflight"
command -v git >/dev/null || { err "git not found"; exit 1; }
command -v gh  >/dev/null || { err "gh (GitHub CLI) not found — install it first"; exit 1; }
gh auth status >/dev/null 2>&1 && ok "gh authenticated" || { err "gh not authenticated — run: gh auth login"; exit 1; }
[[ -f "$MANIFEST" ]] || { err "manifest not found: $MANIFEST"; exit 1; }

mkdir -p "$VCD_DIR"; cd "$VCD_DIR"
say "Target directory: $VCD_DIR"

# --- clone repos (idempotent) ------------------------------------------------
say "Cloning $ORG repos (from repos.txt)"
while IFS= read -r line; do
  repo="${line%%#*}"; repo="$(echo "$repo" | tr -d '[:space:]')"
  [[ -z "$repo" ]] && continue
  if [[ -d "$repo/.git" ]]; then
    ok "$repo already present — skipping"
  elif [[ -e "$repo" ]]; then
    warn "$repo exists but is not a git repo — skipping (inspect manually)"
  else
    gh repo clone "$ORG/$repo" && ok "$repo cloned"
  fi
  # Branch override (active work not on the default branch).
  br="${BRANCH_OVERRIDES[$repo]:-}"
  if [[ -n "$br" && -d "$repo/.git" ]]; then
    if git -C "$repo" ls-remote --exit-code --heads origin "$br" >/dev/null 2>&1; then
      git -C "$repo" checkout "$br" >/dev/null 2>&1 && ok "$repo -> $br" || warn "$repo: could not switch to $br"
    else
      warn "$repo: branch $br not on origin — staying on default"
    fi
  fi
done < "$MANIFEST"

# --- toolchain checks (read-only; warn, never fail) --------------------------
say "Toolchain checks"
if command -v go >/dev/null; then
  GOV="$(go version | awk '{print $3}')"
  [[ "$GOV" == "$REQUIRED_GO" ]] && ok "Go $GOV (matches go.mod)" \
    || warn "Go is $GOV but go.mod pins $REQUIRED_GO — install $REQUIRED_GO/linux-amd64"
else
  warn "Go not installed — go.mod requires $REQUIRED_GO (linux/amd64)"
fi
if command -v docker >/dev/null; then ok "docker present"
elif command -v podman >/dev/null; then ok "podman present (confirm vista-iris compose targets it)"
else warn "no container runtime (docker/podman) found — needed for the IRIS image"; fi

# --- Go workspace (go.work) --------------------------------------------------
# A single go.work at the org root makes cross-module edits resolve against the
# local working tree instead of pinned tags — no tag/bump/repin churn in the dev
# loop (see docs: background/go-work-dev-loop-adr.md). It is local-only and
# uncommitted (the org root is not a repo); regenerate it here, idempotently.
say "Go workspace (go.work)"
if command -v go >/dev/null; then
  cd "$VCD_DIR"
  [[ -f go.work ]] || go work init
  added=0
  for d in */; do
    [[ -f "${d}go.mod" ]] || continue
    go work use "./${d%/}" && added=$((added+1))
  done
  ok "go.work uses $added local module(s)"
  warn "one-time, ONLINE: run 'go build ./...' in a couple of modules with the real"
  warn "GOPROXY to fill the combined-graph module cache; then airgapped builds work."
  warn "Under go.work do NOT set GOFLAGS=-mod=mod (workspace mode is readonly)."
else
  warn "Go not installed — skipping go.work (cross-repo dev will fall back to tags)"
fi

# --- next steps --------------------------------------------------------------
cat <<EOF

${BOLD}Done.${RESET} Repos are in ${VCD_DIR}. Manual next steps:

  ${BOLD}1. Build the IRIS image with the amd64 tag${RESET} (Dockerfile defaults to arm64):
       cd ${VCD_DIR}/vista-iris
       docker build --build-arg IRIS_TAG=latest-cd-linux-amd64 ...
       # or set IRIS_TAG in the Makefile/compose/env. Native amd64 — no emulation.

  ${BOLD}2. Build the Go tools:${RESET}
       (cd ${VCD_DIR}/go-cli-template && make)
       (cd ${VCD_DIR}/m-iris && make)

  ${BOLD}3. Validate m-iris <-> vista-iris:${RESET}
       bring up the vista-iris container + Atelier on :52773
       (namespace VISTA, _SYSTEM/SYS — unexpire the password first).

  ${BOLD}4. Keep machines in sync:${RESET} run ./git-update-repos from ${VCD_DIR}
       whenever you sit down. It ff-only pulls and skips anything dirty.
EOF
