# readOut

Native macOS measurement app rewrite focused on speed, reliability, and clean UI.

## Stack
- Swift 6
- SwiftUI (planned app layer)
- Swift Charts (planned graph layer)
- Swift Package modules for isolation and testability

## Module Layout
- `ReadOutCore`: parsing, domain models, deterministic business rules
- `ReadOutIO`: serial/device session layer (next phase)
- `ReadOutPersistence`: config/logging/output sinks (next phase)

## Current Status
- Repository initialized
- Core parsing rules migrated from the existing Python implementation:
  - Multimeter mode parsing
  - Multimeter numeric/overload parsing behavior
  - USB-C 8-hex frame parsing behavior
  - Energy accumulation math
- Unit test baseline in place for parser compatibility
- Explicit parser contract documented in `docs/parser-compatibility.md`
- `ReadOutIO` now contains a tested async device session state machine:
  - connect / read loop
  - reconnect with backoff policy
  - explicit stop lifecycle
- Measurement pipelines added in `ReadOutIO`:
  - multimeter mode-cache + parser pipeline
  - USB-C frame pipeline with energy accumulation/reset
- `ReadOutPersistence` now includes:
  - JSON config store
  - legacy key migration from Python config format
  - value clamping during load for safer runtime behavior
  - CSV logger and OBS/text output writers
- `ReadOutIO` now includes real serial transport foundations:
  - POSIX serial port implementation (open/configure/read/write line)
  - streaming transport (USB-C style)
  - SCPI polling transport with fallback query path (multimeter style)
  - serial port discovery helper
- high-level device drivers are now available:
  - `MultimeterDeviceDriver` (mode refresh + SCPI polling + beeper verification)
  - `UsbCDeviceDriver` (frame decoding + energy accumulation/reset)
- fixture-driven parser compatibility tests are now in place
  - fixture schema documented in `docs/fixture-format.md`
- initial macOS SwiftUI app target exists:
  - executable target `ReadOutMacApp`
  - dashboard with live driver runtime + dual charts
  - app runtime split into focused services (`ReadOutRuntime`, config/alert/beep helpers)
  - settings sheet wired to persistent JSON config
  - settings now include file pickers + inline validation
  - serial port refresh + reconnect handling
  - live CSV + OBS/text output wiring
  - bounded async output queues (CSV/OBS) with backpressure telemetry
  - built-in simulator mode (`SIM_MULTIMETER`, `SIM_USBC`) for no-hardware testing
  - alarm rules (SHORT/OPEN/DCV high+low) with Mac beeper + meter beeper integration
- soak/fault harness CLI is now available via `ReadOutSoak`:
  - deterministic seeded fault injection (open fail, read fail, disconnect, slow-read windows)
  - presets: `smoke`, `30m`, `2h`, `24h`
  - machine-readable JSON summary artifact with reconnect/error/fault counters
  - example:
    - `swift run ReadOutSoak --preset smoke --seed 42 --output /tmp/readout-soak.json`

## Next Milestones
1. Add real device capture fixtures (multimeter + USB-C) to expand compatibility matrix
2. Add long-run soak tests for reconnect + serial fault scenarios
3. Add alarm visualization polish (per-state color accents and timeline markers)
4. Add targeted app-layer tests for `DashboardViewModel` state transitions
