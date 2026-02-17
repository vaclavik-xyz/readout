# readOut v1 release checklist

This checklist is the release gate for `v1.0.0`.

## 1) Automated readiness checks

Run from repository root:

```bash
scripts/v1-readiness-check.sh --extended --seed 42
```

The run must complete with exit code `0` and produce:
- passing `swift build`
- passing `swift test`
- passing fixture validation (`validate-multimeter`, `validate-usbc`)
- passing parser drift budget (`drift-report`)
- passing soak smoke summary
- passing app startup smoke test

Artifacts are written under `.readout-release-checks/<timestamp>/`.

## 2) Stability validation

Minimum pre-release validation:
- Simulator soak: `ReadOutSoak --preset 24h` completed with `passed=true`
- Hardware session: at least 4 hours on target setup without crashes/deadlocks
- No unbounded memory growth in runtime logs or chart history

## 3) Output integrity checks

Verify with real run data:
- CSV outputs for multimeter and USB-C contain expected columns and timestamp monotonicity
- OBS/text outputs update on each sample window without stale values
- No sustained `dropped` warnings in output queue logs under normal IO conditions

## 4) Recovery and diagnostics checks

In app:
- Trigger `Restart Runtime` and confirm devices reconnect without app relaunch
- Export runtime logs and diagnostics bundle successfully
- Confirm diagnostics bundle contains manifest, sanitized config, connection timeline, health snapshots, runtime logs

## 5) UI/UX checks

- Chart range switching (`30s`, `2m`, `10m`, `Full`) stays smooth
- Alarm/reconnect markers are visible and hover selection details are readable
- Scroll and resizing behavior works on common window sizes

## 6) Release bookkeeping

- Update `README.md` status/roadmap section
- Close completed feature issues
- Tag release: `v1.0.0`
- Publish release notes with known limitations and validation summary
