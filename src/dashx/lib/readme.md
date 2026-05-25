# dashx lib

This directory contains the core runtime libraries for the FrSky Dashboard.

## RX Channel Mapping

The dashboard reads RC channel values directly from the transmitter/receiver via `system.getSource()`.

> **Important:** Channel indices are **zero-based** in code, but your radio displays them as **one-based** (Channel 1 = index 0).

### Channel Map

| Code Index | Radio Channel | Function(s)              |
|:----------:|:-------------:|--------------------------|
| `0`        | Channel 1     | Aileron                  |
| `1`        | Channel 2     | Elevator                 |
| `2`        | Channel 3     | Throttle                 |
| `3`        | Channel 4     | Rudder                   |
| `4`        | Channel 5     | Arm switch               |
| `5`        | Channel 6     | Collective, Flaps        |
| `6`        | Channel 7     | Mode, Gear               |
| `7`        | Channel 8     | Rescue                   |

> Multiple names can share the same channel index — they both read the same physical channel value.

### Where this is defined

The mapping is initialized in `runtime.lua` → `initializeRxMap()`:

```lua
map.aileron    = 0   -- Radio CH1
map.elevator   = 1   -- Radio CH2
map.throttle   = 2   -- Radio CH3
map.rudder     = 3   -- Radio CH4
map.arm        = 4   -- Radio CH5
map.collective = 5   -- Radio CH6
map.flaps      = 5   -- Radio CH6 (same as collective)
map.mode       = 6   -- Radio CH7
map.gear       = 6   -- Radio CH7 (same as mode)
map.rescue     = 7   -- Radio CH8
```

### Armed State Detection

The arm channel value (`rx.values.arm`) is read from **Radio Channel 5** and used to derive the armed state:

- `value >= 500` → **Armed** (sensor returns `0`)
- `value < 500`  → **Disarmed** (sensor returns `1`)

> **Note:** The armed sensor value convention is inverted — `0` means armed, `1` means disarmed.

### Protocol Detection Order

The dashboard auto-detects the protocol in this order:

1. **sim** — Running in Ethos simulator
2. **sport** — Internal module with S.Port (appId `0xF101`)
3. **crsf** — External module with CRSF (`crsfId 0x14`)
4. **sport** — External module with S.Port fallback
5. **spektrum** — External module with Spektrum (detected via `Tx RSSI`)
