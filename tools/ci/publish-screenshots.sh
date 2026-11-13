#!/usr/bin/env bash
# Publishes this run's screenshots to the ci-screenshots branch, one folder per branch
# (decision D5; the Android repo does the same). Usage: publish-screenshots.sh <dir>
set -euo pipefail

src="${1:?screenshots directory}"
if [[ ! -d "$src" ]] || [[ -z "$(ls -A "$src" 2>/dev/null)" ]]; then
  echo "No screenshots to publish."
  exit 0
fi

branch="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-local}}"
folder="$(printf '%s' "$branch" | tr '/' '-' | tr -cd '[:alnum:]._-')"
work="$(mktemp -d)/shots"
sha="$(git rev-parse --short HEAD)"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git fetch --depth 1 origin ci-screenshots 2>/dev/null; then
  git worktree add --detach "$work" FETCH_HEAD
else
  git worktree add --detach "$work" HEAD
  git -C "$work" checkout --orphan ci-screenshots-new
  git -C "$work" rm -rfq .
fi

rm -rf "${work:?}/${folder}"
mkdir -p "$work/$folder"
cp "$src"/*.png "$work/$folder/"
{
  echo "# ${branch}"
  echo
  echo "Commit \`${sha}\`, run ${GITHUB_RUN_ID:-local}."
  echo
  for file in "$work/$folder"/*.png; do
    name="$(basename "$file")"
    echo "## ${name%.png}"
    echo
    echo "![${name}](${name})"
    echo
  done
} > "$work/$folder/README.md"

git -C "$work" add -A "$folder"
if git -C "$work" diff --cached --quiet; then
  echo "Screenshots unchanged."
  exit 0
fi
git -C "$work" commit -qm "Screenshots for ${branch} at ${sha}"

for attempt in 1 2 3; do
  if git -C "$work" push origin HEAD:refs/heads/ci-screenshots; then
    echo "Published to ci-screenshots/${folder}"
    exit 0
  fi
  git -C "$work" fetch --depth 1 origin ci-screenshots
  git -C "$work" rebase FETCH_HEAD
done
echo "::warning::Could not publish screenshots after 3 attempts."
