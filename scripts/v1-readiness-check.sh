#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXTENDED=0
SEED=42
BASELINE_REF="origin/main"
OUTPUT_DIR="$ROOT_DIR/.readout-release-checks/$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<'USAGE'
Usage: scripts/v1-readiness-check.sh [options]

Options:
  --extended               Include 30m soak run (default: off)
  --seed <uint64>          Seed for soak runs (default: 42)
  --baseline-ref <ref>     Git ref used for fixture drift baseline (default: origin/main)
  --output-dir <path>      Output directory for logs/reports
  -h, --help               Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extended)
      EXTENDED=1
      shift
      ;;
    --seed)
      SEED="$2"
      shift 2
      ;;
    --baseline-ref)
      BASELINE_REF="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
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

mkdir -p "$OUTPUT_DIR/logs" "$OUTPUT_DIR/baseline"

echo "Output directory: $OUTPUT_DIR"

action() {
  local name="$1"
  shift
  local log_file="$OUTPUT_DIR/logs/${name}.log"
  echo "==> $name"
  "$@" 2>&1 | tee "$log_file"
}

MULTIMETER_FIXTURES="Tests/ReadOutCoreTests/Fixtures/multimeter_fixtures.json"
USBC_FIXTURES="Tests/ReadOutCoreTests/Fixtures/usbc_frame_fixtures.json"
BASELINE_MM="$OUTPUT_DIR/baseline/multimeter_fixtures.json"
BASELINE_USBC="$OUTPUT_DIR/baseline/usbc_frame_fixtures.json"

if git show "${BASELINE_REF}:${MULTIMETER_FIXTURES}" > "$BASELINE_MM" 2>/dev/null; then
  echo "Baseline multimeter fixtures loaded from $BASELINE_REF"
else
  cp "$MULTIMETER_FIXTURES" "$BASELINE_MM"
  echo "Baseline multimeter fixtures fallback to current workspace"
fi

if git show "${BASELINE_REF}:${USBC_FIXTURES}" > "$BASELINE_USBC" 2>/dev/null; then
  echo "Baseline USB-C fixtures loaded from $BASELINE_REF"
else
  cp "$USBC_FIXTURES" "$BASELINE_USBC"
  echo "Baseline USB-C fixtures fallback to current workspace"
fi

action swift-build swift build
action swift-test swift test

action fixture-validate-multimeter \
  swift run ReadOutFixtureTool validate-multimeter \
  --input "$MULTIMETER_FIXTURES"

action fixture-validate-usbc \
  swift run ReadOutFixtureTool validate-usbc \
  --input "$USBC_FIXTURES"

action fixture-drift \
  swift run ReadOutFixtureTool drift-report \
  --candidate-multimeter "$MULTIMETER_FIXTURES" \
  --candidate-usbc "$USBC_FIXTURES" \
  --baseline-multimeter "$BASELINE_MM" \
  --baseline-usbc "$BASELINE_USBC" \
  --max-new-unknown-modes 0 \
  --max-new-overload-tokens 1 \
  --max-invalid-frame-ratio-delta 0.05 \
  --output "$OUTPUT_DIR/parser-drift-report.json"

action soak-smoke \
  swift run ReadOutSoak \
  --preset smoke \
  --seed "$SEED" \
  --target-frames 400 \
  --timeout-seconds 40 \
  --output "$OUTPUT_DIR/soak-smoke-summary.json"

if [[ "$EXTENDED" -eq 1 ]]; then
  action soak-30m \
    swift run ReadOutSoak \
    --preset 30m \
    --seed "$SEED" \
    --target-frames 6000 \
    --timeout-seconds 1200 \
    --output "$OUTPUT_DIR/soak-30m-summary.json"
fi

action app-startup-smoke \
  swift test --filter appStartupSmokeBootstrapsDashboardViewModel

cat > "$OUTPUT_DIR/summary.md" <<SUMMARY
# readOut v1 readiness run

- Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- Seed: $SEED
- Baseline ref: $BASELINE_REF
- Extended soak: $( [[ "$EXTENDED" -eq 1 ]] && echo yes || echo no )

## Generated artifacts
- parser-drift-report.json
- soak-smoke-summary.json
$( [[ "$EXTENDED" -eq 1 ]] && echo "- soak-30m-summary.json" )
- logs/*.log
SUMMARY

echo "✅ Readiness checks completed. Summary: $OUTPUT_DIR/summary.md"
