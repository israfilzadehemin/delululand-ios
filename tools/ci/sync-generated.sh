#!/usr/bin/env bash
# Keeps the generated Xcode project and the package lockfiles in git (decision D2).
# On a pull request, regenerated files are committed back to the branch and CI is started again on
# that commit (pushes made with GITHUB_TOKEN start no runs; a workflow_dispatch does). Anywhere else
# a difference fails the build: run `xcodegen generate` and commit.
set -euo pipefail

paths=(Delulutopia.xcodeproj Packages/DelulutopiaKit/Package.resolved)
changes="$(git status --porcelain -- "${paths[@]}")"

if [[ -z "$changes" ]]; then
  echo "Generated files are up to date."
  echo "regenerated=false" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

echo "$changes"

if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" && -n "${GITHUB_HEAD_REF:-}" ]]; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git add -A -- "${paths[@]}"
  git commit -m "chore: regenerate the Xcode project and lockfiles"
  git push origin "HEAD:refs/heads/${GITHUB_HEAD_REF}"
  gh workflow run ci.yml --ref "${GITHUB_HEAD_REF}"
  echo "::notice::Regenerated files were committed to ${GITHUB_HEAD_REF}; CI runs again on that commit."
  echo "regenerated=true" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

echo "::error::Delulutopia.xcodeproj or a Package.resolved is out of date. Run 'xcodegen generate', resolve packages and commit."
exit 1
