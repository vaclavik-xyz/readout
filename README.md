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

## Next Milestones
1. Add real serial transport implementation in `ReadOutIO`
2. Add fixture-driven compatibility tests from real device captures
3. Implement SwiftUI macOS app target with dual-device dashboard and graphs
4. Add settings + CSV/OBS output parity
