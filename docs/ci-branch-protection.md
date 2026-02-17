# CI and Branch Protection

## Required checks for `main`
Set the following required status check in GitHub branch protection for `main`:

- Workflow: `macOS CI`
- Job: `build-test-smoke`

This gate enforces:
- `swift build`
- `swift test`
- runtime smoke (`ReadOutSoak`)
- app startup smoke (`ReadOutMacApp`)

## Nightly soak
Use workflow `Nightly Soak` as scheduled stability monitoring.

- It runs deterministic seeded soak with fault injection.
- It exports JSON + logs as downloadable artifacts.
- It fails when soak thresholds are exceeded.

Nightly failures should be triaged before release tagging.
