# FSDash Telemetry Sensor Reference

This document explains the structure of every sensor entry in `src/fsdash/lib/telemetry.lua` and what each member means for the dashboard and the radio at runtime.

---

## How it connects

```
Theme box         → telemetry.getSensor(source)   → sensorTable[source]   → system.getSource(...)
(source = "rpm")    (widgets/dashboard/objects/…)    (lib/telemetry.lua)     (Ethos API / radio)
```

1. A theme box sets `source = "some_key"` (e.g. `source = "rpm"`).
2. The generic telemetry object calls `telemetry.getSensor(source)`.
3. `getSensor` looks up `sensorTable[source]` then calls `getSensorSource` to find the live radio value.
4. `getSensorSource` calls `system.getSource(...)` with protocol-specific identifiers that must match what the radio/FC is broadcasting.

If the key is not in `sensorTable`, or the radio is not broadcasting the matching sensor, the source returns `nil` and the box shows animated dots instead of a value.

---

## Sensor entry members

### The key itself

```lua
rpm = { ... }
```

The Lua table key is the **only identifier** themes use in `source = "..."`. It must exactly match a key in `sensorTable`. It is also passed to `telemetry.getSensor()`, `telemetry.getSensorSource()`, `telemetry.getSensorStats()`, and `telemetry.validateSensors()`.

---

### `name`

```lua
name = "Headspeed",
```

Human-readable label. Used in:
- Settings UI sensor lists (`listSensors()`, `listSwitchSensors()`)
- Audio events chooser
- Validation/diagnostic displays

Does **not** affect lookup or value resolution. Can be a plain string or an i18n key (`"@i18n(...)@"`).

---

### `mandatory`

```lua
mandatory = true,   -- or false
```

Controls whether the sensor appears in the **missing sensors** validation list on startup.

- `true` → shows in the preflight warning if the radio cannot resolve this source.
- `false` / omitted → silently absent if not available.

Used by `telemetry.validateSensors()` in `lib/telemetry.lua`.

---

### `stats`

```lua
stats = true,
```

Conceptually marks a sensor as stat-capable. Actual min/max/avg tracking happens only for sensors explicitly listed in `trackedStats` in `lib/runtime.lua`:

```lua
local trackedStats = {"rssi", "voltage", "rpm", "current", "temp_esc",
                      "consumption", "smartconsumption", "smartfuel"}
```

Stats are accessible in theme boxes via `subtype = "stats"` and `source = "rpm"` etc. and read from `telemetry.getSensorStats(key)`.

---

### `switch_alerts`

```lua
switch_alerts = true,   -- or false
```

Whether this sensor appears in the **audio switch alerts** settings list.

- `true` → users can configure a switch to trigger an audio alert based on this sensor's value.
- `false` → sensor is not available in that settings screen.

Used by `telemetry.listSwitchSensors()`.

---

### `set_telemetry_sensors`

```lua
set_telemetry_sensors = 60,   -- or nil
```

An opaque numeric ID exposed through `listSensors()` and `listSwitchSensors()`. Used by the settings UI to associate sensors with configuration slots. Set to `nil` if the sensor has no associated settings slot.

---

### `unit`

```lua
unit = UNIT_RPM,
```

Internal Ethos unit constant. Used as the major unit returned alongside a sensor value from `telemetry.getSensor()`. Consumed by the Ethos rendering system and can influence automatic unit display. Common values:

| Constant | Meaning |
|---|---|
| `UNIT_PERCENT` | % |
| `UNIT_VOLT` | V |
| `UNIT_AMPERE` | A |
| `UNIT_RPM` | rpm |
| `UNIT_DEGREE` | ° (also used for angles) |
| `UNIT_METER` | m |
| `UNIT_MILLIAMPERE_HOUR` | mAh |
| `UNIT_DB` | dB |
| `UNIT_KNOT` | kts |
| `UNIT_G` | G-force |
| `UNIT_RAW` | untyped numeric |

---

### `unit_string`

```lua
unit_string = "rpm",
```

Fallback unit suffix string displayed in the box when the sensor does not return a dynamic unit. Theme boxes can also override this with `unit = "..."` directly in the box definition.

Resolution order in telemetry object wakeup:
1. Box `unit` param (manual override wins)
2. `dynamicUnit` returned from `getSensor()`
3. `sensorTable[source].unit_string` (this field)
4. Empty string `""`

---

### `sensors`

```lua
sensors = {
    sim      = { ... },
    sport    = { ... },
    crsf     = { ... },
    spektrum = { ... },
}
```

Protocol-specific resolver candidates. `getSensorSource()` branches by `dashx.session.telemetryType` and iterates the matching sub-table, calling `system.getSource(entry)` for each candidate until one resolves.

#### `sim`

Used when `system.getVersion().simulation == true`. Two forms:

**uid form** — looks up a simulator telemetry slot by UID:
```lua
sim = {{uid = 0x5003, unit = UNIT_RPM, dec = nil,
        value = function() return dashx.utils.simSensors('rpm') end,
        min = 0, max = 4000}}
```
The `value` function provides the simulated value. `min`/`max` are hint ranges for the simulator.

**appId form** — looks up a real telemetry source by appId (used for FrSky-protocol sim sensors):
```lua
sim = {{appId = 0xF010, subId = 0}}
```

#### `sport`

FrSky S.Port / F.Port protocol. Each entry is passed directly to `system.getSource()`. Must match the sensor's telemetry data IDs as broadcast by the FC/ESC:

```lua
sport = {{appId = 0x0B60, subId = 0}, {appId = 0x0500, subId = 0}}
```

Multiple entries are tried in order — the first one that resolves wins. Use this for sensors that may appear under different IDs depending on FC firmware version.

An optional `category` field restricts the source search:
```lua
sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE1}}
```
NOTE:  for FrSky the subId is not usable as there may be 32 bites of data in a block of data for a given App Id.  for example RSSI  RSSI 900Mhz & RSSI 2.4 Ghz may be under one App Id.  So the second way is how you will have to map some of them.  
I also have not confirmed if the different proticals will do different things TD, Access, Acccst, s.Bus, S.Port, F.Port, F.Port2, RB, Ethos Internal

#### `crsf`

CRSF/ELRS protocol. Entries can be:
- **String** — matches source by name as returned by `system.getSource()`:
  ```lua
  crsf = {"Rx RSSI1"}
  ```
- **Table** — matches by ID:
  ```lua
  crsf = {{crsfId = 0x14, subId = 2}}
  ```

The string must exactly match the source name that the CRSF receiver/FC broadcasts to Ethos.

#### `spektrum`

Spektrum protocol. Always string-based source names:
```lua
spektrum = {"Tx RSSI"}
```

#### `crsfLegacy` (optional)

Fallback resolver for older CRSF firmware that broadcasts different source names. Set to `{nil}` when there is no legacy path.

---

### `localizations` (optional)

```lua
localizations = function(value)
    local major = UNIT_DEGREE
    if value == nil then return nil, major, nil end
    local isFahrenheit = dashx.preferences.localizations.temperature_unit == 1
    if isFahrenheit then return value * 1.8 + 32, major, "°F" end
    return value, major, "°C"
end
```

A function that post-processes the raw sensor value before it is returned from `getSensor()`. Returns `value, unit, unit_string_override`.

Used for user-selectable unit preferences:
- Temperature: °C / °F
- Altitude: m / ft

Called inside `getSensor()` after the raw value is read from the radio source.

---

### `source` (optional)

```lua
source = function()
    return someCustomSource
end
```

Advanced: a function that directly provides the Ethos source object instead of going through the protocol lookup. Used for computed or special-case sensors. Bypasses `getSensorSource()` lookup entirely.

---

### `onchange` (optional)

```lua
onchange = function(value)
    -- called each time the sensor value changes
end
```

A callback invoked by `telemetry.wakeup()` every time this sensor's value changes (checked at `ONCHANGE_RATE = 0.5s` intervals). Used to trigger events, audio cues, or state changes on sensor value transitions.

---

## Full example: `rssi` vs `link`

```lua
rssi = {
    name = "RSSI",
    unit = UNIT_PERCENT,   -- percent (0-100)
    unit_string = "%",
    ...
}

link = {
    name = "Link Quality",
    unit = UNIT_DB,        -- decibels
    unit_string = "dB",
    ...
}
```

In theme boxes, if you want to show **dB link quality**, use `source = "link"`.  
If you want to show **RSSI as a percentage**, use `source = "rssi"`.

Using `source = "rssi"` with `unit = "dB"` in the box definition will force the suffix to dB but the value is still the percent reading — the two sensors measure different things.

---

## What must match on the radio

| Protocol | What must match |
|---|---|
| sport | `appId` and `subId` must match IDs transmitted by the FC/ESC in the S.Port/F.Port telemetry stream |
| crsf (string) | String must exactly match the source name in Ethos's CRSF source list for that receiver/FC |
| crsf (table) | `crsfId` and `subId` must match the CRSF telemetry frame IDs |
| spektrum | String must match the source name in Ethos for the Spektrum receiver |
| sim | `uid` matches a simulator slot registered in the Ethos simulator |

If the sensor is being broadcast by the FC but not resolving, check:
1. The correct protocol branch (`telemetryType`) is being matched.
2. The `appId`/name in the sensors table matches what Ethos actually discovers (check the Ethos telemetry page on the radio).
3. The FC firmware version is broadcasting the expected sensor IDs.

---

## Stat tracking

Stats (min/max/avg) are tracked by `lib/runtime.lua` during flight for this fixed set of sensors:

```
rssi, voltage, rpm, current, temp_esc, consumption, smartconsumption, smartfuel
```

To show a stat in a theme box, use:
```lua
{type = "text", subtype = "stats", stattype = "max", source = "rpm", ...}
```

`stattype` can be `"min"`, `"max"`, or `"avg"`. Defaults to `"max"` if omitted.
