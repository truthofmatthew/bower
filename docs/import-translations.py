#!/usr/bin/env python3
"""Merges build/loc/<lang>.json translations into Sources/Localizable.xcstrings.

Each <lang>.json maps an English key (as exported by `xcodebuild -exportLocalizations`) to its translation.
A language is refused if a key is missing or a translation's format specifiers differ from the key's,
since a lost %@ or %lld would break the formatted string at runtime.

Run from the repo root:  python3 docs/import-translations.py ja de fr es pt-BR it
"""
import json
import re
import sys
from collections import Counter

SPEC = re.compile(r'%(?:\d+\$)?(@|lld|ld|d|f|\.\d+f)')
keys = [e["key"] for e in json.load(open("build/loc/keys.json"))]
catalog_path = "Sources/Localizable.xcstrings"
catalog = json.load(open(catalog_path))
strings = catalog.setdefault("strings", {})


def specs(s):
    return Counter(SPEC.findall(s))


failed = False
for lang in sys.argv[1:]:
    tr = json.load(open(f"build/loc/{lang}.json"))
    missing = [k for k in keys if k not in tr]
    bad = [k for k in keys if k in tr and specs(k) != specs(tr[k])]
    if missing or bad:
        failed = True
        print(f"{lang}: refused — {len(missing)} missing, {len(bad)} with different format specifiers")
        for k in (missing + bad)[:10]:
            print("   ", repr(k), "→", repr(tr.get(k)))
        continue
    for k in keys:
        if k in ("CFBundleDisplayName", "CFBundleName"):
            continue  # Info.plist names stay "Bower"
        entry = strings.setdefault(k, {})
        entry.setdefault("localizations", {})[lang] = {"stringUnit": {"state": "translated", "value": tr[k]}}
    print(f"{lang}: {len(keys)} keys imported")

json.dump(catalog, open(catalog_path, "w"), ensure_ascii=False, indent=2, sort_keys=True)
sys.exit(1 if failed else 0)
