#!/bin/sh
# Publish a tester build. Usage: tool/release.sh 1.2.3
set -eu

version=${1:-}
case $version in
  v*) version=${version#v} ;;
esac
case $version in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *)
    echo "Usage: tool/release.sh 1.2.3" >&2
    exit 1
    ;;
esac
# Reject extra suffixes such as 1.2.3-beta. Tags are v<major>.<minor>.<patch>.
case $version in
  *[!0-9.]*)
    echo "Version must be numbers and dots, like 1.2.3" >&2
    exit 1
    ;;
esac
old_ifs=$IFS
IFS=.
# shellcheck disable=SC2086
set -- $version
IFS=$old_ifs
if [ $# -ne 3 ]; then
  echo "Version must be major.minor.patch, like 1.2.3" >&2
  exit 1
fi

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" = "HEAD" ]; then
  echo "Checkout a branch before releasing." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit or stash changes before releasing." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
  echo "Tag v$version already exists." >&2
  exit 1
fi

current=$(awk '/^version: / { print $2; exit }' pubspec.yaml)
case $current in
  *+*) build=${current#*+} ;;
  *) build=0 ;;
esac
case $build in
  ''|*[!0-9]*)
    echo "pubspec.yaml build number is not an integer: $current" >&2
    exit 1
    ;;
esac
next=$((build + 1))

VERSION=$version BUILD=$next perl -i -pe 's/^version: .*/version: $ENV{VERSION}+$ENV{BUILD}/' pubspec.yaml
if ! grep -q "^version: $version+$next\$" pubspec.yaml; then
  echo "Could not update pubspec.yaml version." >&2
  exit 1
fi

git add pubspec.yaml
git commit -m "$(printf '%s\n' "Release $version for testers.")"
git tag "v$version"
git push origin "HEAD:refs/heads/$branch" "refs/tags/v$version"

echo "Pushed $branch and v$version."
echo "The release workflow will attach the macOS, Windows, and Linux builds to that tag."
