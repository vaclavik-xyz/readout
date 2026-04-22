# Claude Instructions for readOut

## Purpose
Use this file as the default operating guide when contributing code with Claude in this repository.

## Project Snapshot
- Project: `readOut`
- Platform: macOS 14+
- Language/toolchain: Swift 6 (SwiftPM)
- Main app: `ReadOutMacApp` (SwiftUI + Charts)
- Domain: realtime measurement from multimeter (SCPI) + USB-C power meter (streaming frames)

## Repository Layout
- `/Users/filip/Desktop/projects/readOut/Sources/ReadOutCore`: parsers, measurement models, alert logic, fixture primitives
- `/Users/filip/Desktop/projects/readOut/Sources/ReadOutIO`: transports, drivers, device session orchestration, soak harness
- `/Users/filip/Desktop/projects/readOut/Sources/ReadOutPersistence`: config, validation, CSV/OBS outputs
- `/Users/filip/Desktop/projects/readOut/Sources/ReadOutMacApp`: UI, runtime orchestration, dashboard, settings, popout windows
- `/Users/filip/Desktop/projects/readOut/Tests`: test suites per target
- `/Users/filip/Desktop/projects/readOut/docs`: release checklist, parser contracts, fixture docs

## Standard Commands
Run from `/Users/filip/Desktop/projects/readOut`.

```bash
swift build
swift test
swift run ReadOutMacApp
swift run ReadOutSoak --preset smoke --seed 42 --output /tmp/readout-soak.json
swift run ReadOutFixtureTool validate-multimeter --input Tests/ReadOutCoreTests/Fixtures/multimeter_fixtures.json
swift run ReadOutFixtureTool validate-usbc --input Tests/ReadOutCoreTests/Fixtures/usbc_frame_fixtures.json
scripts/v1-readiness-check.sh --extended --seed 42
```

## Engineering Priorities
1. Keep runtime stable under sustained high-rate input.
2. Preserve UI responsiveness (avoid heavy per-sample main-thread work).
3. Keep operator UI clean; place advanced diagnostics/debug controls behind debug sections.
4. Maintain parser compatibility and fixture-driven regression safety.
5. Keep config changes backward compatible with safe defaults.

## UI/Performance Guardrails
- Do not couple acquisition/output paths to render frequency.
- Prefer coalesced/throttled UI refresh over per-event redraw.
- Reduce chart work in high-load mode (point budgets, overlays, annotations).
- Preserve operator-facing refresh visibility (actual UI Hz should remain visible).
- Runtime logs should stay hidden by default unless explicitly enabled/debug context requires them.

## Coding Expectations
- Make focused, minimal diffs; avoid unrelated refactors.
- Add or update tests for behavior changes.
- Use clear commit scopes (`feat:`, `fix:`, `perf:`, `test:`, `docs:`).
- Before finalizing changes, run at least `swift test`.
- If touching CI/release flow, verify related scripts/workflows still match docs.

## Issue Workflow
When a change maps to a GitHub issue:
- Reference the issue in commits/PR notes.
- Post concise progress updates with:
  - delivered items
  - validation run (`swift test`, soak/readiness if relevant)
  - remaining work/risks

## Safety
- Never commit secrets, tokens, or machine-specific private paths beyond existing local tooling conventions.
- Preserve existing user changes in the working tree; do not revert unrelated modifications.
