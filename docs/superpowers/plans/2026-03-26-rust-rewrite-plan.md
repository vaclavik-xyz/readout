# readOutRS Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite readOut from Swift to Rust with egui GUI and ratatui TUI frontends, targeting macOS/Linux/Windows.

**Architecture:** Cargo workspace with 3 library crates (readout-core, readout-io, readout-persistence) and 2 binary crates (readout-gui, readout-tui). Channel-based event bus connects backend to frontends. Tokio async runtime for all I/O.

**Tech Stack:** Rust, tokio, serde, serialport, eframe/egui/egui_plot, ratatui/crossterm, rodio, dirs, tracing, insta, clap

**Spec:** `docs/superpowers/specs/2026-03-26-rust-rewrite-design.md`

**New repo:** `readOutRS` — created fresh, not inside the Swift readOut repo.

---

## Chunk 1: Workspace Scaffold + readout-core Types

### Task 1: Create workspace and crate scaffold

**Files:**
- Create: `Cargo.toml` (workspace root)
- Create: `crates/readout-core/Cargo.toml`
- Create: `crates/readout-core/src/lib.rs`
- Create: `crates/readout-io/Cargo.toml`
- Create: `crates/readout-io/src/lib.rs`
- Create: `crates/readout-persistence/Cargo.toml`
- Create: `crates/readout-persistence/src/lib.rs`
- Create: `readout-gui/Cargo.toml`
- Create: `readout-gui/src/main.rs`
- Create: `readout-tui/Cargo.toml`
- Create: `readout-tui/src/main.rs`
- Create: `.gitignore`

- [ ] **Step 1: Init repo and create workspace Cargo.toml**

```bash
mkdir -p ~/Dev/Projects/readOutRS
cd ~/Dev/Projects/readOutRS
git init
```

```toml
# Cargo.toml
[workspace]
members = [
    "crates/readout-core",
    "crates/readout-io",
    "crates/readout-persistence",
    "readout-gui",
    "readout-tui",
]
resolver = "2"

[workspace.package]
version = "0.1.0"
edition = "2024"
license = "MIT"

[workspace.dependencies]
readout-core = { path = "crates/readout-core" }
readout-io = { path = "crates/readout-io" }
readout-persistence = { path = "crates/readout-persistence" }
tokio = { version = "1", features = ["full"] }
tokio-util = { version = "0.7", features = ["rt"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
clap = { version = "4", features = ["derive"] }
thiserror = "2"
```

> **Note on edition 2024:** Native async fn in traits is available, so `async-trait` crate is not needed.

- [ ] **Step 2: Create readout-core crate**

```toml
# crates/readout-core/Cargo.toml
[package]
name = "readout-core"
version.workspace = true
edition.workspace = true

[dependencies]
serde = { workspace = true }
```

```rust
// crates/readout-core/src/lib.rs
// Modules added incrementally as tasks are completed.
```

- [ ] **Step 3: Create readout-io crate**

```toml
# crates/readout-io/Cargo.toml
[package]
name = "readout-io"
version.workspace = true
edition.workspace = true

[dependencies]
readout-core = { workspace = true }
tokio = { workspace = true }
tokio-util = { workspace = true }
tracing = { workspace = true }
thiserror = { workspace = true }
serialport = "4"

[dev-dependencies]
tokio = { workspace = true, features = ["test-util"] }
```

```rust
// crates/readout-io/src/lib.rs
// Modules added incrementally as tasks are completed.
```

- [ ] **Step 4: Create readout-persistence crate**

```toml
# crates/readout-persistence/Cargo.toml
[package]
name = "readout-persistence"
version.workspace = true
edition.workspace = true

[dependencies]
readout-core = { workspace = true }
tokio = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
tracing = { workspace = true }
dirs = "5"
```

```rust
// crates/readout-persistence/src/lib.rs
// Modules added incrementally as tasks are completed.
```

- [ ] **Step 5: Create GUI and TUI binary crate stubs**

```toml
# readout-gui/Cargo.toml
[package]
name = "readout-gui"
version.workspace = true
edition.workspace = true

[dependencies]
readout-core = { workspace = true }
readout-io = { workspace = true }
readout-persistence = { workspace = true }
tokio = { workspace = true }
eframe = "0.31"          # verify version at crates.io — must match egui_plot
egui_plot = "0.31"       # must be same minor version as eframe
tracing = { workspace = true }
tracing-subscriber = { workspace = true }
clap = { workspace = true }
rodio = { version = "0.20", optional = true }

[features]
default = ["audio"]
audio = ["rodio"]
```

```rust
// readout-gui/src/main.rs
fn main() {
    println!("readout-gui: not yet implemented");
}
```

```toml
# readout-tui/Cargo.toml
[package]
name = "readout-tui"
version.workspace = true
edition.workspace = true

[dependencies]
readout-core = { workspace = true }
readout-io = { workspace = true }
readout-persistence = { workspace = true }
tokio = { workspace = true }
ratatui = "0.29"         # verify crossterm compat — consider using ratatui's re-export
crossterm = "0.28"       # or remove and use ratatui::crossterm re-export
tracing = { workspace = true }
tracing-subscriber = { workspace = true }
clap = { workspace = true }
rodio = { version = "0.20", optional = true }

[features]
default = ["audio"]
audio = ["rodio"]
```

```rust
// readout-tui/src/main.rs
fn main() {
    println!("readout-tui: not yet implemented");
}
```

- [ ] **Step 6: Create .gitignore and verify build**

```gitignore
/target
.DS_Store
*.swp
```

Run: `cargo build`
Expected: Compiles with no errors. All 5 crates resolve.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: scaffold workspace with 5 crates"
```

---

### Task 2: Core types — DeviceId, MeasurementMode, DeviceMeasurement

**Files:**
- Create: `crates/readout-core/src/types.rs`
- Create: `crates/readout-core/src/measurement_mode.rs`
- Test: `crates/readout-core/tests/types_test.rs`

- [ ] **Step 1: Write tests for MeasurementMode and DeviceMeasurement**

```rust
// crates/readout-core/tests/types_test.rs
use readout_core::types::*;
use readout_core::measurement_mode::*;

#[test]
fn device_id_variants() {
    assert_ne!(DeviceId::Multimeter, DeviceId::UsbC);
}

#[test]
fn measurement_mode_parse_volt_dc() {
    assert_eq!(MeasurementModeParser::parse(Some("VOLT:DC")), MeasurementMode::DcVoltage);
}

#[test]
fn measurement_mode_parse_volt_ac() {
    assert_eq!(MeasurementModeParser::parse(Some("VOLT:AC")), MeasurementMode::AcVoltage);
}

#[test]
fn measurement_mode_parse_curr_dc() {
    assert_eq!(MeasurementModeParser::parse(Some("CURR:DC")), MeasurementMode::DcCurrent);
}

#[test]
fn measurement_mode_parse_curr_ac() {
    assert_eq!(MeasurementModeParser::parse(Some("CURR:AC")), MeasurementMode::AcCurrent);
}

#[test]
fn measurement_mode_parse_resistance() {
    assert_eq!(MeasurementModeParser::parse(Some("RES")), MeasurementMode::Resistance);
    assert_eq!(MeasurementModeParser::parse(Some("FRES")), MeasurementMode::Resistance);
    assert_eq!(MeasurementModeParser::parse(Some("OHM")), MeasurementMode::Resistance);
}

#[test]
fn measurement_mode_parse_continuity() {
    assert_eq!(MeasurementModeParser::parse(Some("CONT")), MeasurementMode::Continuity);
}

#[test]
fn measurement_mode_parse_diode() {
    assert_eq!(MeasurementModeParser::parse(Some("DIOD")), MeasurementMode::Diode);
}

#[test]
fn measurement_mode_parse_capacitance() {
    assert_eq!(MeasurementModeParser::parse(Some("CAP")), MeasurementMode::Capacitance);
}

#[test]
fn measurement_mode_parse_frequency() {
    assert_eq!(MeasurementModeParser::parse(Some("FREQ")), MeasurementMode::Frequency);
}

#[test]
fn measurement_mode_parse_period() {
    assert_eq!(MeasurementModeParser::parse(Some("PER")), MeasurementMode::Period);
}

#[test]
fn measurement_mode_parse_temperature() {
    assert_eq!(MeasurementModeParser::parse(Some("TEMP")), MeasurementMode::Temperature);
}

#[test]
fn measurement_mode_parse_unknown() {
    assert_eq!(MeasurementModeParser::parse(Some("GARBAGE")), MeasurementMode::Unknown);
    assert_eq!(MeasurementModeParser::parse(None), MeasurementMode::Unknown);
    assert_eq!(MeasurementModeParser::parse(Some("")), MeasurementMode::Unknown);
}

#[test]
fn measurement_mode_parse_case_insensitive() {
    assert_eq!(MeasurementModeParser::parse(Some("volt:dc")), MeasurementMode::DcVoltage);
    assert_eq!(MeasurementModeParser::parse(Some("  Curr:AC  ")), MeasurementMode::AcCurrent);
}

#[test]
fn device_measurement_default_flags() {
    let m = DeviceMeasurement {
        timestamp: std::time::Instant::now(),
        device: DeviceId::Multimeter,
        primary_value: Some(12.5),
        primary_unit: "V DC".into(),
        secondary_value: None,
        secondary_unit: None,
        power_watts: None,
        energy_mwh: None,
        energy_mah: None,
        mode: MeasurementMode::DcVoltage,
        mode_string: "VOLT:DC".into(),
        is_overload: false,
        is_open: false,
        is_short: false,
    };
    assert_eq!(m.primary_value, Some(12.5));
    assert!(!m.is_overload);
}

#[test]
fn device_measurement_overload_has_no_value() {
    let m = DeviceMeasurement {
        timestamp: std::time::Instant::now(),
        device: DeviceId::Multimeter,
        primary_value: None,
        primary_unit: "Ω".into(),
        secondary_value: None,
        secondary_unit: None,
        power_watts: None,
        energy_mwh: None,
        energy_mah: None,
        mode: MeasurementMode::Resistance,
        mode_string: "RES".into(),
        is_overload: true,
        is_open: true,
        is_short: false,
    };
    assert!(m.primary_value.is_none());
    assert!(m.is_overload);
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `cargo test -p readout-core`
Expected: Compilation errors (types not defined yet).

- [ ] **Step 3: Implement types.rs**

```rust
// crates/readout-core/src/types.rs
use std::time::Instant;

use crate::measurement_mode::MeasurementMode;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
pub enum DeviceId {
    Multimeter,
    UsbC,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Error(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum AlarmState {
    None,
    HighAlarm,
    LowAlarm,
    Open,
    Short,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum LogLevel {
    Debug,
    Info,
    Warning,
    Error,
}

#[derive(Debug, Clone)]
pub struct DeviceMeasurement {
    pub timestamp: Instant,
    pub device: DeviceId,
    pub primary_value: Option<f64>,
    pub primary_unit: String,
    pub secondary_value: Option<f64>,
    pub secondary_unit: Option<String>,
    pub power_watts: Option<f64>,
    pub energy_mwh: Option<f64>,
    pub energy_mah: Option<f64>,
    pub mode: MeasurementMode,
    pub mode_string: String,
    pub is_overload: bool,
    pub is_open: bool,
    pub is_short: bool,
}

#[derive(Debug, Clone)]
pub enum RuntimeEvent {
    Measurement {
        device: DeviceId,
        value: DeviceMeasurement,
    },
    AlarmTriggered {
        device: DeviceId,
        alarm: AlarmState,
    },
    AlarmCleared {
        device: DeviceId,
    },
    ConnectionChanged {
        device: DeviceId,
        state: ConnectionState,
    },
    Error {
        device: DeviceId,
        message: String,
    },
    Log {
        level: LogLevel,
        message: String,
    },
}

#[derive(Debug, Clone)]
pub enum Command {
    Start,
    Stop,
    UpdateConfig(Box<crate::AppConfiguration>), // defined in readout-persistence, forward-declared here
    Rescan,
    ResetEnergy { device: DeviceId },
    AcknowledgeAlarm { device: DeviceId },
    SilenceAlarm { duration: std::time::Duration },
}
// Note: AppConfiguration lives in readout-persistence. Command is defined in readout-core
// to avoid circular deps. Use a generic config type or move Command to readout-io.
// At implementation time, consider making Command generic or using a trait object.
```

- [ ] **Step 4: Implement measurement_mode.rs**

```rust
// crates/readout-core/src/measurement_mode.rs

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum MeasurementMode {
    DcVoltage,
    AcVoltage,
    DcCurrent,
    AcCurrent,
    Resistance,
    Continuity,
    Diode,
    Capacitance,
    Frequency,
    Period,
    Temperature,
    Unknown,
}

pub struct MeasurementModeParser;

impl MeasurementModeParser {
    pub fn parse(mode_string: Option<&str>) -> MeasurementMode {
        let raw = match mode_string {
            Some(s) => s.trim().to_uppercase(),
            None => return MeasurementMode::Unknown,
        };

        if raw.is_empty() {
            return MeasurementMode::Unknown;
        }

        if raw.contains("VOLT") {
            return if raw.contains("AC") {
                MeasurementMode::AcVoltage
            } else {
                MeasurementMode::DcVoltage
            };
        }
        if raw.contains("CURR") {
            return if raw.contains("AC") {
                MeasurementMode::AcCurrent
            } else {
                MeasurementMode::DcCurrent
            };
        }
        if raw.contains("CONT") {
            return MeasurementMode::Continuity;
        }
        if raw.contains("RES") || raw.contains("OHM") || raw.contains("FRES") {
            return MeasurementMode::Resistance;
        }
        if raw.contains("DIOD") {
            return MeasurementMode::Diode;
        }
        if raw.contains("CAP") {
            return MeasurementMode::Capacitance;
        }
        if raw.contains("FREQ") {
            return MeasurementMode::Frequency;
        }
        // TEMP before PER: "TEMPERATURE" contains "PER"
        if raw.contains("TEMP") {
            return MeasurementMode::Temperature;
        }
        if raw.contains("PER") {
            return MeasurementMode::Period;
        }

        MeasurementMode::Unknown
    }
}
```

- [ ] **Step 5: Update lib.rs exports**

```rust
// crates/readout-core/src/lib.rs
pub mod types;
pub mod measurement_mode;
```

- [ ] **Step 6: Run tests — verify they pass**

Run: `cargo test -p readout-core`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add crates/readout-core/
git commit -m "feat(core): add DeviceMeasurement, DeviceId, MeasurementMode types"
```

---

### Task 3: MultimeterParser

**Files:**
- Create: `crates/readout-core/src/multimeter_parser.rs`
- Create: `crates/readout-core/tests/fixtures/multimeter_fixtures.json`
- Create: `crates/readout-core/tests/multimeter_parser_test.rs`

- [ ] **Step 1: Copy fixture file from Swift project**

Copy `/Users/filip/Dev/Projects/readOut/Tests/ReadOutCoreTests/Fixtures/multimeter_fixtures.json` to `crates/readout-core/tests/fixtures/multimeter_fixtures.json`.

- [ ] **Step 2: Write fixture-driven tests**

```rust
// crates/readout-core/tests/multimeter_parser_test.rs
use readout_core::multimeter_parser::*;
use readout_core::measurement_mode::MeasurementMode;

#[derive(serde::Deserialize)]
struct FixtureExpected {
    mode: String,
    value: Option<f64>,
    unit: String,
    #[serde(rename = "isOverload")]
    is_overload: bool,
    #[serde(rename = "isOpen")]
    is_open: bool,
}

#[derive(serde::Deserialize)]
struct Fixture {
    response: String,
    mode: String,
    expected: FixtureExpected,
}

fn load_fixtures() -> Vec<Fixture> {
    let data = include_str!("fixtures/multimeter_fixtures.json");
    serde_json::from_str(data).expect("valid fixture JSON")
}

fn mode_name(mode: MeasurementMode) -> &'static str {
    match mode {
        MeasurementMode::DcVoltage => "dcVoltage",
        MeasurementMode::AcVoltage => "acVoltage",
        MeasurementMode::DcCurrent => "dcCurrent",
        MeasurementMode::AcCurrent => "acCurrent",
        MeasurementMode::Resistance => "resistance",
        MeasurementMode::Continuity => "continuity",
        MeasurementMode::Diode => "diode",
        MeasurementMode::Capacitance => "capacitance",
        MeasurementMode::Frequency => "frequency",
        MeasurementMode::Period => "period",
        MeasurementMode::Temperature => "temperature",
        MeasurementMode::Unknown => "unknown",
    }
}

#[test]
fn fixture_driven_parsing() {
    let fixtures = load_fixtures();
    for (i, f) in fixtures.iter().enumerate() {
        let result = MultimeterParser::parse(Some(&f.response), &f.mode);
        let result = result.unwrap_or_else(|| {
            panic!("fixture {i}: parse returned None for response={:?} mode={:?}", f.response, f.mode)
        });

        assert_eq!(
            mode_name(result.mode), f.expected.mode,
            "fixture {i}: mode mismatch"
        );
        assert_eq!(
            result.value, f.expected.value,
            "fixture {i}: value mismatch for response={:?}",
            f.response
        );
        assert_eq!(
            result.unit, f.expected.unit,
            "fixture {i}: unit mismatch"
        );
        assert_eq!(
            result.is_overload, f.expected.is_overload,
            "fixture {i}: isOverload mismatch"
        );
        assert_eq!(
            result.is_open, f.expected.is_open,
            "fixture {i}: isOpen mismatch"
        );
    }
}

#[test]
fn parse_none_returns_none() {
    assert!(MultimeterParser::parse(None, "VOLT:DC").is_none());
}

#[test]
fn parse_empty_returns_none() {
    assert!(MultimeterParser::parse(Some(""), "VOLT:DC").is_none());
}

#[test]
fn parse_whitespace_returns_none() {
    assert!(MultimeterParser::parse(Some("   "), "VOLT:DC").is_none());
}

#[test]
fn value_overload_resistance_threshold() {
    assert!(MultimeterParser::is_value_overload(1e7, MeasurementMode::Resistance));
    assert!(!MultimeterParser::is_value_overload(9.9e6, MeasurementMode::Resistance));
}

#[test]
fn value_overload_voltage_threshold() {
    assert!(MultimeterParser::is_value_overload(1e30, MeasurementMode::DcVoltage));
    assert!(!MultimeterParser::is_value_overload(999.0, MeasurementMode::DcVoltage));
}
```

- [ ] **Step 3: Run tests — verify they fail**

Run: `cargo test -p readout-core`
Expected: Compilation error — `MultimeterParser` not defined.

- [ ] **Step 4: Implement MultimeterParser**

```rust
// crates/readout-core/src/multimeter_parser.rs
use crate::measurement_mode::{MeasurementMode, MeasurementModeParser};
use std::collections::HashMap;
use std::sync::LazyLock;

#[derive(Debug, Clone, PartialEq)]
pub struct MultimeterParsedMeasurement {
    pub mode: MeasurementMode,
    pub mode_string: String,
    pub value: Option<f64>,
    pub unit: String,
    pub is_overload: bool,
    pub is_open: bool,
}

static MODE_UNITS: LazyLock<HashMap<&'static str, &'static str>> = LazyLock::new(|| {
    HashMap::from([
        ("VOLT", "V"),
        ("VOLT:DC", "V DC"),
        ("VOLT:AC", "V AC"),
        ("CURR", "A"),
        ("CURR:DC", "A DC"),
        ("CURR:AC", "A AC"),
        ("RES", "Ω"),
        ("FRES", "Ω"),
        ("CAP", "F"),
        ("FREQ", "Hz"),
        ("PER", "s"),
        ("CONT", "Ω"),
        ("DIOD", "V"),
        ("TEMP", "°C"),
    ])
});

const OVERLOAD_THRESHOLD: f64 = 1e7;

pub struct MultimeterParser;

impl MultimeterParser {
    pub fn parse(response: Option<&str>, mode_string: &str) -> Option<MultimeterParsedMeasurement> {
        let response = response?;
        let trimmed = response.trim();
        if trimmed.is_empty() {
            return None;
        }

        let normalized_mode = mode_string.trim().to_uppercase();
        let mode = MeasurementModeParser::parse(Some(&normalized_mode));
        let open_candidate = Self::is_open_candidate(mode);

        let upper = trimmed.to_uppercase();
        if upper.contains("OL") || upper.contains("OVER") {
            return Some(MultimeterParsedMeasurement {
                mode,
                mode_string: normalized_mode.clone(),
                value: None,
                unit: Self::resolved_unit(&normalized_mode, mode),
                is_overload: true,
                is_open: open_candidate,
            });
        }

        let first_segment = trimmed.split(',').next().unwrap_or(trimmed);
        let numeric = Self::extract_numeric_prefix(first_segment);

        let parsed_value = numeric.and_then(|s| s.replace(',', ".").parse::<f64>().ok());

        let Some(value) = parsed_value else {
            return Some(MultimeterParsedMeasurement {
                mode,
                mode_string: normalized_mode,
                value: None,
                unit: String::new(),
                is_overload: false,
                is_open: false,
            });
        };

        if Self::is_value_overload(value, mode) {
            return Some(MultimeterParsedMeasurement {
                mode,
                mode_string: normalized_mode.clone(),
                value: None,
                unit: Self::resolved_unit(&normalized_mode, mode),
                is_overload: true,
                is_open: open_candidate,
            });
        }

        Some(MultimeterParsedMeasurement {
            mode,
            mode_string: normalized_mode.clone(),
            value: Some(value),
            unit: Self::resolved_unit(&normalized_mode, mode),
            is_overload: false,
            is_open: false,
        })
    }

    pub fn is_value_overload(value: f64, mode: MeasurementMode) -> bool {
        match mode {
            MeasurementMode::Diode | MeasurementMode::Resistance | MeasurementMode::Continuity => {
                value.abs() >= OVERLOAD_THRESHOLD
            }
            _ => value.abs() >= 1e30,
        }
    }

    fn is_open_candidate(mode: MeasurementMode) -> bool {
        matches!(
            mode,
            MeasurementMode::Resistance | MeasurementMode::Continuity | MeasurementMode::Diode
        )
    }

    fn resolved_unit(mode_string: &str, mode: MeasurementMode) -> String {
        if let Some(&unit) = MODE_UNITS.get(mode_string) {
            return unit.to_string();
        }
        match mode {
            MeasurementMode::DcVoltage => "V DC",
            MeasurementMode::AcVoltage => "V AC",
            MeasurementMode::DcCurrent => "A DC",
            MeasurementMode::AcCurrent => "A AC",
            MeasurementMode::Resistance | MeasurementMode::Continuity => "Ω",
            MeasurementMode::Diode => "V",
            MeasurementMode::Capacitance => "F",
            MeasurementMode::Frequency => "Hz",
            MeasurementMode::Temperature => "°C",
            MeasurementMode::Period => "s",
            MeasurementMode::Unknown => "",
        }
        .to_string()
    }

    fn extract_numeric_prefix(text: &str) -> Option<&str> {
        let text = text.trim();
        if text.is_empty() {
            return None;
        }
        // Match: optional sign, digits, optional decimal, optional exponent
        let mut end = 0;
        let bytes = text.as_bytes();

        // Optional sign
        if end < bytes.len() && (bytes[end] == b'+' || bytes[end] == b'-') {
            end += 1;
        }
        // Digits
        let digit_start = end;
        while end < bytes.len() && bytes[end].is_ascii_digit() {
            end += 1;
        }
        if end == digit_start {
            return None; // No digits found
        }
        // Optional decimal
        if end < bytes.len() && bytes[end] == b'.' {
            end += 1;
            while end < bytes.len() && bytes[end].is_ascii_digit() {
                end += 1;
            }
        }
        // Optional exponent
        if end < bytes.len() && (bytes[end] == b'E' || bytes[end] == b'e') {
            end += 1;
            if end < bytes.len() && (bytes[end] == b'+' || bytes[end] == b'-') {
                end += 1;
            }
            while end < bytes.len() && bytes[end].is_ascii_digit() {
                end += 1;
            }
        }

        if end > 0 {
            Some(&text[..end])
        } else {
            None
        }
    }
}
```

- [ ] **Step 5: Add module to lib.rs**

```rust
// Update crates/readout-core/src/lib.rs — add:
pub mod multimeter_parser;
```

Also add `serde_json` to dev-dependencies in `crates/readout-core/Cargo.toml`:
```toml
[dev-dependencies]
serde_json = { workspace = true }
```

- [ ] **Step 6: Run tests — verify they pass**

Run: `cargo test -p readout-core`
Expected: All tests pass, including fixture-driven tests.

- [ ] **Step 7: Commit**

```bash
git add crates/readout-core/
git commit -m "feat(core): add MultimeterParser with fixture-driven tests"
```

---

### Task 4: UsbCFrameParser

**Files:**
- Create: `crates/readout-core/src/usbc_frame_parser.rs`
- Create: `crates/readout-core/tests/fixtures/usbc_frame_fixtures.json`
- Create: `crates/readout-core/tests/usbc_frame_parser_test.rs`

- [ ] **Step 1: Copy fixture file from Swift project**

Copy `/Users/filip/Dev/Projects/readOut/Tests/ReadOutCoreTests/Fixtures/usbc_frame_fixtures.json` to `crates/readout-core/tests/fixtures/usbc_frame_fixtures.json`.

- [ ] **Step 2: Write fixture-driven tests**

```rust
// crates/readout-core/tests/usbc_frame_parser_test.rs
use readout_core::usbc_frame_parser::*;

#[derive(serde::Deserialize)]
struct Fixture {
    frame: String,
    valid: bool,
    #[serde(rename = "expectedVoltage")]
    expected_voltage: Option<f64>,
    #[serde(rename = "expectedCurrent")]
    expected_current: Option<f64>,
}

fn load_fixtures() -> Vec<Fixture> {
    let data = include_str!("fixtures/usbc_frame_fixtures.json");
    serde_json::from_str(data).expect("valid fixture JSON")
}

#[test]
fn fixture_driven_parsing() {
    let fixtures = load_fixtures();
    for (i, f) in fixtures.iter().enumerate() {
        assert_eq!(
            UsbCFrameParser::is_valid_frame(&f.frame),
            f.valid,
            "fixture {i}: validity mismatch for frame={:?}",
            f.frame
        );

        let result = UsbCFrameParser::parse(&f.frame);
        if f.valid {
            let m = result.unwrap_or_else(|| panic!("fixture {i}: expected Some for valid frame"));
            let expected_v = f.expected_voltage.unwrap();
            let expected_c = f.expected_current.unwrap();
            assert!(
                (m.voltage - expected_v).abs() < 0.001,
                "fixture {i}: voltage mismatch: got {} expected {}",
                m.voltage, expected_v
            );
            assert!(
                (m.current - expected_c).abs() < 0.001,
                "fixture {i}: current mismatch: got {} expected {}",
                m.current, expected_c
            );
        } else {
            assert!(result.is_none(), "fixture {i}: expected None for invalid frame");
        }
    }
}

#[test]
fn negative_current_clamped_to_zero() {
    // Frame with negative shunt value
    let frame = "80000BB8"; // shunt = 0x8000 = 32768 -> signed = -32768
    let result = UsbCFrameParser::parse(frame).unwrap();
    assert_eq!(result.current, 0.0);
}

#[test]
fn whitespace_trimmed() {
    let result = UsbCFrameParser::parse("  03E80BB8  ");
    assert!(result.is_some());
}
```

- [ ] **Step 3: Run tests — verify they fail**

Run: `cargo test -p readout-core`
Expected: Compilation error — `UsbCFrameParser` not defined.

- [ ] **Step 4: Implement UsbCFrameParser**

```rust
// crates/readout-core/src/usbc_frame_parser.rs

pub const VOLTAGE_QUANTUM: f64 = 0.003125;
pub const CURRENT_QUANTUM: f64 = 0.0002;
pub const FRAME_LENGTH: usize = 8;

#[derive(Debug, Clone, PartialEq)]
pub struct UsbCFrameMeasurement {
    pub voltage: f64,
    pub current: f64,
}

pub struct UsbCFrameParser;

impl UsbCFrameParser {
    pub fn is_valid_frame(raw_frame: &str) -> bool {
        let frame = raw_frame.trim();
        frame.len() == FRAME_LENGTH && u32::from_str_radix(frame, 16).is_ok()
    }

    pub fn parse(raw_frame: &str) -> Option<UsbCFrameMeasurement> {
        let frame = raw_frame.trim();
        if !Self::is_valid_frame(frame) {
            return None;
        }

        let shunt_hex = &frame[..4];
        let bus_hex = &frame[4..];

        let shunt_raw = u16::from_str_radix(shunt_hex, 16).ok()?;
        let bus_raw = u16::from_str_radix(bus_hex, 16).ok()?;

        // Signed conversion for shunt
        let shunt_signed: i16 = shunt_raw as i16;

        let voltage = f64::from(bus_raw) * VOLTAGE_QUANTUM;
        let current = (f64::from(shunt_signed) * CURRENT_QUANTUM).max(0.0);

        Some(UsbCFrameMeasurement { voltage, current })
    }
}
```

- [ ] **Step 5: Add module to lib.rs**

```rust
// Update crates/readout-core/src/lib.rs — add:
pub mod usbc_frame_parser;
```

- [ ] **Step 6: Run tests — verify they pass**

Run: `cargo test -p readout-core`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add crates/readout-core/
git commit -m "feat(core): add UsbCFrameParser with fixture-driven tests"
```

---

### Task 5: EnergyAccumulator

**Files:**
- Create: `crates/readout-core/src/energy_accumulator.rs`
- Create: `crates/readout-core/tests/energy_accumulator_test.rs`

- [ ] **Step 1: Write tests**

```rust
// crates/readout-core/tests/energy_accumulator_test.rs
use readout_core::energy_accumulator::*;
use std::time::Duration;

#[test]
fn initial_state_is_zero() {
    let acc = EnergyAccumulator::new();
    assert_eq!(acc.energy_mwh(), 0.0);
    assert_eq!(acc.energy_mah(), 0.0);
}

#[test]
fn first_update_records_no_energy() {
    let mut acc = EnergyAccumulator::new();
    let snap = acc.update(5.0, 2.0, Duration::from_secs(0));
    assert_eq!(snap.energy_mwh, 0.0);
    assert_eq!(snap.energy_mah, 0.0);
    assert!((snap.power_watts - 10.0).abs() < 0.001);
}

#[test]
fn second_update_accumulates_energy() {
    let mut acc = EnergyAccumulator::new();
    acc.update(5.0, 2.0, Duration::from_secs(0));
    let snap = acc.update(5.0, 2.0, Duration::from_secs(3600)); // 1 hour later
    // 10W * 1h = 10Wh = 10000mWh
    assert!((snap.energy_mwh - 10000.0).abs() < 1.0);
    // 2A * 1h = 2Ah = 2000mAh
    assert!((snap.energy_mah - 2000.0).abs() < 1.0);
}

#[test]
fn reset_clears_accumulator() {
    let mut acc = EnergyAccumulator::new();
    acc.update(5.0, 2.0, Duration::from_secs(0));
    acc.update(5.0, 2.0, Duration::from_secs(3600));
    acc.reset();
    assert_eq!(acc.energy_mwh(), 0.0);
    assert_eq!(acc.energy_mah(), 0.0);
}

#[test]
fn negative_voltage_uses_abs_power() {
    let mut acc = EnergyAccumulator::new();
    acc.update(-5.0, 2.0, Duration::from_secs(0));
    let snap = acc.update(-5.0, 2.0, Duration::from_secs(3600));
    assert!((snap.power_watts - 10.0).abs() < 0.001);
    assert!(snap.energy_mwh > 0.0);
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `cargo test -p readout-core`
Expected: Compilation error.

- [ ] **Step 3: Implement EnergyAccumulator**

```rust
// crates/readout-core/src/energy_accumulator.rs
use std::time::Duration;

#[derive(Debug, Clone, PartialEq)]
pub struct EnergySnapshot {
    pub power_watts: f64,
    pub energy_mwh: f64,
    pub energy_mah: f64,
}

pub struct EnergyAccumulator {
    energy_mwh: f64,
    energy_mah: f64,
    last_timestamp: Option<Duration>,
}

impl EnergyAccumulator {
    pub fn new() -> Self {
        Self {
            energy_mwh: 0.0,
            energy_mah: 0.0,
            last_timestamp: None,
        }
    }

    pub fn energy_mwh(&self) -> f64 {
        self.energy_mwh
    }

    pub fn energy_mah(&self) -> f64 {
        self.energy_mah
    }

    pub fn reset(&mut self) {
        self.energy_mwh = 0.0;
        self.energy_mah = 0.0;
        self.last_timestamp = None;
    }

    pub fn update(&mut self, voltage: f64, current: f64, timestamp: Duration) -> EnergySnapshot {
        let power = (voltage * current).abs();

        if let Some(prev) = self.last_timestamp {
            let delta_hours = (timestamp - prev).as_secs_f64() / 3600.0;
            self.energy_mwh += power * 1000.0 * delta_hours;
            self.energy_mah += current * 1000.0 * delta_hours;
        }

        self.last_timestamp = Some(timestamp);

        EnergySnapshot {
            power_watts: power,
            energy_mwh: self.energy_mwh,
            energy_mah: self.energy_mah,
        }
    }
}

impl Default for EnergyAccumulator {
    fn default() -> Self {
        Self::new()
    }
}
```

- [ ] **Step 4: Add module to lib.rs, run tests**

Run: `cargo test -p readout-core`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add crates/readout-core/
git commit -m "feat(core): add EnergyAccumulator with reset and accumulation tests"
```

---

### Task 6: MeasurementAlerts

**Files:**
- Create: `crates/readout-core/src/alerts.rs`
- Create: `crates/readout-core/tests/alerts_test.rs`

- [ ] **Step 1: Write tests**

```rust
// crates/readout-core/tests/alerts_test.rs
use readout_core::alerts::*;
use readout_core::types::*;
use readout_core::measurement_mode::MeasurementMode;
use std::time::Instant;

fn make_measurement(mode: MeasurementMode, value: Option<f64>) -> DeviceMeasurement {
    DeviceMeasurement {
        timestamp: Instant::now(),
        device: DeviceId::Multimeter,
        primary_value: value,
        primary_unit: "V DC".into(),
        secondary_value: None,
        secondary_unit: None,
        power_watts: None,
        energy_mwh: None,
        energy_mah: None,
        mode,
        mode_string: "VOLT:DC".into(),
        is_overload: false,
        is_open: false,
        is_short: false,
    }
}

fn default_config() -> AlertConfiguration {
    AlertConfiguration {
        short_threshold: 2.0,
        dcv_high_alarm_enabled: true,
        dcv_high_alarm_value: 12.0,
        dcv_low_alarm_enabled: true,
        dcv_low_alarm_value: 3.0,
    }
}

#[test]
fn no_alarm_for_normal_dc_voltage() {
    let m = make_measurement(MeasurementMode::DcVoltage, Some(5.0));
    let state = AlertEvaluator::evaluate(&m, &default_config(), AlarmState::None);
    assert_eq!(state, AlarmState::None);
}

#[test]
fn high_alarm_triggered() {
    let m = make_measurement(MeasurementMode::DcVoltage, Some(13.0));
    let state = AlertEvaluator::evaluate(&m, &default_config(), AlarmState::None);
    assert_eq!(state, AlarmState::HighAlarm);
}

#[test]
fn low_alarm_triggered() {
    let m = make_measurement(MeasurementMode::DcVoltage, Some(2.0));
    let state = AlertEvaluator::evaluate(&m, &default_config(), AlarmState::None);
    assert_eq!(state, AlarmState::LowAlarm);
}

#[test]
fn high_alarm_hysteresis_holds() {
    let config = default_config();
    // Value just below threshold but within hysteresis band
    let clear_threshold = 12.0 * (1.0 - 0.01);
    let m = make_measurement(MeasurementMode::DcVoltage, Some(clear_threshold + 0.01));
    let state = AlertEvaluator::evaluate(&m, &config, AlarmState::HighAlarm);
    assert_eq!(state, AlarmState::HighAlarm); // Holds due to hysteresis
}

#[test]
fn high_alarm_clears_below_hysteresis() {
    let config = default_config();
    let clear_threshold = 12.0 * (1.0 - 0.01);
    let m = make_measurement(MeasurementMode::DcVoltage, Some(clear_threshold - 0.1));
    let state = AlertEvaluator::evaluate(&m, &config, AlarmState::HighAlarm);
    assert_eq!(state, AlarmState::None);
}

#[test]
fn open_on_overload() {
    let mut m = make_measurement(MeasurementMode::Resistance, None);
    m.is_overload = true;
    m.is_open = true;
    let state = AlertEvaluator::evaluate(&m, &default_config(), AlarmState::None);
    assert_eq!(state, AlarmState::Open);
}

#[test]
fn short_on_low_resistance() {
    let mut m = make_measurement(MeasurementMode::Continuity, Some(0.5));
    m.mode = MeasurementMode::Continuity;
    let state = AlertEvaluator::evaluate(&m, &default_config(), AlarmState::None);
    assert_eq!(state, AlarmState::Short);
}

#[test]
fn no_short_above_threshold() {
    let m = make_measurement(MeasurementMode::Continuity, Some(5.0));
    let state = AlertEvaluator::evaluate(&m, &default_config(), AlarmState::None);
    assert_eq!(state, AlarmState::None);
}

#[test]
fn no_alarm_for_non_dcv_mode() {
    let m = make_measurement(MeasurementMode::AcVoltage, Some(300.0));
    let state = AlertEvaluator::evaluate(&m, &default_config(), AlarmState::None);
    assert_eq!(state, AlarmState::None);
}

#[test]
fn enrich_stamps_short_flag() {
    let m = make_measurement(MeasurementMode::Continuity, Some(0.5));
    let config = default_config();
    let enriched = AlertEvaluator::enrich_measurement(m, &config);
    assert!(enriched.is_short);
}

#[test]
fn enrich_does_not_stamp_when_above_threshold() {
    let m = make_measurement(MeasurementMode::Continuity, Some(5.0));
    let config = default_config();
    let enriched = AlertEvaluator::enrich_measurement(m, &config);
    assert!(!enriched.is_short);
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `cargo test -p readout-core`
Expected: Compilation error.

- [ ] **Step 3: Implement alerts.rs**

```rust
// crates/readout-core/src/alerts.rs
use crate::measurement_mode::MeasurementMode;
use crate::types::{AlarmState, DeviceMeasurement};

const HYSTERESIS_FRACTION: f64 = 0.01;

#[derive(Debug, Clone, PartialEq)]
pub struct AlertConfiguration {
    pub short_threshold: f64,
    pub dcv_high_alarm_enabled: bool,
    pub dcv_high_alarm_value: f64,
    pub dcv_low_alarm_enabled: bool,
    pub dcv_low_alarm_value: f64,
}

impl Default for AlertConfiguration {
    fn default() -> Self {
        Self {
            short_threshold: 2.0,
            dcv_high_alarm_enabled: false,
            dcv_high_alarm_value: 12.0,
            dcv_low_alarm_enabled: false,
            dcv_low_alarm_value: 0.0,
        }
    }
}

pub struct AlertEvaluator;

impl AlertEvaluator {
    pub fn evaluate(
        measurement: &DeviceMeasurement,
        config: &AlertConfiguration,
        previous_state: AlarmState,
    ) -> AlarmState {
        if measurement.is_open || measurement.is_overload {
            return AlarmState::Open;
        }

        if Self::is_short_condition(measurement, config) {
            return AlarmState::Short;
        }

        if measurement.mode != MeasurementMode::DcVoltage {
            return AlarmState::None;
        }

        let Some(value) = measurement.primary_value else {
            return AlarmState::None;
        };

        if config.dcv_high_alarm_enabled {
            let threshold = config.dcv_high_alarm_value;
            let clear_threshold = threshold * (1.0 - HYSTERESIS_FRACTION);
            if value > threshold {
                return AlarmState::HighAlarm;
            }
            if previous_state == AlarmState::HighAlarm && value > clear_threshold {
                return AlarmState::HighAlarm;
            }
        }

        if config.dcv_low_alarm_enabled {
            let threshold = config.dcv_low_alarm_value;
            let clear_threshold = threshold * (1.0 + HYSTERESIS_FRACTION);
            if value < threshold {
                return AlarmState::LowAlarm;
            }
            if previous_state == AlarmState::LowAlarm && value < clear_threshold {
                return AlarmState::LowAlarm;
            }
        }

        AlarmState::None
    }

    pub fn enrich_measurement(
        mut measurement: DeviceMeasurement,
        config: &AlertConfiguration,
    ) -> DeviceMeasurement {
        let is_short = Self::is_short_condition(&measurement, config);
        measurement.is_short = is_short;
        measurement
    }

    fn is_short_condition(
        measurement: &DeviceMeasurement,
        config: &AlertConfiguration,
    ) -> bool {
        if measurement.is_overload || measurement.is_open {
            return false;
        }
        let Some(value) = measurement.primary_value else {
            return false;
        };
        matches!(
            measurement.mode,
            MeasurementMode::Continuity | MeasurementMode::Resistance | MeasurementMode::Diode
        ) && value < config.short_threshold
    }
}
```

- [ ] **Step 4: Add module to lib.rs, run tests**

Run: `cargo test -p readout-core`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add crates/readout-core/
git commit -m "feat(core): add MeasurementAlerts with hysteresis and short detection"
```

---

### Task 7: ChartPipeline

**Files:**
- Create: `crates/readout-core/src/chart_pipeline.rs`
- Create: `crates/readout-core/tests/chart_pipeline_test.rs`

- [ ] **Step 1: Write tests**

```rust
// crates/readout-core/tests/chart_pipeline_test.rs
use readout_core::chart_pipeline::*;
use std::time::Duration;

#[test]
fn empty_pipeline_returns_empty() {
    let pipeline = ChartPipeline::new(1000);
    let points = pipeline.query(Duration::from_secs(120), 800);
    assert!(points.is_empty());
}

#[test]
fn push_and_query_returns_points() {
    let mut pipeline = ChartPipeline::new(1000);
    let base = Duration::from_secs(100);
    for i in 0..10 {
        pipeline.push(base + Duration::from_millis(i * 100), i as f64);
    }
    let points = pipeline.query(Duration::from_secs(120), 800);
    assert_eq!(points.len(), 10);
}

#[test]
fn ring_buffer_wraps_at_capacity() {
    let mut pipeline = ChartPipeline::new(5);
    let base = Duration::from_secs(100);
    for i in 0..10 {
        pipeline.push(base + Duration::from_millis(i * 100), i as f64);
    }
    // Only last 5 should remain
    let points = pipeline.query(Duration::from_secs(120), 100);
    assert_eq!(points.len(), 5);
    assert!((points[0].1 - 5.0).abs() < 0.001);
}

#[test]
fn time_filter_excludes_old_samples() {
    let mut pipeline = ChartPipeline::new(1000);
    let now = Duration::from_secs(200);
    // Add samples: some old, some recent
    for i in 0..100 {
        let ts = Duration::from_secs(100 + i);
        pipeline.push(ts, i as f64);
    }
    // Query last 30 seconds from ts=200
    let points = pipeline.query_with_now(Duration::from_secs(30), 800, now);
    // Should only have samples from ts=170..199
    assert!(points.len() <= 30);
    assert!(points.first().unwrap().0 >= Duration::from_secs(170));
}

#[test]
fn downsampling_reduces_to_target() {
    let mut pipeline = ChartPipeline::new(10000);
    let base = Duration::from_secs(0);
    for i in 0..5000 {
        pipeline.push(base + Duration::from_millis(i * 20), (i as f64).sin());
    }
    let points = pipeline.query(Duration::from_secs(120), 200);
    // Should be around 200 points (min-max pairs)
    assert!(points.len() <= 400); // min-max doubles the count
    assert!(points.len() >= 100);
}

#[test]
fn downsampling_preserves_peaks() {
    let mut pipeline = ChartPipeline::new(1000);
    let base = Duration::from_secs(0);
    // Create data with a clear spike at index 50
    for i in 0..100 {
        let value = if i == 50 { 100.0 } else { 1.0 };
        pipeline.push(base + Duration::from_millis(i * 100), value);
    }
    let points = pipeline.query(Duration::from_secs(30), 20);
    // The spike should be preserved
    let max_val = points.iter().map(|p| p.1).fold(f64::NEG_INFINITY, f64::max);
    assert!((max_val - 100.0).abs() < 0.001);
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `cargo test -p readout-core`
Expected: Compilation error.

- [ ] **Step 3: Implement ChartPipeline**

```rust
// crates/readout-core/src/chart_pipeline.rs
use std::time::Duration;

/// A point in the chart: (timestamp, value).
pub type ChartPoint = (Duration, f64);

pub struct ChartPipeline {
    buffer: Vec<ChartPoint>,
    capacity: usize,
    write_pos: usize,
    count: usize,
}

impl ChartPipeline {
    pub fn new(capacity: usize) -> Self {
        Self {
            buffer: vec![(Duration::ZERO, 0.0); capacity],
            capacity,
            write_pos: 0,
            count: 0,
        }
    }

    pub fn push(&mut self, timestamp: Duration, value: f64) {
        self.buffer[self.write_pos] = (timestamp, value);
        self.write_pos = (self.write_pos + 1) % self.capacity;
        if self.count < self.capacity {
            self.count += 1;
        }
    }

    pub fn clear(&mut self) {
        self.write_pos = 0;
        self.count = 0;
    }

    /// Query with automatic "now" = latest sample timestamp.
    pub fn query(&self, time_range: Duration, target_points: usize) -> Vec<ChartPoint> {
        if self.count == 0 {
            return Vec::new();
        }
        let latest_idx = if self.write_pos == 0 {
            self.capacity - 1
        } else {
            self.write_pos - 1
        };
        let now = self.buffer[latest_idx].0;
        self.query_with_now(time_range, target_points, now)
    }

    pub fn query_with_now(
        &self,
        time_range: Duration,
        target_points: usize,
        now: Duration,
    ) -> Vec<ChartPoint> {
        if self.count == 0 {
            return Vec::new();
        }

        let cutoff = now.saturating_sub(time_range);

        // Collect samples in chronological order within time range
        let samples = self.ordered_samples_after(cutoff);

        if samples.len() <= target_points {
            return samples;
        }

        // Min-max downsample
        Self::min_max_downsample(&samples, target_points)
    }

    fn ordered_samples_after(&self, cutoff: Duration) -> Vec<ChartPoint> {
        let mut result = Vec::new();
        let start = if self.count < self.capacity {
            0
        } else {
            self.write_pos
        };

        for i in 0..self.count {
            let idx = (start + i) % self.capacity;
            let sample = self.buffer[idx];
            if sample.0 >= cutoff {
                result.push(sample);
            }
        }
        result
    }

    fn min_max_downsample(samples: &[ChartPoint], target_points: usize) -> Vec<ChartPoint> {
        let bucket_count = target_points / 2;
        if bucket_count == 0 {
            return Vec::new();
        }

        let bucket_size = samples.len() as f64 / bucket_count as f64;
        let mut result = Vec::with_capacity(target_points);

        for b in 0..bucket_count {
            let start = (b as f64 * bucket_size) as usize;
            let end = ((b + 1) as f64 * bucket_size) as usize;
            let end = end.min(samples.len());

            if start >= end {
                continue;
            }

            let mut min_sample = samples[start];
            let mut max_sample = samples[start];

            for &sample in &samples[start..end] {
                if sample.1 < min_sample.1 {
                    min_sample = sample;
                }
                if sample.1 > max_sample.1 {
                    max_sample = sample;
                }
            }

            // Add in chronological order
            if min_sample.0 <= max_sample.0 {
                result.push(min_sample);
                if min_sample != max_sample {
                    result.push(max_sample);
                }
            } else {
                result.push(max_sample);
                if min_sample != max_sample {
                    result.push(min_sample);
                }
            }
        }

        result
    }
}
```

- [ ] **Step 4: Add module to lib.rs, run tests**

Run: `cargo test -p readout-core`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add crates/readout-core/
git commit -m "feat(core): add ChartPipeline with ring buffer and min-max downsampling"
```

---

## Chunk 2: readout-persistence (Config, Outputs)

### Task 8: AppConfiguration + ConfigStore

**Files:**
- Create: `crates/readout-persistence/src/config.rs`
- Create: `crates/readout-persistence/src/config_store.rs`
- Create: `crates/readout-persistence/tests/config_test.rs`

- [ ] **Step 1: Write tests**

```rust
// crates/readout-persistence/tests/config_test.rs
use readout_persistence::config::*;

#[test]
fn default_config_is_valid() {
    let config = AppConfiguration::default();
    assert_eq!(config.sample_rate_hz, 10);
    assert!(!config.use_simulator);
    assert!(config.multimeter_enabled);
}

#[test]
fn deserialize_with_missing_keys_uses_defaults() {
    let json = r#"{"multimeter_port": "/dev/ttyUSB0"}"#;
    let config: AppConfiguration = serde_json::from_str(json).unwrap();
    assert_eq!(config.multimeter_port, "/dev/ttyUSB0");
    assert_eq!(config.sample_rate_hz, 10); // default
    assert!(!config.use_simulator); // default
}

#[test]
fn clamp_values_enforces_ranges() {
    let json = r#"{"sample_rate_hz": 999, "pc_beep_volume": 5.0}"#;
    let config: AppConfiguration = serde_json::from_str(json).unwrap();
    assert_eq!(config.sample_rate_hz, 50); // clamped to max
    assert!((config.pc_beep_volume - 1.0).abs() < 0.001); // clamped to max
}

#[test]
fn clamp_values_enforces_minimums() {
    let json = r#"{"sample_rate_hz": 0, "pc_beep_volume": -1.0}"#;
    let config: AppConfiguration = serde_json::from_str(json).unwrap();
    assert_eq!(config.sample_rate_hz, 1);
    assert!((config.pc_beep_volume - 0.0).abs() < 0.001);
}

#[test]
fn roundtrip_serialize_deserialize() {
    let original = AppConfiguration::default();
    let json = serde_json::to_string_pretty(&original).unwrap();
    let restored: AppConfiguration = serde_json::from_str(&json).unwrap();
    assert_eq!(original, restored);
}

#[test]
fn case_insensitive_theme_parsing() {
    let json = r#"{"dashboard_theme": "DARK"}"#;
    let config: AppConfiguration = serde_json::from_str(json).unwrap();
    assert_eq!(config.dashboard_theme, DashboardTheme::Dark);
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `cargo test -p readout-persistence`
Expected: Compilation error.

- [ ] **Step 3: Implement config.rs**

Port `AppConfiguration` struct with all fields from Swift, using `#[serde(default)]` for fallback defaults and a `clamp_values()` post-deserialize hook via a custom `Deserialize` impl. Include all enums: `ObsOutputMode`, `DashboardDeviceVisibility`, `DashboardTheme`, `PopoutDisplayMode`. Use `#[serde(rename_all = "snake_case")]` where possible, custom `#[serde(rename = "...")]` for specific keys matching the spec.

Key fields (ported from Swift `AppConfiguration`):
- Device: `multimeter_port`, `usbc_port`, `multimeter_enabled`, `usbc_enabled`, `use_simulator`, `multimeter_auto_reconnect`, `usbc_auto_reconnect`
- Sample: `sample_rate_hz` (1..50), `graph_history_seconds` (5..600)
- Output queue: `output_queue_capacity` (8..2048), `output_queue_max_retry_attempts` (0..10)
- Alarms: `short_threshold` (min 0.1), `dcv_high_alarm_enabled`, `dcv_high_alarm_value`, `dcv_low_alarm_enabled`, `dcv_low_alarm_value`, `beep_on_alarm`, `beep_on_short_pc`, `beep_on_short_meter`
- Audio: `pc_beep_volume` (0.0..1.0), `dashboard_beep_master_enabled`
- OBS: `multimeter_output_file`, `usbc_output_file`, output modes, custom templates, value labels
- CSV: enable flags, file paths per device
- UI: `dashboard_device_visibility`, `dashboard_theme`, `runtime_log_panel_visible`, popout modes and frames

- [ ] **Step 4: Implement config_store.rs**

```rust
// crates/readout-persistence/src/config_store.rs
use crate::config::AppConfiguration;
use std::path::PathBuf;

pub fn default_config_path() -> PathBuf {
    let base = dirs::config_dir().unwrap_or_else(|| PathBuf::from("."));
    base.join("readout").join("config.json")
}

pub fn load(path: &std::path::Path) -> Result<AppConfiguration, ConfigStoreError> {
    if !path.exists() {
        return Ok(AppConfiguration::default());
    }
    let data = std::fs::read_to_string(path)
        .map_err(|e| ConfigStoreError::ReadFailed(e.to_string()))?;
    serde_json::from_str(&data)
        .map_err(|e| ConfigStoreError::ParseFailed(e.to_string()))
}

pub fn save(config: &AppConfiguration, path: &std::path::Path) -> Result<(), ConfigStoreError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| ConfigStoreError::WriteFailed(e.to_string()))?;
    }
    let json = serde_json::to_string_pretty(config)
        .map_err(|e| ConfigStoreError::SerializeFailed(e.to_string()))?;
    std::fs::write(path, json)
        .map_err(|e| ConfigStoreError::WriteFailed(e.to_string()))
}

#[derive(Debug)]
pub enum ConfigStoreError {
    ReadFailed(String),
    ParseFailed(String),
    WriteFailed(String),
    SerializeFailed(String),
}
```

- [ ] **Step 5: Run tests — verify they pass**

Run: `cargo test -p readout-persistence`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add crates/readout-persistence/
git commit -m "feat(persistence): add AppConfiguration with serde, clamping, and ConfigStore"
```

---

### Task 9: ConfigValidator

**Files:**
- Create: `crates/readout-persistence/src/config_validator.rs`
- Create: `crates/readout-persistence/tests/config_validator_test.rs`

- [ ] **Step 1: Write tests**

```rust
// crates/readout-persistence/tests/config_validator_test.rs
use readout_persistence::config::*;
use readout_persistence::config_validator::*;

#[test]
fn valid_simulator_config_has_no_errors() {
    let mut config = AppConfiguration::default();
    config.use_simulator = true;
    let issues = ConfigValidator::validate(&config);
    assert!(issues.iter().all(|i| i.severity != IssueSeverity::Error));
}

#[test]
fn hardware_mode_without_port_is_error() {
    let mut config = AppConfiguration::default();
    config.use_simulator = false;
    config.multimeter_enabled = true;
    config.multimeter_port = String::new();
    let issues = ConfigValidator::validate(&config);
    assert!(issues.iter().any(|i| i.severity == IssueSeverity::Error));
}

#[test]
fn csv_enabled_without_path_is_warning() {
    let mut config = AppConfiguration::default();
    config.use_simulator = true;
    config.multimeter_csv_logging_enabled = true;
    config.multimeter_csv_log_file_path = String::new();
    let issues = ConfigValidator::validate(&config);
    assert!(issues
        .iter()
        .any(|i| i.severity == IssueSeverity::Warning && i.message.contains("CSV")));
}
```

- [ ] **Step 2: Implement ConfigValidator**

```rust
// crates/readout-persistence/src/config_validator.rs
use crate::config::AppConfiguration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IssueSeverity {
    Error,
    Warning,
}

#[derive(Debug, Clone)]
pub struct ValidationIssue {
    pub severity: IssueSeverity,
    pub message: String,
}

pub struct ConfigValidator;

impl ConfigValidator {
    pub fn validate(config: &AppConfiguration) -> Vec<ValidationIssue> {
        let mut issues = Vec::new();

        if !config.use_simulator {
            if config.multimeter_enabled && config.multimeter_port.is_empty() {
                issues.push(ValidationIssue {
                    severity: IssueSeverity::Error,
                    message: "Multimeter enabled but no port configured".into(),
                });
            }
            if config.usbc_enabled && config.usbc_port.is_empty() {
                issues.push(ValidationIssue {
                    severity: IssueSeverity::Error,
                    message: "USB-C meter enabled but no port configured".into(),
                });
            }
        }

        if config.multimeter_csv_logging_enabled
            && config.multimeter_csv_log_file_path.is_empty()
        {
            issues.push(ValidationIssue {
                severity: IssueSeverity::Warning,
                message: "Multimeter CSV logging enabled but no file path set".into(),
            });
        }

        if config.usbc_csv_logging_enabled && config.usbc_csv_log_file_path.is_empty() {
            issues.push(ValidationIssue {
                severity: IssueSeverity::Warning,
                message: "USB-C CSV logging enabled but no file path set".into(),
            });
        }

        if config.dcv_high_alarm_enabled
            && config.dcv_low_alarm_enabled
            && config.dcv_high_alarm_value <= config.dcv_low_alarm_value
        {
            issues.push(ValidationIssue {
                severity: IssueSeverity::Warning,
                message: "High alarm threshold is not above low alarm threshold".into(),
            });
        }

        issues
    }
}
```

- [ ] **Step 3: Run tests, commit**

Run: `cargo test -p readout-persistence`

```bash
git add crates/readout-persistence/
git commit -m "feat(persistence): add ConfigValidator with error and warning detection"
```

---

### Task 10: OutputWriteQueue, CsvLogger, ObsOutputWriter

**Files:**
- Create: `crates/readout-persistence/src/output_queue.rs`
- Create: `crates/readout-persistence/src/csv_logger.rs`
- Create: `crates/readout-persistence/src/obs_writer.rs`
- Create: `crates/readout-persistence/tests/output_queue_test.rs`
- Create: `crates/readout-persistence/tests/csv_logger_test.rs`

- [ ] **Step 1: Write OutputWriteQueue tests**

```rust
// crates/readout-persistence/tests/output_queue_test.rs
use readout_persistence::output_queue::*;
use tokio::sync::mpsc;

#[tokio::test]
async fn queue_accepts_within_capacity() {
    let (tx, mut rx) = mpsc::channel::<String>(8);
    let queue = OutputWriteQueue::new(tx, 8);
    assert!(queue.try_send("hello".into()).is_ok());
    let msg = rx.recv().await.unwrap();
    assert_eq!(msg, "hello");
}

#[tokio::test]
async fn queue_drops_when_full() {
    let (tx, _rx) = mpsc::channel::<String>(2);
    let queue = OutputWriteQueue::new(tx, 2);
    assert!(queue.try_send("one".into()).is_ok());
    assert!(queue.try_send("two".into()).is_ok());
    // Third should report dropped
    let result = queue.try_send("three".into());
    assert!(result.is_err());
}
```

- [ ] **Step 2: Implement OutputWriteQueue**

A thin wrapper around `mpsc::Sender` with bounded capacity and try_send semantics.

- [ ] **Step 3: Write CsvLogger tests**

Test that `CsvLogger` writes header on first write, appends rows with correct format (ISO timestamp, device, value, unit, mode).

- [ ] **Step 4: Implement CsvLogger**

Async task that receives `DeviceMeasurement` via channel, writes CSV rows. Uses `OutputWriteQueue` internally.

- [ ] **Step 5: Implement ObsOutputWriter**

Async task that receives measurements, overwrites text file. Throttled to max 2 Hz using `tokio::time::interval`.

- [ ] **Step 6: Run tests, commit**

Run: `cargo test -p readout-persistence`

```bash
git add crates/readout-persistence/
git commit -m "feat(persistence): add OutputWriteQueue, CsvLogger, and ObsOutputWriter"
```

---

## Chunk 3: readout-io (Transport, Sessions, Drivers, Runtime)

### Task 11: Transport trait + SimulatedTransports

**Files:**
- Create: `crates/readout-io/src/transport.rs`
- Create: `crates/readout-io/src/simulated.rs`
- Create: `crates/readout-io/tests/simulated_test.rs`

- [ ] **Step 1: Write tests for simulated transports**

Test that `SimulatedScpiTransport` responds to FUNC?, MEAS?, *IDN?, beeper commands. Test that `SimulatedStreamingTransport` produces valid 8-char hex frames. Test that both respect sample rate timing.

- [ ] **Step 2: Implement Transport trait**

```rust
// crates/readout-io/src/transport.rs
// Edition 2024: native async fn in traits, no async-trait crate needed.

pub trait DeviceTransport: Send + Sync {
    async fn open(&mut self) -> Result<(), TransportError>;
    async fn close(&mut self);
    async fn read_frame(&mut self) -> Result<Option<String>, TransportError>;
}

pub trait ScpiTransport: DeviceTransport {
    async fn query(&mut self, command: &str) -> Result<Option<String>, TransportError>;
}

#[derive(Debug, thiserror::Error)]
pub enum TransportError {
    #[error("not open")]
    NotOpen,
    #[error("connection lost: {0}")]
    ConnectionLost(String),
    #[error("timeout")]
    Timeout,
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}
```

Note: `thiserror` is already in workspace deps. With edition 2024, no `async-trait` crate needed — use native `async fn` in traits.

- [ ] **Step 3: Implement SimulatedScpiTransport and SimulatedStreamingTransport**

Port from Swift `SimulatedSCPITransport` and `SimulatedStreamingTransport`. Same waveform generation: sine waves with mode cycling for multimeter, voltage/current sine waves for USB-C. Same `encodeUsbCFrame` logic.

- [ ] **Step 4: Run tests, commit**

```bash
git add crates/readout-io/
git commit -m "feat(io): add Transport trait and simulated transports"
```

---

### Task 12: DeviceSession state machine

**Files:**
- Create: `crates/readout-io/src/device_session.rs`
- Create: `crates/readout-io/tests/device_session_test.rs`

- [ ] **Step 1: Write tests for state machine transitions**

Test: idle → connecting → connected on successful open. Test: connected → reconnecting → waiting_retry on error. Test: backoff delay sequence. Test: cancellation stops the loop. Test: successful reconnect resets attempt counter. Use a mock transport that fails N times then succeeds.

- [ ] **Step 2: Implement DeviceSession**

Async state machine that takes a `Box<dyn DeviceTransport>`, a `ReconnectPolicy`, and event/command channels. Runs as a Tokio task. Uses `CancellationToken` for graceful shutdown. Emits `DeviceSessionEvent` (state changes, frames, errors) on a callback channel.

Port `ReconnectPolicy` from Swift: `enabled`, `initial_delay_seconds`, `max_delay_seconds`, `multiplier`, `delay(for_attempt)`.

- [ ] **Step 3: Run tests, commit**

```bash
git add crates/readout-io/
git commit -m "feat(io): add DeviceSession state machine with reconnect policy"
```

---

### Task 13: MultimeterDriver + UsbCDriver

**Files:**
- Create: `crates/readout-io/src/multimeter_driver.rs`
- Create: `crates/readout-io/src/usbc_driver.rs`
- Create: `crates/readout-io/tests/driver_test.rs`

- [ ] **Step 1: Write tests**

Test MultimeterDriver: connects, queries FUNC?, queries MEAS?, parses response into `DeviceMeasurement`. Test UsbCDriver: connects, reads streaming frames, parses into `DeviceMeasurement` with energy accumulation. Use simulated transports.

- [ ] **Step 2: Implement drivers**

`MultimeterDriver`: wraps `ScpiTransport`. On connect, queries FUNC? for mode, then polls MEAS? at configured rate. Parses via `MultimeterParser`. Enriches via `AlertEvaluator::enrich_measurement`. Sends beeper command on connect.

`UsbCDriver`: wraps `DeviceTransport`. Reads frames continuously. Parses via `UsbCFrameParser`. Updates `EnergyAccumulator`. Builds `DeviceMeasurement` with secondary values (current), power, energy.

- [ ] **Step 3: Run tests, commit**

```bash
git add crates/readout-io/
git commit -m "feat(io): add MultimeterDriver and UsbCDriver with parser integration"
```

---

### Task 14: Serial port transport + port discovery

**Files:**
- Create: `crates/readout-io/src/serial_transport.rs`
- Create: `crates/readout-io/src/port_discovery.rs`
- Create: `crates/readout-io/tests/port_discovery_test.rs`

- [ ] **Step 1: Implement SerialTransport**

Wraps `serialport` crate. Implements `DeviceTransport` and `ScpiTransport`. Opens port with baud rate, configures 8N1. `read_frame()` reads until newline. `query()` writes command + newline, then reads response.

- [ ] **Step 2: Implement PortDiscovery**

Uses `serialport::available_ports()`. Scores candidates by matching vendor/product strings against known patterns (e.g., "CH340", "FTDI", "CP210x"). Returns `Vec<PortCandidate>` with port name, score, matched hints.

- [ ] **Step 3: Write port discovery tests**

Test scoring with mock port info. Test empty ports returns empty. Test known vendor string gets high score.

- [ ] **Step 4: Run tests, commit**

```bash
git add crates/readout-io/
git commit -m "feat(io): add SerialTransport and PortDiscovery"
```

---

### Task 15: Runtime orchestrator

**Files:**
- Create: `crates/readout-io/src/runtime.rs`
- Create: `crates/readout-io/tests/runtime_test.rs`

- [ ] **Step 1: Write tests**

Test: start runtime with simulated transports, receive measurements via broadcast channel. Test: send Stop command, verify shutdown. Test: send Rescan command.

- [ ] **Step 2: Implement Runtime**

```rust
// Pseudostructure:
pub struct Runtime {
    event_tx: broadcast::Sender<RuntimeEvent>,
    command_tx: mpsc::Sender<Command>,
}

impl Runtime {
    pub fn new(config: AppConfiguration) -> (Self, broadcast::Receiver<RuntimeEvent>);
    pub async fn run(&self, cancel: CancellationToken);
    pub fn command_sender(&self) -> mpsc::Sender<Command>;
    pub fn subscribe(&self) -> broadcast::Receiver<RuntimeEvent>;
}
```

Spawns device session tasks per enabled device. Listens for commands. Manages CSV/OBS output subscribers. Handles graceful shutdown sequence.

- [ ] **Step 3: Run tests, commit**

```bash
git add crates/readout-io/
git commit -m "feat(io): add Runtime orchestrator with event bus and command channel"
```

---

## Chunk 4: readout-gui (egui Desktop App)

### Task 16: Minimal eframe app with tokio integration

**Files:**
- Modify: `readout-gui/src/main.rs`
- Create: `readout-gui/src/app.rs`

- [ ] **Step 1: Implement basic eframe + tokio integration**

**Threading model:** eframe runs its own event loop on the main thread. Tokio runtime runs on a separate background thread. Communication uses `std::sync::mpsc` (not tokio channels) to bridge the two worlds:

1. Start tokio runtime in `std::thread::spawn`
2. The tokio side subscribes to `broadcast::Receiver<RuntimeEvent>`, forwards events via `std::sync::mpsc::Sender<RuntimeEvent>` to the UI thread
3. In `App::update()`, call `receiver.try_recv()` in a loop to drain all pending events
4. Store `egui::Context` in the app and pass a clone to the tokio bridge. When new events arrive, call `ctx.request_repaint()` to wake eframe — without this the UI appears frozen between mouse events
5. For continuous 60 FPS rendering, also call `ctx.request_repaint_after(Duration::from_millis(16))` in `update()`

**CLI args:** Use `clap` to parse `--config <path>` (override config location) and `--simulator` (force simulator mode).

```rust
// Skeleton structure:
struct ReadOutApp {
    event_rx: std::sync::mpsc::Receiver<RuntimeEvent>,
    command_tx: tokio::sync::mpsc::Sender<Command>,
    state: DashboardState,
}

impl eframe::App for ReadOutApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Drain events
        while let Ok(event) = self.event_rx.try_recv() {
            self.state.handle_event(event);
        }
        // Request continuous repaint
        ctx.request_repaint_after(std::time::Duration::from_millis(16));
        // ... render UI ...
    }
}
```

- [ ] **Step 2: Verify it compiles and opens a window**

Run: `cargo run -p readout-gui`
Expected: Empty window opens and closes cleanly.

- [ ] **Step 3: Commit**

```bash
git add readout-gui/
git commit -m "feat(gui): minimal eframe app with tokio runtime integration"
```

---

### Task 17: Dashboard layout — header, device cards, status strip

**Files:**
- Create: `readout-gui/src/widgets/header.rs`
- Create: `readout-gui/src/widgets/device_card.rs`
- Create: `readout-gui/src/widgets/status_strip.rs`
- Create: `readout-gui/src/widgets/mod.rs`
- Create: `readout-gui/src/dashboard_state.rs`

- [ ] **Step 1: Implement DashboardState in readout-core**

Create `crates/readout-core/src/dashboard_state.rs` — shared between GUI and TUI. Pure data, no UI dependency. Holds:
- Latest `DeviceMeasurement` per device
- `ConnectionState` per device
- `AlarmState` per device
- Health metrics (reconnect count, error count, parse errors, output drops)
- `ChartPipeline` per device
- Runtime log buffer (last N `RuntimeEvent::Log` entries)
- `fn handle_event(&mut self, event: RuntimeEvent)` — updates all fields from an event

- [ ] **Step 2: Implement header widget**

Start/stop button, pause button, connection indicators. Uses egui `ui.horizontal()`.

- [ ] **Step 3: Implement device card widgets**

Large primary value text, unit, mode label. Alarm indicator (colored background) with **Acknowledge** button (sends `Command::AcknowledgeAlarm`). **Silence** dropdown with 1m/5m/15m presets (sends `Command::SilenceAlarm`). Secondary values for USB-C (power, energy).

- [ ] **Step 4: Implement status strip**

Connection badges, reconnect/error counts, refresh Hz counter, output status indicators.

- [ ] **Step 5: Implement keyboard shortcuts**

Via `ctx.input(|i| ...)` in `App::update()`:
- `Ctrl+1` / `Cmd+1`: toggle multimeter popout
- `Ctrl+2` / `Cmd+2`: toggle USB-C popout
- `Ctrl+P` / `Cmd+P`: pause/resume
- `Ctrl+L` / `Cmd+L`: toggle log panel

Use `ctx.input(|i| i.modifiers.command)` for cross-platform Ctrl/Cmd detection.

- [ ] **Step 6: Implement log panel**

Create `readout-gui/src/widgets/log_panel.rs`. Collapsible panel toggled via Ctrl+L. Scrollable list of `RuntimeEvent::Log` entries from `DashboardState`. Auto-scroll to bottom. Color-coded by log level.

- [ ] **Step 7: Wire into App::update()**

Layout: header top, cards middle row, chart (placeholder), log panel (collapsible), status strip bottom.

- [ ] **Step 6: Run with simulator, verify layout**

Run: `cargo run -p readout-gui -- --simulator`
Expected: Window shows device cards with simulated values updating.

- [ ] **Step 7: Commit**

```bash
git add readout-gui/
git commit -m "feat(gui): add dashboard layout with header, device cards, and status strip"
```

---

### Task 18: Real-time chart with egui_plot

**Files:**
- Create: `readout-gui/src/widgets/chart.rs`

- [ ] **Step 1: Implement chart widget**

Uses `egui_plot::Plot` with `Line` from `ChartPipeline` output. Range picker buttons (2m, 5m, 10m, 30m, 1h). Auto-scrolling X axis. Y axis auto-fit.

- [ ] **Step 2: Wire ChartPipeline into DashboardState**

Each measurement pushes to the pipeline. Chart widget queries on each frame.

- [ ] **Step 3: Run with simulator, verify chart scrolls**

Expected: Live scrolling chart with sine wave from simulator.

- [ ] **Step 4: Commit**

```bash
git add readout-gui/
git commit -m "feat(gui): add real-time chart with egui_plot and range picker"
```

---

### Task 19: Settings panel

**Files:**
- Create: `readout-gui/src/widgets/settings.rs`

- [ ] **Step 1: Implement settings window**

egui `Window` with form fields for all `AppConfiguration` settings. Grouped by section: devices, alarms, outputs, UI. Save/cancel buttons. Sends `Command::UpdateConfig` on save.

- [ ] **Step 2: Wire into app with keyboard shortcut**

Toggle with menu or shortcut.

- [ ] **Step 3: Commit**

```bash
git add readout-gui/
git commit -m "feat(gui): add settings panel with config editing"
```

---

### Task 20: First-run wizard

**Files:**
- Create: `readout-gui/src/widgets/first_run_wizard.rs`

- [ ] **Step 1: Implement wizard modal**

Shows on first launch (no config file) or invalid config. Mode picker (hardware/simulator), device toggles, port selection with discovery results, validation feedback, save button.

- [ ] **Step 2: Commit**

```bash
git add readout-gui/
git commit -m "feat(gui): add first-run wizard with port discovery"
```

---

### Task 21: Themes, popout windows, alarm audio

**Files:**
- Create: `readout-gui/src/theme.rs`
- Create: `readout-gui/src/audio.rs`
- Create: `readout-gui/src/popout.rs`

- [ ] **Step 1: Implement dark/light theme switching**

Map `DashboardTheme` to egui `Visuals`.

- [ ] **Step 2: Implement popout windows**

egui viewports — one per device with enlarged value and chart.

- [ ] **Step 3: Implement alarm audio**

`rodio` plays embedded WAV on alarm trigger. Optional — graceful fallback if audio init fails.

- [ ] **Step 4: Commit**

```bash
git add readout-gui/
git commit -m "feat(gui): add themes, popout windows, and alarm audio"
```

---

## Chunk 5: readout-tui (ratatui Terminal Dashboard)

### Task 22: Minimal ratatui app with tokio

**Files:**
- Modify: `readout-tui/src/main.rs`
- Create: `readout-tui/src/app.rs`

- [ ] **Step 1: Implement basic ratatui + tokio integration**

**Threading model:** Tokio runtime runs on the main thread. ratatui rendering runs in a `tokio::select!` loop alongside event polling:
1. `crossterm::event::poll()` for key/resize events (non-blocking with short timeout)
2. `broadcast_rx.recv()` for runtime events
3. `tokio::time::interval(Duration::from_millis(50))` for render ticks (~20 FPS)

Uses shared `DashboardState` from readout-core (same as GUI).

**CLI args:** Use `clap` to parse `--config <path>` and `--simulator`.

**Alarm audio:** Initialize `rodio` (same as GUI). If audio init fails (headless), log warning and continue.

Ctrl+C / 'q' to quit. Restore terminal on exit (crossterm `disable_raw_mode`, `LeaveAlternateScreen`).

- [ ] **Step 2: Verify it runs in terminal**

Run: `cargo run -p readout-tui`
Expected: Terminal UI shows, exits cleanly on 'q'.

- [ ] **Step 3: Commit**

```bash
git add readout-tui/
git commit -m "feat(tui): minimal ratatui app with tokio integration"
```

---

### Task 23: TUI dashboard — cards, chart, status, navigation

**Files:**
- Create: `readout-tui/src/widgets/mod.rs`
- Create: `readout-tui/src/widgets/device_card.rs`
- Create: `readout-tui/src/widgets/chart.rs`
- Create: `readout-tui/src/widgets/status_bar.rs`

- [ ] **Step 1: Implement device card widgets**

ratatui `Paragraph` with styled text. Large value, unit, alarm indicator with color. Alarm acknowledge key hint ('a' to acknowledge).

- [ ] **Step 2: Implement chart widget**

ratatui `Chart` with `Dataset`. Downsampled from `ChartPipeline`.

- [ ] **Step 3: Implement status bar and key hints**

Connection status, Hz counter, key shortcuts.

- [ ] **Step 4: Implement navigation and focus**

Define `FocusedPanel` enum: `Cards`, `Chart`, `Log`. `Tab` cycles focus. Per-key bindings:
- 's' → settings screen, 'p' → pause, 'q' → quit
- '1'/'2' → fullscreen device view (replaces popout)
- 'a' → acknowledge alarm, 'A' → silence alarm (1m/5m/15m cycle)
- ←/→ → chart range
- 'l' → toggle log panel

- [ ] **Step 5: Run with simulator, verify**

Run: `cargo run -p readout-tui -- --simulator`
Expected: Full TUI dashboard with updating values and chart.

- [ ] **Step 6: Commit**

```bash
git add readout-tui/
git commit -m "feat(tui): add dashboard with device cards, chart, and navigation"
```

---

### Task 24: TUI settings screen

**Files:**
- Create: `readout-tui/src/widgets/settings.rs`

- [ ] **Step 1: Implement settings screen**

Editable fields for config. Tab between fields, Enter to edit, Esc to cancel. Save writes config and sends `Command::UpdateConfig`.

- [ ] **Step 2: Commit**

```bash
git add readout-tui/
git commit -m "feat(tui): add settings screen with editable config fields"
```

---

## Chunk 6: CI, Soak Tests, Polish

### Task 25: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write CI workflow**

```yaml
name: CI
on: [push, pull_request]
jobs:
  build-and-test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy, rustfmt
      - uses: Swatinem/rust-cache@v2
      - name: Install Linux system deps
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y libxkbcommon-dev libwayland-dev libx11-dev libxi-dev libgl1-mesa-dev libasound2-dev
      - run: cargo fmt --check
      - run: cargo clippy -- -D warnings
      - run: cargo build
      - run: cargo test
```

- [ ] **Step 2: Commit**

```bash
git add .github/
git commit -m "ci: add cross-platform CI workflow"
```

---

### Task 26: Soak tests

**Files:**
- Create: `crates/readout-io/tests/soak_test.rs`
- Modify: `crates/readout-io/Cargo.toml` (add `soak` feature)

- [ ] **Step 1: Add soak feature flag**

```toml
[features]
soak = []
```

- [ ] **Step 2: Write soak test**

```rust
#![cfg(feature = "soak")]
// Run: cargo test -p readout-io --features soak -- soak --nocapture

#[tokio::test]
async fn soak_smoke_simulated() {
    // Start runtime with simulated transports
    // Collect 400 frames per device
    // Assert: no panics, frame count met, latency p99 < 100ms
    // Output JSON summary
}
```

- [ ] **Step 3: Add nightly soak CI workflow**

```yaml
name: Nightly Soak
on:
  schedule:
    - cron: '35 3 * * *'
jobs:
  soak:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      - name: Install Linux system deps
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y libasound2-dev
      - run: cargo test -p readout-io --features soak -- soak --nocapture
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: soak-report-${{ matrix.os }}
          path: /tmp/soak-report.json
```

- [ ] **Step 4: Commit**

```bash
git add crates/readout-io/ .github/
git commit -m "test: add soak test harness with smoke preset and nightly CI"
```

---

### Task 27: Graceful shutdown + signal handling

**Files:**
- Modify: `readout-gui/src/main.rs`
- Modify: `readout-tui/src/main.rs`

- [ ] **Step 1: Add signal handling to both binaries**

Use `tokio::signal::ctrl_c()` and `CancellationToken`. **Phased shutdown sequence:**

1. Signal handler fires → send `Command::Stop` to runtime
2. Runtime cancels device session `CancellationToken`s → device tasks finish current frame and exit
3. Runtime awaits device task `JoinHandle`s (ensures serial ports are closed)
4. Runtime signals output tasks (CSV, OBS) to flush via dedicated shutdown channels
5. Output tasks flush remaining buffers, close files, then exit
6. Runtime awaits output task `JoinHandle`s
7. Runtime drops broadcast/command channels
8. Frontend detects channel closed → exits render loop

Order matters: outputs flush **after** devices stop (to capture final measurements) but **before** process exits.

- [ ] **Step 2: Test manual Ctrl+C in both GUI and TUI**

Expected: Clean exit, no panics, CSV flushed.

- [ ] **Step 3: Commit**

```bash
git add readout-gui/ readout-tui/
git commit -m "feat: add graceful shutdown with signal handling in GUI and TUI"
```

---

### Task 28: Final integration test + README

**Files:**
- Create: `tests/integration_test.rs`
- Create: `README.md`

- [ ] **Step 1: Write integration test**

Start runtime with simulator, subscribe to events, verify measurements arrive, send Stop, verify clean shutdown. Run across all platforms in CI.

- [ ] **Step 2: Write README**

Project description, build instructions (`cargo build`), run instructions (`cargo run -p readout-gui`, `cargo run -p readout-tui`), test instructions, CI status.

- [ ] **Step 3: Run full test suite**

Run: `cargo test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add tests/ README.md
git commit -m "docs: add README and integration test"
```
