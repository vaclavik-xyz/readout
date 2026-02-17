# Fixture Format

Fixture tests are used to preserve parser behavior while the app evolves.

## Multimeter Fixtures
Path: `Tests/ReadOutCoreTests/Fixtures/multimeter_fixtures.json`

Schema:
- `response` (string): raw line returned by device
- `mode` (string): mode string used by parser
- `expected`:
  - `mode` (string): normalized mode enum string
  - `value` (number|null)
  - `unit` (string)
  - `isOverload` (bool)
  - `isOpen` (bool)

## USB-C Frame Fixtures
Path: `Tests/ReadOutCoreTests/Fixtures/usbc_frame_fixtures.json`

Schema:
- `frame` (string): raw 8-char frame candidate
- `valid` (bool): expected frame validity
- `expectedVoltage` (number|null)
- `expectedCurrent` (number|null)

## Workflow
1. Capture real serial samples from devices.
2. Convert captures to fixture JSON with `ReadOutFixtureTool`:
   - `swift run ReadOutFixtureTool import-multimeter --input captures/multimeter.txt --output candidate/multimeter_fixtures.json`
   - `swift run ReadOutFixtureTool import-usbc --input captures/usbc.txt --output candidate/usbc_frame_fixtures.json`
3. Validate candidate fixtures:
   - `swift run ReadOutFixtureTool validate-multimeter --input candidate/multimeter_fixtures.json`
   - `swift run ReadOutFixtureTool validate-usbc --input candidate/usbc_frame_fixtures.json`
4. Generate drift report against baseline fixtures:
   - `swift run ReadOutFixtureTool drift-report --candidate-multimeter candidate/multimeter_fixtures.json --candidate-usbc candidate/usbc_frame_fixtures.json --baseline-multimeter Tests/ReadOutCoreTests/Fixtures/multimeter_fixtures.json --baseline-usbc Tests/ReadOutCoreTests/Fixtures/usbc_frame_fixtures.json --output candidate/parser_drift_report.json`
5. Run `swift test`.
6. If behavior change is intentional, update fixture expectations in the same commit.
