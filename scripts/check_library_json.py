"""Check that the native tip library is byte-for-byte the export of js/library.js.

    python3 scripts/check_library_json.py

Exit 0 when ios/DugOutCore/Sources/DugOutCore/Resources/tip-library.json is exactly what
scripts/export_library_json.swift would write from today's js/library.js; exit 1 with the
reason otherwise. Python standard library only — no Mac, no Swift, no spreadsheet — so it runs
anywhere: in CI on every push, and at the end of scripts/build_library.py.

How: library.js is a JavaScript literal (bare keys, // comments), not JSON. This reads it the
way a JS engine would for the shape build_library.py writes — strings, comments, bare keys —
then serialises it the way the exporter does (JSON.stringify(obj, null, 2), which matches
json.dumps(indent=2, ensure_ascii=False) byte for byte for this data) and compares bytes.
A duplicated key, a construct it does not understand, or any byte of difference fails loudly.

It only ever READS both files. js/library.js is written by scripts/build_library.py alone.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LIBRARY_JS = REPO / "js" / "library.js"
TIP_JSON = REPO / "ios" / "DugOutCore" / "Sources" / "DugOutCore" / "Resources" / "tip-library.json"
PREFIX = "window.DUGOUT_LIBRARY ="


class ShapeError(Exception):
    pass


def js_literal_to_json(src: str) -> str:
    """The object literal assigned to window.DUGOUT_LIBRARY, rewritten as JSON text.

    Copies double-quoted strings verbatim, drops // and /* */ comments outside strings, and
    quotes bare identifier keys. Anything else outside a string must be JSON punctuation,
    a number, or true/false/null — otherwise this is not the shape build_library.py writes.
    """
    start = src.find(PREFIX)
    if start < 0:
        raise ShapeError(f"'{PREFIX}' not found")
    i, n = start + len(PREFIX), len(src)
    out, depth = [], 0
    while i < n:
        c = src[i]
        if c == '"':                                  # string: copy verbatim, escapes included
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            if j >= n:
                raise ShapeError("unterminated string")
            out.append(src[i:j + 1])
            i = j + 1
        elif src.startswith("//", i):                 # line comment
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):                 # block comment
            j = src.find("*/", i + 2)
            if j < 0:
                raise ShapeError("unterminated block comment")
            i = j + 2
        elif c in "-0123456789":                      # number: copy the whole run (1e5, -0.5)
            j = i
            while j < n and src[j] in "0123456789+-.eE":
                j += 1
            out.append(src[i:j])
            i = j
        elif c.isalpha() or c in "_$":                # bare word: a key, or true/false/null
            j = i
            while j < n and (src[j].isalnum() or src[j] in "_$"):
                j += 1
            word = src[i:j]
            k = j
            while k < n and src[k] in " \t\r\n":
                k += 1
            if word in ("true", "false", "null"):
                out.append(word)
            elif k < n and src[k] == ":":
                out.append(json.dumps(word))
            else:
                raise ShapeError(f"unexpected bare word {word!r}")
            i = j
        elif c in "'`":
            raise ShapeError("single-quoted or template string — not the shape build_library.py writes")
        else:
            if c in "{[":
                depth += 1
            elif c in "}]":
                depth -= 1
            elif c == ";" and depth == 0:
                break
            elif c not in ",: \t\r\n":
                raise ShapeError(f"unexpected character {c!r}")
            out.append(c)
            i += 1
            if depth == 0 and "".join(out).strip():
                # the object closed; only whitespace, comments and ';' may follow
                rest = src[i:]
                if rest.strip().lstrip(";").strip():
                    raise ShapeError("unexpected content after the library object")
                break
    return "".join(out)


def no_duplicate_keys(pairs):
    seen = set()
    for k, _ in pairs:
        if k in seen:
            raise ShapeError(f"duplicate key {k!r}")
        seen.add(k)
    return dict(pairs)


def expected_export(library_js: Path) -> bytes:
    text = js_literal_to_json(library_js.read_text(encoding="utf-8"))
    obj = json.loads(text, object_pairs_hook=no_duplicate_keys,
                     parse_constant=lambda c: (_ for _ in ()).throw(ShapeError(f"non-JSON constant {c}")))
    if not isinstance(obj, dict) or not isinstance(obj.get("tips"), list):
        raise ShapeError("DUGOUT_LIBRARY is not an object with a tips array")
    return (json.dumps(obj, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def check(library_js: Path, tip_json: Path) -> str | None:
    """None when the JSON is exactly the export; otherwise the reason."""
    try:
        want = expected_export(library_js)
    except (ShapeError, json.JSONDecodeError) as e:
        return f"could not read {library_js}: {e}"
    if not tip_json.is_file():
        return f"{tip_json} is missing"
    # The exported file must itself be valid JSON with no duplicate keys — bytes alone would not
    # say *which* of two copies a reader keeps.
    have = tip_json.read_bytes()
    try:
        json.loads(have.decode("utf-8"), object_pairs_hook=no_duplicate_keys)
    except (ShapeError, json.JSONDecodeError, UnicodeDecodeError) as e:
        return f"{tip_json} is not clean JSON: {e}"
    if have == want:
        return None
    at = next((k for k, (a, b) in enumerate(zip(have, want)) if a != b), min(len(have), len(want)))
    line = have[:at].count(b"\n") + 1
    return (f"{tip_json.name} differs from the export of {library_js.name} "
            f"(first difference at byte {at}, line {line}; {len(have)} vs {len(want)} bytes)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--library", type=Path, default=LIBRARY_JS)
    ap.add_argument("--json", type=Path, default=TIP_JSON)
    args = ap.parse_args()
    problem = check(args.library, args.json)
    if problem:
        print(f"TIP LIBRARY DRIFT: {problem}", file=sys.stderr)
        print("Fix: python3 scripts/build_library.py (or, if library.js is already right, "
              "swift scripts/export_library_json.swift). Never hand-edit either file.", file=sys.stderr)
        return 1
    print(f"ok: {args.json.name} is byte-for-byte the export of {args.library.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
