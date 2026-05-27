# How to Deploy FrSky Dashboard to Your Radio

## Quick Deploy to Radio
Use the **"Deploy Radio"** task:
1. Press `Ctrl+Shift+D` (or **Run** → **Run Task**) 
2. Select **"Deploy Radio"**

This will:
- Build the dashboard (compile Lua, generate i18n files)
- Package it as `fsdash.zip`
- Upload to your radio via USB

## Alternative Deploy Options

| Task | Purpose |
|------|---------|
| **Deploy Radio [Fast]** | Faster deployment (skips some rebuilds) |
| **Deploy Radio + Serial Debug** | Deploy + connect serial debug console to see logs |
| **Deploy Radio + Serial Debug [Fast]** | Same but faster |
| **Deploy & Launch [SIM]** | Build and run in the simulator instead |

## Manual Deploy via Terminal

If you prefer running it manually:
```powershell
python .vscode\scripts\deploy.py --radio --lang en --step i18n --step soundpack --step sensors
```

## Prerequisites
- **Ethos Suite** installed (detected at `C:\Program Files\Ethos Suite\`)
- **Radio connected** via USB (detects FrSky radios automatically)
- **Python 3** available in your PATH

## Steps Included in Deploy
The build process automatically handles:
1. **i18n** — Merges language files into `scripts/fsdash/i18n/`
2. **soundpack** — Generates localized sound packs
3. **Lua compilation** — Formats and validates all Lua code
4. **Packaging** — Creates the deployable zip
5. **Upload** — Transfers to radio's `SCRIPTS:/FSDash/` directory

## If Widget Is Missing In Screen Setup

If the widget does not appear in the Ethos screen widget list after deploy:

1. Verify folder name on radio is exactly `SCRIPTS:/FSDash/` (capitalization matters for script path resolution).
2. Remove old `SCRIPTS:/fsdash/` folder if present.
3. Re-run deploy and reboot the radio once.
4. Open Screen Setup and look for **FSDash**.
