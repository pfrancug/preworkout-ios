#!/usr/bin/env python3
"""Builds PreWorkout/Resources/Localizable.xcstrings (pl source + en) from
tools/strings_en.py and checks that every localizable literal in the Swift
code has an English translation."""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from strings_en import EN, PLURALS, VERBATIM  # noqa: E402

# Word-boundary on Tag so header names like ETag are not treated as UI calls.
CALLS = r'(?:Text|Label|Button|Section|navigationTitle|TextField|SecureField|Toggle|Picker|LabeledContent|DatePicker|\bTag\b|ContentUnavailableView|confirmationDialog|alert|IconRow|IntField|DecimalField|DurationField|chainRow|planRow|DisclosureGroup|NavigationLink|String\(localized:)'
LIT = r'"((?:[^"\\]|\\.|\\\([^)]*(?:\([^)]*\))?[^)]*\))*)"'
# Interpolations whose last identifier is one of these are integers (%lld).
INT_NAMES = {"count", "number", "minutes", "reps", "deficit", "age", "exercisecount", "setcount", "statuscode", "n", "total", "setnumber", "done", "planned", "index", "setindex", "setno", "plannedsets"}


def to_key(literal: str) -> str:
    """Replaces each `\\(expr)` (balanced parentheses) with %lld / %@."""
    out, i = [], 0
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(literal) and depth:
                depth += {"(": 1, ")": -1}.get(literal[j], 0)
                j += 1
            expr = literal[i + 2:j - 1].lower().strip()
            names = re.findall(r"[a-z_][a-z0-9_]*", expr)
            last = names[-1] if names else ""
            out.append("%lld" if last in INT_NAMES else "%@")
            i = j
        else:
            out.append(literal[i])
            i += 1
    return "".join(out)


def code_keys():
    keys = set()
    for f in glob.glob(os.path.join(ROOT, "PreWorkout", "**", "*.swift"), recursive=True):
        src = open(f, encoding="utf-8").read()
        for m in re.finditer(CALLS + r'\s*\(?\s*' + LIT, src):
            keys.add(to_key(m.group(1)))
        if f.endswith(("Labels.swift", "SetEntry.swift")):
            for m in re.finditer(r'return ' + LIT, src):
                keys.add(to_key(m.group(1)))
        # LocalizedStringResource fields (e.g. calculator activity levels)
        for m in re.finditer(r'(?:title|detail|label): ' + LIT, src):
            keys.add(to_key(m.group(1)))
        for m in re.finditer(r'Text\(' + LIT + r'\) : Text\(' + LIT + r'\)', src):
            keys.update({to_key(m.group(1)), to_key(m.group(2))})
    return keys


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural(forms):
    return {"variations": {"plural": {k: unit(v) for k, v in forms.items()}}}


def main():
    keys = code_keys()
    missing = sorted(k for k in keys if k not in EN and k not in PLURALS and k not in VERBATIM)
    if missing:
        print("Missing English translations:", *missing, sep="\n  ")
        sys.exit(1)
    unused = sorted(k for k in list(EN) + list(PLURALS) if k not in keys)
    if unused:
        print("Note: translations not found in code (kept):", *unused, sep="\n  ")

    strings = {}
    for key, value in EN.items():
        strings[key] = {"localizations": {"en": unit(value)}}
    for key, (pl, en) in PLURALS.items():
        strings[key] = {"localizations": {"pl": plural(pl), "en": plural(en)}}
    for key in VERBATIM:
        if key in keys:
            strings[key] = {"shouldTranslate": False}

    catalog = {"sourceLanguage": "pl", "strings": dict(sorted(strings.items())), "version": "1.0"}
    out = os.path.join(ROOT, "PreWorkout", "Resources", "Localizable.xcstrings")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(catalog, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print(f"Wrote {len(strings)} strings to {os.path.relpath(out, ROOT)}")


if __name__ == "__main__":
    main()
