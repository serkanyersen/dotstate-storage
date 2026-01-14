#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./gh-release-downloads.sh owner/repo
#   ./gh-release-downloads.sh owner/repo 30        # last 30 releases
#   ./gh-release-downloads.sh owner/repo 50 v0.1   # only tags starting with "v0.1"
#
# Env:
#   GITHUB_TOKEN (optional but recommended)

REPO="${1:-}"
LIMIT="${2:-50}"
TAG_PREFIX="${3:-}"

if [[ -z "${REPO}" ]]; then
  echo "Usage: $0 owner/repo [limit=50] [tag_prefix]"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq  (or apt-get install jq)"
  exit 1
fi

AUTH_HEADER=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

# Fetch releases (GitHub paginates; we’ll pull enough pages to cover LIMIT)
# Note: 100 max per page
PER_PAGE=100
PAGES=$(((LIMIT + PER_PAGE - 1) / PER_PAGE))

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

: >"$tmp"

for page in $(seq 1 "$PAGES"); do
  curl -fsSL \
    "${AUTH_HEADER[@]}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/releases?per_page=${PER_PAGE}&page=${page}" \
    >>"$tmp"
done

# The above concatenates JSON arrays; turn it into one array.
# jq -s reads multiple JSON docs and merges into an array of arrays => flatten.
jq -s 'flatten' "$tmp" |
  jq --arg tag_prefix "$TAG_PREFIX" --argjson limit "$LIMIT" '
  # optionally filter tags
  map(select($tag_prefix == "" or (.tag_name | startswith($tag_prefix))))
  | .[0:$limit]
  | {
      per_release: map({
        tag: .tag_name,
        name: (.name // ""),
        published_at: .published_at,
        prerelease: .prerelease,
        draft: .draft,
        asset_count: (.assets | length),
        total_downloads: ([.assets[].download_count] | add // 0)
      }),
      per_asset: (map(.assets[] | {
        tag: .release.tag_name,
        asset: .name,
        downloads: .download_count,
        size_mb: ((.size / 1048576) * 100 | floor / 100)
      }))
    }
  | .
' |
  jq -r '
  def line: ("-" * 92);

  "Repo metrics (GitHub Releases downloads)\n" +
  line + "\n" +
  "PER RELEASE\n" +
  line + "\n" +
  ( "published_at\t\ttag\t\ttotal\tassets\tdraft\tprerelease\tname" ) + "\n" +
  ( .per_release
    | sort_by(.published_at) | reverse
    | .[]
    | "\(.published_at)\t\(.tag)\t\t\(.total_downloads)\t\(.asset_count)\t\(.draft)\t\(.prerelease)\t\(.name)"
  ) + "\n\n" +
  line + "\n" +
  "TOP ASSETS (overall)\n" +
  line + "\n" +
  ( "downloads\tMB\tasset (tag)" ) + "\n" +
  ( .per_asset
    | group_by(.asset)
    | map({
        asset: .[0].asset,
        downloads: (map(.downloads) | add),
        size_mb: (map(.size_mb) | max),
        tags: (map(.tag) | unique | length)
      })
    | sort_by(.downloads) | reverse
    | .[0:20]
    | .[]
    | "\(.downloads)\t\(.size_mb)\t\(.asset)  (seen in \(.tags) tag(s))"
  )
'
