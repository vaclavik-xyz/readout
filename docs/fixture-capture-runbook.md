# Fixture Capture Runbook

## 1) Capture raw samples
Store raw device outputs in plain text files:

- `captures/multimeter.txt` with one entry per line in `MODE<TAB>RESPONSE` (or `MODE|RESPONSE`) format
- `captures/usbc.txt` with one USB-C frame per line

Comments and empty lines are allowed (`# ...`).

## 2) Import captures into fixtures
```bash
swift run ReadOutFixtureTool import-multimeter \
  --input captures/multimeter.txt \
  --output candidate/multimeter_fixtures.json

swift run ReadOutFixtureTool import-usbc \
  --input captures/usbc.txt \
  --output candidate/usbc_frame_fixtures.json
```

## 3) Validate schema
```bash
swift run ReadOutFixtureTool validate-multimeter --input candidate/multimeter_fixtures.json
swift run ReadOutFixtureTool validate-usbc --input candidate/usbc_frame_fixtures.json
```

## 4) Check parser drift vs baseline
```bash
swift run ReadOutFixtureTool drift-report \
  --candidate-multimeter candidate/multimeter_fixtures.json \
  --candidate-usbc candidate/usbc_frame_fixtures.json \
  --baseline-multimeter Tests/ReadOutCoreTests/Fixtures/multimeter_fixtures.json \
  --baseline-usbc Tests/ReadOutCoreTests/Fixtures/usbc_frame_fixtures.json \
  --max-new-unknown-modes 0 \
  --max-new-overload-tokens 1 \
  --max-invalid-frame-ratio-delta 0.05 \
  --output candidate/parser_drift_report.json
```

Exit code `2` means drift threshold failure.

## 5) Final verification
```bash
swift test
```
