# readOut

Native macOS app for realtime measurement workflows:
- multimeter (SCPI-based)
- USB-C power meter (streaming hex frames)

Project focus: speed, reliability, parser compatibility, and production-ready tooling.

## Current State

`readOut` is already runnable and includes:
- SwiftUI macOS dashboard (`ReadOutMacApp`) with dual/single device views, charts, alerts, runtime logs, and settings.
- Real device runtime + simulator mode (`SIM_MULTIMETER`, `SIM_USBC`).
- Persistent JSON config with validation, migration from legacy keys, and dashboard preferences (theme/layout/log visibility/beep controls).
- CSV + OBS/text output sinks with bounded async write queues, retry, and backpressure telemetry.
- Runtime recovery action, UI render pause with coalesced chart refresh, persistent log rotation/export, and diagnostics-oriented runtime log panel.
- Deterministic soak/fault harness CLI (`ReadOutSoak`) with JSON summary output.
- Fixture import/validation/drift tooling CLI (`ReadOutFixtureTool`) for parser regression control.
- macOS GitHub Actions CI (build, test, fixture drift guard, smoke checks, nightly soak).

## Stack

- Swift tools `6.0`
- SwiftUI + Charts (macOS app)
- Swift Package Manager multi-target architecture
- macOS-only target platform (`macOS 14+`)

## Package Targets

- `ReadOutCore`: parsing, domain models, alert rules, fixture/drift tooling primitives
- `ReadOutIO`: serial transports, drivers, session state machine, soak/fault harness
- `ReadOutPersistence`: config store, validation, CSV/OBS writers
- `ReadOutMacApp`: desktop app UI + runtime orchestration
- `ReadOutSoak`: soak/fault CLI
- `ReadOutFixtureTool`: fixture import/validation/drift-report CLI

## Quick Start

### Run app
```bash
swift run ReadOutMacApp
```

### Run tests
```bash
swift test
```

### Run soak smoke preset
```bash
swift run ReadOutSoak --preset smoke --seed 42 --output /tmp/readout-soak.json
```

### Fixture tooling
```bash
swift run ReadOutFixtureTool validate-multimeter --input Tests/ReadOutCoreTests/Fixtures/multimeter_fixtures.json
swift run ReadOutFixtureTool validate-usbc --input Tests/ReadOutCoreTests/Fixtures/usbc_frame_fixtures.json
```

### Run v1 readiness check
```bash
scripts/v1-readiness-check.sh --extended --seed 42
```

## CI and Quality Gates

Workflows:
- `.github/workflows/ci-macos.yml`
- `.github/workflows/nightly-soak.yml`
- `.github/workflows/release-candidate.yml`

CI enforces:
- `swift build`
- `swift test`
- fixture schema validation + parser drift guard
- soak smoke run
- headless app startup smoke

Release-candidate workflow (`workflow_dispatch`) can:
- run full readiness checks (optional extended soak)
- generate draft release notes artifact
- create/push RC tag (example `v1.0.0-rc1`)
- create/update GitHub draft release for the RC tag

Branch protection setup:
- `docs/ci-branch-protection.md`

## Parser Compatibility and Fixtures

- Parser contract: `docs/parser-compatibility.md`
- Fixture format: `docs/fixture-format.md`
- Capture/import runbook: `docs/fixture-capture-runbook.md`
- Release gate checklist: `docs/v1-release-checklist.md`

## Roadmap (Open)

- `#1`: v1 stabilization and production-readiness epic (final release validation + tagging)
- `#12`: render pause + throttled dashboard pipeline for high-rate hardware streams
- `#13`: dashboard device visibility modes (Both / Multimeter / USB-C)
- `#14`: runtime logs hide/disable controls in dashboard
- `#15`: configurable Mac alert sound + dashboard beep master toggle
- `#16`: theme selector (System / Light / Dark)

Completed recently:
- `#9`: first-run setup wizard + serial auto-detection + connect preflight blocking
- `#5`: alarm timeline markers + hover details + snapshot coverage
- `#10`: high-density chart mode + reconnect overlays + pipeline performance instrumentation
- `#8`: diagnostics bundle export

## Repository

- GitHub: <https://github.com/vaclavik-xyz/readout>
