#!/usr/bin/env bash
#
# Apply (or re-apply) the branch protection rulesets defined in
# .github/rulesets/*.json against the GitHub repo.
#
# Idempotent: for each JSON file, look up an existing ruleset by name. If found,
# PUT to update it; if not, POST to create it.
#
# Requirements:
#   - gh CLI authenticated (`gh auth status`) with `repo` + `administration` scopes,
#     OR a GITHUB_TOKEN env var with the same scopes.
#   - jq
#
# Usage:
#   bash scripts/apply-rulesets.sh
#
# Optional env vars:
#   OWNER  (default: dj-pearson)
#   REPO   (default: wellvo)
#   DRY_RUN=1 to print intended actions without calling the API.

set -euo pipefail

OWNER="${OWNER:-dj-pearson}"
REPO="${REPO:-wellvo}"
RULESETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.github/rulesets"
DRY_RUN="${DRY_RUN:-0}"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

# Pick an API caller: prefer gh, fall back to curl with GITHUB_TOKEN.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  api() {
    local method="$1" path="$2"
    if [[ "${3:-}" == "--input" ]]; then
      gh api -X "$method" "$path" --input "$4"
    else
      gh api -X "$method" "$path"
    fi
  }
  echo "using: gh CLI"
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  api() {
    local method="$1" path="$2"
    local url="https://api.github.com/${path#/}"
    if [[ "${3:-}" == "--input" ]]; then
      curl -fsSL -X "$method" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: application/json" \
        --data-binary "@$4" \
        "$url"
    else
      curl -fsSL -X "$method" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url"
    fi
  }
  echo "using: curl + GITHUB_TOKEN"
else
  echo "error: need either 'gh' authenticated or GITHUB_TOKEN env var" >&2
  exit 1
fi

echo "==> Listing existing rulesets on $OWNER/$REPO"
existing="$(api GET "repos/$OWNER/$REPO/rulesets")"

declare -A name_to_id=()
while IFS=$'\t' read -r id name; do
  [[ -z "$name" ]] && continue
  name_to_id["$name"]="$id"
done < <(echo "$existing" | jq -r '.[] | [.id, .name] | @tsv')

echo "    found ${#name_to_id[@]} existing ruleset(s)"

shopt -s nullglob
for f in "$RULESETS_DIR"/*.json; do
  name="$(jq -r '.name' "$f")"
  if [[ -z "$name" || "$name" == "null" ]]; then
    echo "    skip $f (no .name field)" >&2
    continue
  fi

  if [[ -n "${name_to_id[$name]:-}" ]]; then
    id="${name_to_id[$name]}"
    echo "==> UPDATE  $name  (id=$id)  <- $f"
    if [[ "$DRY_RUN" == "1" ]]; then
      echo "    (dry-run) PUT repos/$OWNER/$REPO/rulesets/$id"
    else
      api PUT "repos/$OWNER/$REPO/rulesets/$id" --input "$f" >/dev/null
    fi
  else
    echo "==> CREATE  $name              <- $f"
    if [[ "$DRY_RUN" == "1" ]]; then
      echo "    (dry-run) POST repos/$OWNER/$REPO/rulesets"
    else
      api POST "repos/$OWNER/$REPO/rulesets" --input "$f" >/dev/null
    fi
  fi
done

echo
echo "==> Done. Verify in GitHub UI: https://github.com/$OWNER/$REPO/rules"

# ---------------------------------------------------------------------------
# Bootstrap: ensure 'develop' branch exists before the develop ruleset has
# anything to protect. Safe to run repeatedly.
# ---------------------------------------------------------------------------
echo
echo "==> Ensuring 'develop' branch exists"
if api GET "repos/$OWNER/$REPO/branches/develop" >/dev/null 2>&1; then
  echo "    develop already exists"
else
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    (dry-run) would create develop from main"
  else
    main_sha="$(api GET "repos/$OWNER/$REPO/git/ref/heads/main" | jq -r '.object.sha')"
    echo "    creating develop from main@$main_sha"
    tmp="$(mktemp)"
    jq -n --arg sha "$main_sha" '{ref: "refs/heads/develop", sha: $sha}' > "$tmp"
    api POST "repos/$OWNER/$REPO/git/refs" --input "$tmp" >/dev/null
    rm -f "$tmp"
    echo "    develop created"
  fi
fi
