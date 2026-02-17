# CI and Branch Protection

## Required checks for `main`
Set the following required status check in GitHub branch protection for `main`:

- Workflow: `macOS CI`
- Job: `build-test-smoke`

This gate enforces:
- `swift build`
- `swift test`
- fixture schema validation + parser drift guard
- runtime smoke (`ReadOutSoak`)
- app startup smoke (`ReadOutMacApp`)

## Nightly soak
Use workflow `Nightly Soak` as scheduled stability monitoring.

- It runs deterministic seeded soak with fault injection.
- It publishes job summary with pass/fail metrics.
- It exports JSON + logs as downloadable artifacts (`nightly-soak-results`).
- It builds trend artifact (`nightly-soak-trend.json`) with delta vs previous successful nightly run.
- It fails when soak thresholds are exceeded.

Nightly failures should be triaged before release tagging.
