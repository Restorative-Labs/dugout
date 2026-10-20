#!/usr/bin/env python3
"""Ship checks for the iOS build — any failure stops the TestFlight lane (DUG-63).

    python3 scripts/ship_checks.py source <repo>
        The files as committed, before anything is built.

    python3 scripts/ship_checks.py ipa <repo> <DugOut.ipa> --bundle-id <id> --build <n>
        What will actually be uploaded, after the build.

What fails the build:

  DUG-96 / DUG-44  The app's entry point is an outside address.
      * Native: every http(s)/ws(s) URL written in the app's Swift code must be the loopback
        server (127.0.0.1 / localhost). The web view must load the loopback index.html, and the
        loopback server must serve from the app bundle — never from a download.
      * Web: index.html, the page the web view opens, may not reference an outside address at
        all — no http:, https:, protocol-relative //host, <base href> or refresh redirect
        (XML namespace identifiers like xmlns="http://www.w3.org/2000/svg" are not fetched and
        are allowed). The same holds for every stylesheet. Every <script src> and <link href>
        in index.html must be a file that ships.
  DUG-97  SharePoint marks in a shipped text file: xmlns:mso, CustomDocumentProperties, the
      urn:schemas-microsoft-com:office namespace, or an HTML <title> that is missing or blank.
  DUG-44  The web files ship inside the app, untouched: in the .ipa, every shipped file is
      byte-identical to the repo's. Nothing is transformed and nothing comes over the air.
  Packaging  the .ipa's bundle id and build number are the ones the lane asked for, and
      ITSAppUsesNonExemptEncryption is NO (so App Store Connect asks nothing by hand).

Standard library only. Prints one line per finding and exits 1 if there is any.
"""
from __future__ import annotations

import argparse
import hashlib
import plistlib
import re
import sys
import zipfile
from pathlib import Path

# What the Xcode project bundles from the repo root (its Resources build phase, Assets aside).
# checked against the project file in `source` mode, so this list cannot silently drift.
SHIPPED = ["index.html", "css", "js", "vendor", "shadow-sprite.jpg", "swing-shadow.mp4"]
ENTRY = "index.html"
NATIVE_DIR = "ios/DugOut"
PBXPROJ = "ios/DugOut.xcodeproj/project.pbxproj"
LOOPBACK = {"127.0.0.1", "localhost", "::1", "[::1]"}
TEXT_SUFFIXES = {".html", ".htm", ".css", ".js", ".mjs", ".json", ".svg", ".xml", ".txt", ".plist", ".swift"}
SHAREPOINT_MARKS = ["xmlns:mso", "CustomDocumentProperties", "urn:schemas-microsoft-com:office"]

URL_RE = re.compile(r"\b(https?|wss?)://([^/\s\"'\\:)>]+)", re.IGNORECASE)
SCHEME_RE = re.compile(r"\b(https?|wss?):", re.IGNORECASE)
NAMESPACE_ATTR_RE = re.compile(r"""\bxmlns(:[\w-]+)?\s*=\s*["'][^"']*["']""", re.IGNORECASE)
PROTOCOL_RELATIVE_RE = re.compile(
    r"""(\b(src|href|action|poster|data|srcset|formaction|manifest|content)\s*=\s*["']?\s*//)"""
    r"""|(url\(\s*["']?\s*//)|(@import\s+["']\s*//)""", re.IGNORECASE)
BASE_RE = re.compile(r"<base\b[^>]*\bhref\s*=", re.IGNORECASE)
REFRESH_RE = re.compile(r"""<meta\b[^>]*http-equiv\s*=\s*["']?refresh""", re.IGNORECASE)
TITLE_RE = re.compile(r"<title\b[^>]*>(.*?)</title\s*>", re.IGNORECASE | re.DOTALL)
ASSET_RE = re.compile(r"""<(script|link)\b[^>]*?\b(src|href)\s*=\s*["']([^"']+)["']""", re.IGNORECASE)


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []

    def fail(self, rule: str, where: str, what: str) -> None:
        self.failures.append(f"FAIL [{rule}] {where}: {what}")


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def strip_namespace_attrs(text: str) -> str:
    """Blank out xmlns="…" attributes (identifiers, never fetched), keeping offsets."""
    return NAMESPACE_ATTR_RE.sub(lambda m: " " * len(m.group(0)), text)


# ---------------------------------------------------------------- DUG-96 / DUG-44: entry point

def check_native_entry(repo: Path, rep: Report) -> None:
    sources = sorted((repo / NATIVE_DIR).glob("*.swift"))
    if not sources:
        rep.fail("DUG-96", NATIVE_DIR, "no Swift sources found — cannot tell what the app opens")
        return
    loopback_entry = False
    for src in sources:
        text = src.read_text(encoding="utf-8")
        rel = src.relative_to(repo)
        for m in URL_RE.finditer(text):
            host = m.group(2).lower()
            if host not in LOOPBACK:
                rep.fail("DUG-96", f"{rel}:{line_of(text, m.start())}",
                         f"outside address in the app's code: {m.group(0)}")
        if re.search(r"https?://(127\.0\.0\.1|localhost)[^\"]*/index\.html", text):
            loopback_entry = True
        for api in ("URLSession", "loadHTMLString", "NSURLConnection", "WKDownload"):
            for m in re.finditer(rf"\b{api}\b", text):
                rep.fail("DUG-44", f"{rel}:{line_of(text, m.start())}",
                         f"{api} in the app's code — the app runs only files shipped inside it")
    if not loopback_entry:
        rep.fail("DUG-96", NATIVE_DIR, "the web view does not open the loopback index.html")
    vc = repo / NATIVE_DIR / "ViewController.swift"
    if vc.exists() and "LocalHTTPServer(docRoot: Bundle.main.resourceURL" not in vc.read_text(encoding="utf-8"):
        rep.fail("DUG-44", str(vc.relative_to(repo)),
                 "the loopback server no longer serves from the app bundle (Bundle.main.resourceURL)")


def outside_refs(text: str) -> list[tuple[int, str]]:
    """(offset, snippet) of every outside address a page or stylesheet could fetch."""
    clean = strip_namespace_attrs(text)
    hits = [(m.start(), m.group(0)) for m in SCHEME_RE.finditer(clean)]
    hits += [(m.start(), m.group(0).strip()) for m in PROTOCOL_RELATIVE_RE.finditer(clean)]
    hits += [(m.start(), "<base href>") for m in BASE_RE.finditer(clean)]
    hits += [(m.start(), "refresh redirect") for m in REFRESH_RE.finditer(clean)]
    return sorted(set(hits))


def check_web_entry(entry_text: str, entry_label: str, exists, rep: Report) -> None:
    for off, snippet in outside_refs(entry_text):
        rep.fail("DUG-96", f"{entry_label}:{line_of(entry_text, off)}", f"outside address in the entry point: {snippet}")
    for m in ASSET_RE.finditer(entry_text):
        ref = m.group(3).split("#")[0].split("?")[0]
        if not ref or SCHEME_RE.match(ref) or ref.startswith("//") or ref.startswith("data:"):
            continue          # outside addresses are reported above; data: URIs carry their bytes
        if not exists(ref.lstrip("./")):
            rep.fail("DUG-96", f"{entry_label}:{line_of(entry_text, m.start())}",
                     f"{m.group(1)} {m.group(2)}=\"{ref}\" is not a file that ships")


def check_stylesheets(files: dict[str, bytes], rep: Report, where: str) -> None:
    for name, data in files.items():
        if not name.endswith(".css"):
            continue
        text = data.decode("utf-8", errors="replace")
        for off, snippet in outside_refs(text):
            rep.fail("DUG-96", f"{where}{name}:{line_of(text, off)}", f"outside address in a stylesheet: {snippet}")


# ---------------------------------------------------------------- DUG-97: SharePoint marks

def check_sharepoint(files: dict[str, bytes], rep: Report, where: str) -> None:
    for name, data in files.items():
        if Path(name).suffix.lower() not in TEXT_SUFFIXES:
            continue
        text = data.decode("utf-8", errors="replace")
        for mark in SHAREPOINT_MARKS:
            for m in re.finditer(re.escape(mark), text, re.IGNORECASE):
                rep.fail("DUG-97", f"{where}{name}:{line_of(text, m.start())}", f"SharePoint mark: {mark}")
        if Path(name).suffix.lower() in (".html", ".htm"):
            titles = TITLE_RE.findall(text)
            if not titles:
                rep.fail("DUG-97", f"{where}{name}", "no <title> — SharePoint blanks or strips it")
            elif not any(t.strip() for t in titles):
                rep.fail("DUG-97", f"{where}{name}", "blank <title> — the SharePoint signature")


# ---------------------------------------------------------------- inputs

def repo_shipped_files(repo: Path) -> dict[str, bytes]:
    out: dict[str, bytes] = {}
    for item in SHIPPED:
        p = repo / item
        if p.is_file():
            out[item] = p.read_bytes()
        elif p.is_dir():
            for f in sorted(p.rglob("*")):
                if f.is_file() and f.name != ".DS_Store":
                    out[f.relative_to(repo).as_posix()] = f.read_bytes()
    return out


def check_project_resources(repo: Path, rep: Report) -> None:
    pbx = (repo / PBXPROJ).read_text(encoding="utf-8")
    phase = re.search(r"isa = PBXResourcesBuildPhase;.*?files = \((.*?)\);", pbx, re.DOTALL)
    names = re.findall(r"/\* (.+?) in Resources \*/", phase.group(1)) if phase else []
    bundled = sorted(n for n in names if n != "Assets.xcassets")
    if bundled != sorted(SHIPPED):
        rep.fail("DUG-44", PBXPROJ, f"the app bundles {bundled}, but these checks cover {sorted(SHIPPED)} — "
                                    "update SHIPPED in scripts/ship_checks.py")


def run_source(repo: Path) -> Report:
    rep = Report()
    for item in SHIPPED:
        if not (repo / item).exists():
            rep.fail("DUG-44", item, "a file the app bundles is missing from the repo")
    check_project_resources(repo, rep)
    check_native_entry(repo, rep)
    files = repo_shipped_files(repo)
    if ENTRY in files:
        check_web_entry(files[ENTRY].decode("utf-8", errors="replace"), ENTRY, lambda r: (repo / r).is_file(), rep)
    check_stylesheets(files, rep, "")
    native = {p.relative_to(repo).as_posix(): p.read_bytes() for p in sorted((repo / NATIVE_DIR).rglob("*"))
              if p.is_file() and p.suffix in (".swift", ".plist")}
    check_sharepoint({**files, **native}, rep, "")
    return rep


def run_ipa(repo: Path, ipa: Path, bundle_id: str, build: str) -> Report:
    rep = Report()
    with zipfile.ZipFile(ipa) as z:
        apps = sorted({n.split("/")[1] for n in z.namelist() if n.startswith("Payload/") and n.split("/")[1].endswith(".app")})
        if len(apps) != 1:
            rep.fail("DUG-63", str(ipa), f"expected one app in Payload/, found {apps}")
            return rep
        root = f"Payload/{apps[0]}/"
        shipped = {n[len(root):]: z.read(n) for n in z.namelist() if n.startswith(root) and not n.endswith("/")}
    where = f"{ipa.name}!{apps[0]}/"

    # DUG-44: every web file is inside the app and identical to the commit — no transforms
    repo_files = repo_shipped_files(repo)
    for name, data in repo_files.items():
        if name not in shipped:
            rep.fail("DUG-44", where + name, "missing from the app")
        elif hashlib.sha256(shipped[name]).digest() != hashlib.sha256(data).digest():
            rep.fail("DUG-44", where + name, "differs from the repo — the build changed a shipped file")
    extra = sorted(n for n in shipped if n.split("/")[0] in SHIPPED and n not in repo_files and not n.endswith(".DS_Store"))
    for name in extra:
        rep.fail("DUG-44", where + name, "in the app but not in the repo")

    web = {n: d for n, d in shipped.items() if n.split("/")[0] in SHIPPED}
    if ENTRY in shipped:
        check_web_entry(shipped[ENTRY].decode("utf-8", errors="replace"), where + ENTRY, lambda r: r in shipped, rep)
    else:
        rep.fail("DUG-96", where + ENTRY, "the entry point is not inside the app")
    check_stylesheets(web, rep, where)
    check_sharepoint(web, rep, where)

    # packaging: what App Store Connect will read
    try:
        info = plistlib.loads(shipped["Info.plist"])
    except Exception as exc:  # noqa: BLE001 — any unreadable plist is a failed build
        rep.fail("DUG-63", where + "Info.plist", f"unreadable: {exc}")
        return rep
    if info.get("CFBundleIdentifier") != bundle_id:
        rep.fail("DUG-63", where + "Info.plist", f"bundle id is {info.get('CFBundleIdentifier')!r}, expected {bundle_id!r}")
    if str(info.get("CFBundleVersion")) != str(build):
        rep.fail("DUG-63", where + "Info.plist", f"build number is {info.get('CFBundleVersion')!r}, expected {build!r}")
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        rep.fail("DUG-63", where + "Info.plist", "ITSAppUsesNonExemptEncryption is not NO — upload would need a hand step")
    return rep


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="mode", required=True)
    s = sub.add_parser("source")
    s.add_argument("repo", type=Path)
    i = sub.add_parser("ipa")
    i.add_argument("repo", type=Path)
    i.add_argument("ipa", type=Path)
    i.add_argument("--bundle-id", required=True)
    i.add_argument("--build", required=True)
    args = ap.parse_args(argv)

    repo = args.repo.resolve()
    rep = run_source(repo) if args.mode == "source" else run_ipa(repo, args.ipa.resolve(), args.bundle_id, args.build)
    label = "source" if args.mode == "source" else args.ipa.name
    for f in rep.failures:
        print(f)
    if rep.failures:
        print(f"ship checks FAILED on {label}: {len(rep.failures)} finding(s) — the build stops here.")
        return 1
    print(f"ship checks passed on {label}: entry point is local (DUG-96), no SharePoint marks (DUG-97), "
          f"web files ship inside the app{' unchanged' if args.mode == 'ipa' else ''} (DUG-44).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
