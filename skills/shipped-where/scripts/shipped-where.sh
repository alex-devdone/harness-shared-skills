#!/usr/bin/env bash
# Which release branches contain a commit/PR, and which merged PR first carried it onto each.
# Usage:  shipped-where.sh [<PR#> | <PR url> | <sha> | <branch>]      (default: HEAD)
#         BRANCHES="dev stage main" shipped-where.sh 4269
set -uo pipefail

ref="${1:-HEAD}"
read -r -a branches <<<"${BRANCHES:-dev stage main}"

pr=""
case "$ref" in
  *"/pull/"*) pr="${ref##*/pull/}"; pr="${pr%%[!0-9]*}" ;;
  ''|*[!0-9]*) : ;;
  *) pr="$ref" ;;
esac

if [ -n "$pr" ]; then
  IFS=$'\t' read -r sha base state title < <(
    gh pr view "$pr" --json mergeCommit,headRefOid,baseRefName,state,title \
      -q '[(.mergeCommit.oid // .headRefOid), .baseRefName, .state, .title] | @tsv'
  ) || { echo "PR #$pr not found in this repo" >&2; exit 1; }
  echo "PR #$pr  [$state -> $base]  $title"
  # a merged PR's merge commit arrives with the base-branch fetch; an open PR needs the pull ref
  git cat-file -e "${sha}^{commit}" 2>/dev/null || git fetch -q origin "pull/$pr/head"
else
  sha="$ref"
fi
sha=$(git rev-parse --verify "${sha}^{commit}") || exit 1

existing=()
for b in "${branches[@]}"; do git show-ref -q "refs/remotes/origin/$b" && existing+=("$b"); done
[ ${#existing[@]} -gt 0 ] || { echo "none of '${branches[*]}' exist on origin" >&2; exit 1; }
git fetch -q origin "${existing[@]}"

echo "commit $(git log -1 --format='%h %ad %s' --date=short "$sha")"
echo

# The merged PR that put $sha on branch $1: the earliest-merged PR with base=$1 whose merge commit
# already contains it. Deliberately NOT a first-parent walk — auto-merge bots merge these branches
# into each other in both directions, so a branch's first-parent chain wanders through its
# neighbours' history and dates the arrival wrong. GitHub's PR records are the reliable log of
# which promotion (dev->stage, stage->main) actually carried the change.
landed_via() {
  gh pr list --base "$1" --state merged --limit 100 \
     --json number,title,mergedAt,mergeCommit \
     -q '. | sort_by(.mergedAt) | .[] | [.mergeCommit.oid, .mergedAt, .number, .title] | @tsv' \
  | while IFS=$'\t' read -r oid merged num t; do
      git cat-file -e "${oid}^{commit}" 2>/dev/null || continue
      if git merge-base --is-ancestor "$sha" "$oid"; then
        echo "${merged}  via PR #${num}  ${t}"
        break
      fi
    done
}

for b in "${existing[@]}"; do
  if git merge-base --is-ancestor "$sha" "origin/$b"; then
    via=$(landed_via "$b")
    printf '%-6s YES  %s\n' "$b" "${via:-(no merged PR found — direct push? see git log origin/$b)}"
  else
    printf '%-6s NO   (tip: %s)\n' "$b" "$(git log -1 --format='%h %ad' --date=short "origin/$b")"
  fi
done
