# i18n/build-single-json.py
#!/usr/bin/env python3
import os, sys, json
from pathlib import Path
from collections import defaultdict

# Source root: i18n/json/**/<locale>.json
JSON_ROOT = Path(__file__).parent / "json"

# Output root: scripts/dashx/i18n/<locale>.json
OUT_DIR = (Path(__file__).parent / ".." / ".." / "scripts" / "dashx" / "i18n").resolve()

def insert_nested(root: dict, rel_dir: str, leaf: dict) -> None:
    """Place the leaf dict under nested keys derived from rel_dir (e.g. 'widgets/dashboard')."""
    cur = root
    if rel_dir and rel_dir != ".":
        for part in rel_dir.replace("\\", "/").split("/"):
            if not part:
                continue
            cur = cur.setdefault(part, {})
  
	  # shallow-merge at this level
    for key, value in leaf.items():
        if isinstance(value, dict) and isinstance(cur.get(key), dict):
            cur[key] = {**cur[key], **value}
        else:
            cur[key] = value

def source_namespace(rel_dir: str) -> str:
    """Top-level locale files are treated as the dashboard namespace."""
    if rel_dir in ("", "."):
        return ROOT_NAMESPACE
    return rel_dir
def discover_locale_files():
    """Yield tuples (locale, file_path, rel_dir) for every i18n/json/**/<locale>.json."""
    for dirpath, _, files in os.walk(JSON_ROOT):
        rel_dir = os.path.relpath(dirpath, JSON_ROOT)
        for filename in files:
            if not filename.lower().endswith(".json"):
                continue
            locale = filename[:-5]
            if not locale:
                continue
            yield (locale, Path(dirpath) / filename, rel_dir)

def main(argv=None):
    if not JSON_ROOT.exists():
        print(f"ERROR: source directory not found: {JSON_ROOT}", file=sys.stderr)
        return 1

    # optional: filter by locales if passed (e.g. --only en de)
    import argparse
    ap = argparse.ArgumentParser(description="Build merged per-locale JSON files from i18n/json/**/<locale>.json")
    ap.add_argument("--only", nargs="*", help="Limit to specific locales (e.g. --only en de fr)")
    args = ap.parse_args(argv)

    merged_per_locale: dict[str, dict] = defaultdict(dict)
    counts_per_locale: dict[str, int] = defaultdict(int)
    errors = []

    for locale, fpath, rel_dir in discover_locale_files():
        if args.only and locale not in args.only:
            continue
        try:
            with fpath.open("r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:
            errors.append(f"{fpath}: {e}")
            continue
        insert_nested(merged_per_locale[locale], source_namespace(rel_dir), data)
        counts_per_locale[locale] += 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    written = 0
    for locale in sorted(merged_per_locale.keys()):
        out_path = OUT_DIR / f"{locale}.json"
        with out_path.open("w", encoding="utf-8") as f:
            json.dump(merged_per_locale[locale], f, ensure_ascii=False, indent=2, sort_keys=True)
        written += 1
        print(f"✔ Wrote {out_path}  (from {counts_per_locale[locale]} source file(s))")

    if errors:
        print("\nSome files could not be read/parsed:", file=sys.stderr)
        for line in errors:
            print(f"  - {line}", file=sys.stderr)

    if written == 0:
        print("WARNING: No locale files found under", JSON_ROOT, file=sys.stderr)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
