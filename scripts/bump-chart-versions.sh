#!/usr/bin/env bash
# Bumps the `version` of every Helm chart that has uncommitted changes in the working tree.
# Run by Renovate as a postUpgradeTask, so chart-releaser publishes the updated charts.
# A chart whose appVersion changed its major component gets a minor bump, everything else a patch bump.
set -euo pipefail

chart_dir_of() {
  local dir
  dir=$(dirname "$1")
  while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    if [ -f "$dir/Chart.yaml" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

field() {
  sed -nE "s/^$1:[[:space:]]*[\"']?([^\"'[:space:]]+).*/\1/p" | head -n 1
}

mapfile -t changed < <(git status --porcelain --untracked-files=no | sed -E 's/^.{3}//')

declare -A charts=()
for file in "${changed[@]}"; do
  if dir=$(chart_dir_of "$file"); then
    charts["$dir"]=1
  fi
done

for dir in "${!charts[@]}"; do
  chart="$dir/Chart.yaml"
  old_version=$(git show "HEAD:$chart" 2>/dev/null | field version || true)
  new_version=$(field version < "$chart")

  if [ -z "$old_version" ]; then
    echo "$dir: new chart, skipping"
    continue
  fi
  if [ "$old_version" != "$new_version" ]; then
    echo "$dir: version already changed ($old_version -> $new_version), skipping"
    continue
  fi

  if ! [[ "$old_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "$dir: version '$old_version' is not major.minor.patch, skipping" >&2
    continue
  fi
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"

  old_app=$(git show "HEAD:$chart" | field appVersion || true)
  new_app=$(field appVersion < "$chart")
  old_app_major="${old_app#v}"; old_app_major="${old_app_major%%.*}"
  new_app_major="${new_app#v}"; new_app_major="${new_app_major%%.*}"

  if [ -n "$old_app" ] && [ "$old_app_major" != "$new_app_major" ]; then
    next="$major.$((minor + 1)).0"
  else
    next="$major.$minor.$((patch + 1))"
  fi

  sed -Ei "0,/^version:.*/s//version: $next/" "$chart"
  echo "$dir: $old_version -> $next"
done
