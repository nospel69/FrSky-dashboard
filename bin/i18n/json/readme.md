# Internationalization (i18n) JSON Configuration

This directory contains all telemetry definitions and translations for the FrSky Dashboard. It is organized by category, with separate language files for each region.

## Directory Structure

```
i18n/json/
├── en.json, de.json, es.json, fr.json, it.json, nl.json  (Root/Dashboard strings)
├── api/
│   ├── en.json, de.json, es.json, fr.json, it.json, nl.json
├── app/
│   ├── en.json, de.json, es.json, fr.json, it.json, nl.json
├── telemetry/
│   ├── en.json, de.json, es.json, fr.json, it.json, nl.json  ← **Add new telemetry here**
└── widgets/
    ├── en.json, de.json, es.json, fr.json, it.json, nl.json
    └── subdirectories...
```

## How to Add New Telemetry

### 1. Identify the Telemetry ID
First, find the exact **telemetry ID** that your radio transmits. This is the technical identifier (e.g., `batt_voltage`, `esc_temp`, `rssi`).

### 2. Add to Telemetry Files
Edit `telemetry/en.json` and add your telemetry:

```json
"your_telemetry_id": {
  "english": "Human Readable Name",
  "translation": "Human Readable Name",
  "needs_translation": "false"
}
```

### 3. Translate to Other Languages
Add the same entry to `telemetry/de.json`, `telemetry/fr.json`, etc. with appropriate translations:

```json
"your_telemetry_id": {
  "english": "Human Readable Name",
  "translation": "Translated Name",
  "needs_translation": "false"
}
```

## Example: Adding Battery Voltage

If your radio sends telemetry with ID `batt_voltage`:

**telemetry/en.json:**
```json
"batt_voltage": {
  "english": "Battery Voltage",
  "translation": "Battery Voltage",
  "needs_translation": "false"
}
```

**telemetry/de.json:**
```json
"batt_voltage": {
  "english": "Battery Voltage",
  "translation": "Batteriespannung",
  "needs_translation": "false"
}
```

**telemetry/fr.json:**
```json
"batt_voltage": {
  "english": "Battery Voltage",
  "translation": "Tension de Batterie",
  "needs_translation": "false"
}
```

## Key Points

| Part | Must Match | Purpose | Example |
|------|-----------|---------|---------|
| `"key"` | ✅ Radio telemetry ID exactly | Identifies which telemetry from the radio | `"rssi"` |
| `"english"` | ❌ Display name | Human-readable text shown on dashboard | `"RSSI"` |
| `"translation"` | ❌ Localized name | Translated display text for each language | `"Signalstärke"` (German) |

## Building the Merged JSON Files

After adding telemetry entries, merge all language files into a single combined JSON:

### Run the Build Script

```bash
cd bin/i18n
python build-single-json.py
```

**Optional: Build only specific languages**
```bash
python build-single-json.py --only en de fr
```

### Output

The script creates merged files in `scripts/fsdash/i18n/`:
- `scripts/fsdash/i18n/en.json`
- `scripts/fsdash/i18n/de.json`
- `scripts/fsdash/i18n/es.json`
- `scripts/fsdash/i18n/fr.json`
- `scripts/fsdash/i18n/it.json`
- `scripts/fsdash/i18n/nl.json`

These merged files are what the dashboard actually uses.

## Workflow Summary

1. ✏️ Add telemetry ID and display names to `telemetry/en.json` and translate to other languages
2. 🔧 Run `python build-single-json.py` from `bin/i18n/`
3. ✅ Telemetry is now available on the dashboard with proper translations

