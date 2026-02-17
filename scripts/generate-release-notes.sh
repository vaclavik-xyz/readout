#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TAG=""
OUTPUT_PATH=""
FROM_TAG=""

usage() {
  cat <<'USAGE'
Usage: scripts/generate-release-notes.sh --tag <version-tag> --output <path> [--from-tag <tag>]

Options:
  --tag <version-tag>      Target release tag (for header/title)
  --output <path>          File path for generated markdown
  --from-tag <tag>         Optional lower bound tag for changelog range
  -h, --help               Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --from-tag)
      FROM_TAG="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$TAG" || -z "$OUTPUT_PATH" ]]; then
  echo "Missing required arguments --tag and --output." >&2
  usage
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

if [[ -z "$FROM_TAG" ]]; then
  FROM_TAG="$(git tag --sort=-v:refname | grep -v "^${TAG}$" | head -n 1 || true)"
fi

if [[ -n "$FROM_TAG" ]]; then
  RANGE="${FROM_TAG}..HEAD"
  RANGE_LABEL="Changes since ${FROM_TAG}"
else
  RANGE="$(git rev-list --max-parents=0 HEAD | tail -n 1)..HEAD"
  RANGE_LABEL="Changes since initial commit"
fi

COMMITS="$(git log --no-merges --pretty=format:'- %s (%h)' "$RANGE" || true)"
if [[ -z "$COMMITS" ]]; then
  COMMITS="- No commits detected in selected range."
fi

cat > "$OUTPUT_PATH" <<EOF
# readOut ${TAG}

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Commit: $(git rev-parse --short HEAD)

## ${RANGE_LABEL}

${COMMITS}

## Validation

- macOS CI must be green on \`main\`
- Runbook: \`docs/v1-release-checklist.md\`
- Readiness script: \`scripts/v1-readiness-check.sh\`

## Notes

- Review diagnostics bundle export on real hardware before final \`v1.0.0\`
- Confirm 24h simulator soak + 4h hardware pass before final tag
EOF

echo "Release notes generated at: $OUTPUT_PATH"
