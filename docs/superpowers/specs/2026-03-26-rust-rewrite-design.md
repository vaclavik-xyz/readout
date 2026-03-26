# readOut Rust Rewrite — Design Spec

## Overview

Full rewrite of readOut from Swift/SwiftUI to Rust. Motivated by poor UI performance under sustained high-rate measurement input (charts lagging, numbers stuttering, high resource usage). The Swift version was unusable enough that the user stopped using it.

**Goals:**
- Performant real-time measurement dashboard
- Two frontends: desktop GUI (egui) + terminal TUI (ratatui)
- Cross-platform: macOS, Linux, Windows
- Feature parity with current Swift app
- Clean start (no backward compatibility with Swift config)

## Workspace Structure

```
readout/
├── Cargo.toml                   # workspace root
├── crates/
│   ├── readout-core/            # data types, parsers, alerts, chart pipeline
│   ├── readout-io/              # serial port, transports, device sessions, drivers
│   └── readout-persistence/     # config, CSV logger, OBS writer
├── readout-gui/                 # egui desktop application
└── readout-tui/                 # ratatui terminal dashboard
```

No separate CLI binaries. Soak testing and fixture validation are integrated into `cargo test` / `cargo test --features soak`.

## Crate Responsibilities

### readout-core

Pure logic, no I/O, no UI. The heart of the system.

- **`DeviceMeasurement`** — unified struct for all device readings:
  ```rust
  struct DeviceMeasurement {
      timestamp: Instant,
      device: DeviceId,
      primary_value: Option<f64>,      // None for overload readings ("OL")
      primary_unit: String,
      secondary_value: Option<f64>,   // USB-C: current alongside voltage
      secondary_unit: Option<String>,
      power_watts: Option<f64>,
      energy_mwh: Option<f64>,
      energy_mah: Option<f64>,
      mode: MeasurementMode,
      mode_string: String,            // raw SCPI mode text for display/logging
      is_overload: bool,
      is_open: bool,
      is_short: bool,
  }
  ```
  `MeasurementMode` enum: DcVoltage, AcVoltage, DcCurrent, AcCurrent, Resistance, Continuity, Diode, Capacitance, Frequency, Period, Temperature, Unknown.
- **`DeviceId`** — enum identifying device type:
  ```rust
  enum DeviceId { Multimeter, UsbC }
  ```
- **`ConnectionState`** — device connection status exposed to frontends:
  ```rust
  enum ConnectionState { Disconnected, Connecting, Connected, Reconnecting, Error(String) }
  ```
- **`AlarmState`** — alarm condition:
  ```rust
  enum AlarmState { None, HighAlarm, LowAlarm, Open, Short }
  ```
- **`MultimeterParser`** — parses SCPI text responses from multimeters into `DeviceMeasurement`.
- **`UsbCFrameParser`** — parses hex frames from USB-C power meters into `DeviceMeasurement`.
- **`EnergyAccumulator`** — integrates power over time to compute mWh and mAh. Exposes `reset()` triggered via `Command::ResetEnergy`.
- **`MeasurementAlerts`** — alarm state machine with hysteresis:
  - States: None, High, Low, Open, Short
  - High/low alarms apply only to DC voltage mode
  - Short detection applies only to continuity/resistance/diode modes
  - Hysteresis deadband: configurable (default 1% of threshold)
  - `enrich_measurement()` stamps fault flags onto measurements before they reach subscribers
  - **Alarm control**: acknowledge (silences beep for current state), timed silence (1m, 5m, 15m presets), auto-clear acknowledge when alarm state changes
- **`RuntimeEvent`** — the shared language of the entire system:
  ```rust
  enum RuntimeEvent {
      Measurement { device: DeviceId, value: DeviceMeasurement },
      AlarmTriggered { device: DeviceId, alarm: AlarmState },
      AlarmCleared { device: DeviceId },
      ConnectionChanged { device: DeviceId, state: ConnectionState },
      Error { device: DeviceId, message: String },
      Log { level: LogLevel, message: String },
  }
  ```
- **`Command`** — UI-to-backend commands:
  ```rust
  enum Command {
      Start,
      Stop,
      UpdateConfig(AppConfiguration),
      Rescan,                          // re-enumerate serial ports, update available list
      ResetEnergy { device: DeviceId },  // reset energy accumulator for specific device
      AcknowledgeAlarm { device: DeviceId },
      SilenceAlarm { duration: Duration },
  }
  ```
- **`ChartPipeline`** — ring buffer + time filter + min-max downsampling. Shared by both frontends.
  - Ring buffer per device, capacity 360,000 samples (1 hour at 50 Hz × 2 devices = 720k total). No allocations at runtime.
  - Time filter trims to selected range (2m, 5m, 10m, 30m, 1h).
  - Min-max downsample reduces to target point count while preserving peaks.

### readout-io

Device communication. Depends on readout-core.

- **`SerialPort`** — cross-platform serial I/O via `serialport` crate. Replaces hand-rolled POSIX termios code.
- **`DeviceSession`** — async state machine per device:
  ```
  Idle → Connecting → Connected → (error) → Reconnecting → WaitingRetry → Connecting → ...
  ```
  Exponential backoff: 0.5s → 1s → 2s → 4s → 5s (capped). Resets on successful connection. Retries indefinitely while enabled — only stops on explicit `Command::Stop` or task cancellation via `CancellationToken`.
- **`MultimeterDriver`** — SCPI polling transport (request-reply pattern): sends query command, waits for response, parses. Also sends beeper configuration on connect. Timeout-based error detection.
- **`UsbCDriver`** — streaming transport (push pattern): reads frames continuously from serial port, parses each. No query commands. Timeout = no data received for N seconds.
- **`SimulatedTransport`** — deterministic generator with seed. Supports fault injection (disconnects, slow reads, corrupt frames) for soak tests.
- **Event bus** — `tokio::sync::broadcast` channel carrying `RuntimeEvent`. Any number of subscribers.
- **Command channel** — `tokio::sync::mpsc` for `Command` from frontends to backend.

Each device runs as an independent Tokio task. No shared mutable state between devices.

- **Port discovery** — `serialport::available_ports()` enumerates system ports. Scoring heuristic ranks candidates per device type (vendor/product strings, baud rate probing). Exposed via `Command::Rescan` and used in first-run wizard.

### readout-persistence

Configuration and file outputs. Depends on readout-core.

- **`AppConfiguration`** — serde struct with all settings:
  - Device: multimeter/usbc enabled, ports, simulator mode
  - Alarms: thresholds, hysteresis, beep enabled
  - Outputs: CSV enabled/path, OBS enabled/path
  - UI: theme, chart range, layout preferences
- **`ConfigStore`** — reads/writes JSON config. Platform-specific paths via `dirs` crate:
  - macOS: `~/Library/Application Support/readout/config.json`
  - Linux: `~/.config/readout/config.json`
  - Windows: `%APPDATA%\readout\config.json`
- **`ConfigValidator`** — `validate(&AppConfiguration) -> Vec<Issue>`. Checks: missing ports, nonexistent paths, invalid thresholds.
- **`OutputWriteQueue`** — generic async write queue with configurable capacity and retry attempts. Handles per-write error recovery. Logs queue drops as runtime warnings via `RuntimeEvent::Log`. Used by both CSV and OBS outputs independently.
- **`CsvLogger`** — uses `OutputWriteQueue`. Appends measurement rows. If disk is slow, buffer fills and oldest samples drop (never blocks measurement pipeline).
- **`ObsOutputWriter`** — uses `OutputWriteQueue`. Overwrites text file with current value. Throttled to ~2 Hz.
- **Config value clamping** — `AppConfiguration` applies `clamp_values()` on deserialize: sample_rate_hz clamped to 1..50, beep_volume to 0.0..1.0, etc. Enum decoding is case-insensitive. Missing JSON keys fall back to defaults via `#[serde(default)]`.

Clean start — no migration from Swift config format.

## Architecture: Channel-Based Event Bus

```
[Serial/Simulated devices]
        ↓ async Tokio tasks
[readout-io: DeviceSession per device]
        ↓ RuntimeEvent
[broadcast channel] ──→ [egui subscriber] ──→ GPU render
                    ──→ [ratatui subscriber] ──→ terminal render
                    ──→ [CSV logger] ──→ file append
                    ──→ [OBS writer] ──→ file overwrite
        ↑ Command (mpsc channel)
[UI sends: Start/Stop/UpdateConfig/Rescan]
```

Backend runs in Tokio async runtime. Each frontend subscribes to the broadcast channel. Commands flow back via mpsc channel. No locks, no shared mutable state.

**Broadcast buffer and backpressure:**
- Broadcast channel capacity: 1024 events (covers ~20s at 50 Hz)
- If a subscriber lags (receives `RecvError::Lagged(n)`):
  - GUI/TUI: skip missed events, log warning, continue with latest — UI is best-effort
  - CSV logger: log the gap as a warning row in the CSV, continue — data loss is visible
  - OBS writer: skip silently — only latest value matters
- This differs from Swift where throttling happens at the emit side. Channel-side backpressure is simpler and lets each consumer decide its own policy.

**Refresh rates:**
- Backend emits events at device rate (configurable, default 10 Hz, max 50 Hz for real devices, unlimited for simulator/soak)
- GUI renders at 60 FPS, coalesces measurements (displays last value, chart gets all points)
- TUI renders at 10-30 FPS (terminal speed)
- CSV logger writes every measurement (no throttling)
- OBS writer throttled to ~2 Hz

**Graceful shutdown:**
1. Signal handler catches SIGINT/SIGTERM (Unix) / Ctrl+C (all platforms) via `tokio::signal`
2. Sends `Command::Stop` to backend
3. Backend cancels device session tasks via `CancellationToken`
4. Device sessions close serial ports
5. CSV logger flushes remaining buffer and closes file
6. OBS writer writes final value and closes file
7. Frontend exits render loop
8. Process exits cleanly

Order matters: outputs flush before ports close, ensuring no data loss for in-flight measurements.

## GUI: egui Desktop App

**Layout:**
```
┌─────────────────────────────────────────────┐
│  Header: status, preset, start/stop, pause  │
├──────────────────────┬──────────────────────┤
│   Multimeter Card    │    USB-C Card        │
│   12.4523 V DC       │    5.12V  2.41A      │
│   [alarm indicator]  │    12.36W  1847mWh   │
├──────────────────────┴──────────────────────┤
│   Chart (egui_plot)                         │
│   ~~~~/\~~~~~/\~~~/\~~~~                    │
│   [2m] [5m] [10m] [30m] [1h] range picker  │
├─────────────────────────────────────────────┤
│   Status strip: connection, refresh Hz      │
└─────────────────────────────────────────────┘
```

- **Popout windows**: egui multiple viewports — per-device floating window with enlarged value and chart.
- **Settings panel**: egui `Window` with form — ports, alarms, outputs, theme.
- **First-run wizard**: modal window on first launch or invalid config. Hardware/simulator picker, port discovery with scoring, validation feedback.
- **Themes**: dark/light via egui `Visuals`. Switchable at runtime.
- **Alarm sound**: `rodio` crate — cross-platform audio playback from embedded WAV. Audio initialization is optional — if it fails (e.g., headless Linux), log warning and continue silently.
- **Keyboard shortcuts**: Ctrl+1/2 popouts, Ctrl+P pause, Ctrl+L logs. Cmd on macOS.
- **Runtime health**: connection status badges, reconnect/error/parse error counts, output drop warnings. Status strip shows aggregate health at a glance.

## TUI: ratatui Terminal Dashboard

**Layout:**
```
┌─ readout ──────────────────────────────────┐
│ ● Multimeter: connected  ● USB-C: connected│
├──────────────────────┬─────────────────────┤
│  MULTIMETER          │  USB-C POWER METER  │
│  12.4523 V DC        │  5.12V   2.41A      │
│  ⚠ HIGH ALARM        │  12.36W  1847mWh    │
├──────────────────────┴─────────────────────┤
│  ▁▂▃▅▇▅▃▂▁▂▃▅▆▇▆▅▃▂▁▂▃▅▇▅▃▂▁  12.45V    │
│  [2m] 5m  10m  30m  1h                     │
├────────────────────────────────────────────┤
│ CSV: /tmp/log.csv  OBS: /tmp/obs.txt  10Hz │
│ [s]ettings [p]ause [q]uit [1]pop [2]pop    │
└────────────────────────────────────────────┘
```

- **Navigation**: `s` settings, `p` pause, `q` quit, `1`/`2` fullscreen per device (replaces popout windows), `Tab` switch panels, `←`/`→` chart range.
- **Chart**: `ratatui::widgets::Chart` with downsampled data from `ChartPipeline`.
- **Settings**: separate screen with editable fields.
- **Colors**: respects terminal palette. Dark default, light switchable.
- **Alarm sound**: same `rodio` as GUI. Optional — graceful fallback if audio unavailable.

## Key Dependencies

| Crate | Purpose | Replaces |
|-------|---------|----------|
| `tokio` | async runtime, channels, tasks | Swift async/await, actors |
| `serialport` | cross-platform serial port | hand-rolled POSIX termios |
| `serde` + `serde_json` | config/fixture serialization | Swift Codable |
| `eframe` + `egui` | GUI framework | SwiftUI |
| `egui_plot` | real-time charts | Swift Charts |
| `ratatui` + `crossterm` | TUI framework + terminal backend | (new) |
| `rodio` | cross-platform alarm audio | NSSound |
| `dirs` | platform config paths | hardcoded paths |
| `tracing` | structured logging | RuntimeLogStore |
| `insta` | snapshot tests | ReadOutFixtureTool |
| `clap` | CLI args for GUI/TUI binaries (--config, --simulator) | (new) |
| `tokio-util` | CancellationToken for graceful shutdown | Swift Task cancellation |

No heavy frameworks. All well-maintained, widely adopted.

## Testing Strategy

**Unit tests (`cargo test`):**
- Parser tests — fixture-driven with JSON input/expected output files
- Alert state machine — state transitions, hysteresis edge cases
- Energy accumulator — cumulative calculations, reset behavior
- Config validation — invalid/valid configurations
- Chart pipeline — downsampling accuracy, time filtering, ring buffer wraparound
- Device session — state machine transitions, reconnect logic (mock transport)

**Snapshot tests (`insta`):**
- Parser drift detection — new unknown mode = test fails with visible diff
- Replaces `ReadOutFixtureTool` functionality without separate binary

**Soak tests (`cargo test --features soak`):**
- Fault injection — simulated disconnects, slow reads, corrupt frames
- Deterministic seed — reproducible runs
- Metrics: target frames, transport errors, reconnects, latency p50/p95/p99
- Behind feature flag — not run during normal `cargo test` (they take minutes)

## CI (GitHub Actions)

**ci.yml:**
- Matrix: macOS + Linux + Windows
- `cargo build`
- `cargo test`
- `cargo clippy` (linter)
- `cargo fmt --check`

**nightly-soak.yml:**
- `cargo test --features soak` (smoke preset)
- JSON report as CI artifact
- Scheduled daily

Cross-platform CI from day one.

## Migration Notes

- **No backward compatibility** with Swift config. Clean start.
- **Fixture JSON files** can be reused as-is (same format, serde reads them).
- **Parser logic** is a direct port — same SCPI commands, same frame format.
- **Swift codebase remains** untouched — Rust project lives in a new repository or directory.
