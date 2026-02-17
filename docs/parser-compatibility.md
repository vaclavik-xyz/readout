# Parser Compatibility Spec (v1 Baseline)

This document captures behavior preserved from the legacy Python implementation.

## Multimeter Mode Parsing
- Input mode text is uppercased and trimmed.
- Mapping priority:
  - contains `VOLT` -> AC if `AC` present, else DC
  - contains `CURR` -> AC if `AC` present, else DC
  - contains `CONT` -> continuity
  - contains `RES`/`OHM`/`FRES` -> resistance
  - contains `DIOD` -> diode
  - contains `CAP` -> capacitance
  - contains `FREQ` -> frequency
  - contains `PER` -> period
  - contains `TEMP` -> temperature
  - otherwise unknown

## Multimeter Value Parsing
- Overload by keywords: response containing `OL` or `OVER`.
- Numeric extraction regex:
  - `^([+-]?\d+\.?\d*(?:[Ee][+-]?\d+)?)\s*(.*)$`
- If payload contains comma-separated segments, parse first segment.
- Parse failure returns empty value (`nil`) and empty unit.

### Overload Thresholds
- Resistance/Continuity/Diode: `abs(value) >= 1e7`
- Other modes: `abs(value) >= 1e30`

### Open State Rule
- `isOpen = true` only for overload in resistance/continuity/diode family.

## USB-C Frame Parsing
- Frame length must be exactly 8 hex chars.
- Frame format: `[SSSS][BBBB]`.
  - `SSSS`: signed 16-bit shunt raw
  - `BBBB`: unsigned 16-bit bus raw
- Conversion:
  - `voltage = busRaw * 0.003125`
  - `current = shuntRaw * 0.0002`
- Negative current is clamped to `0`.

## Energy Accumulation
- Uses timestamp delta in hours:
  - `energy_mWh += power_W * 1000 * delta_hours`
  - `energy_mAh += current_A * 1000 * delta_hours`
