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
2. Append new fixture entries.
3. Run `swift test`.
4. If behavior change is intentional, update fixture expectations in the same commit.
