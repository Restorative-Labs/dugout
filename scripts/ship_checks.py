#!/usr/bin/env python3
"""Ship checks for the iOS build — any failure stops the TestFlight lane (DUG-63).

    python3 -I scripts/ship_checks.py source <repo>
        The files as they will be bundled, before anything is built.

    python3 -I scripts/ship_checks.py ipa <repo> <DugOut.ipa> --bundle-id <id> --build <n> [--commit <sha>]
        What will actually be uploaded, after the build.

What fails the build:

  DUG-96 / DUG-44  The app's entry point is an outside address.
      * Native: every URL in the Swift the app compiles (its own sources and each linked local
        package; comments aside), every URL value in its Info.plist, and every URL string compiled
        into its executable must be the loopback server (127.0.0.1 / localhost). No URL pieces,
        user info, URLComponents, file/HTML loading or network APIs. The loopback server must
        serve from the app bundle, and the project may not compile Swift these checks do not read.
      * Web: index.html — the page the web view opens — and every stylesheet may not reference
        an outside address: no http(s)/ws(s) scheme, protocol-relative //host, <base href> or
        refresh redirect, HTML entities decoded first. W3C XML namespace identifiers
        (xmlns="http://www.w3.org/…") are not fetched and are allowed. Every <script src> and
        <link href> must be a file that ships.
      * Scripts: no outside address in js/ (escaped or assembled from pieces included) except the
        AI adapter's own endpoint (CLAUDE.md invariant 3). The pose model (MODEL_URL) must be a file
        that ships, and every createDetector call must pass modelUrl: CFG.MODEL_URL — the vendored
        detector silently falls back to a remote model otherwise.
  DUG-97  SharePoint marks in a shipped text file: xmlns:mso, CustomDocumentProperties, the
      urn:schemas-microsoft-com:office namespace, or a page whose head <title> is missing or blank.
  DUG-44  Only the commit ships, untouched: every file in a bundled folder must be tracked by git
      (an ignored .env or .p8 inside js/ would otherwise ship), no credential-like file or
      secret-like content (API key, private key) may be in the app, and in the .ipa every shipped
      file is byte-identical to the commit's (--commit) or, for a dry run, the working tree's.
      Nothing is transformed; nothing comes over the air.
  DUG-153  Debug is off: js/config.js must say DEBUG: false. On, it logs detector confidences —
      internal scores, which are never logged (R-13) — and prints diagnostics on the round card.
  Packaging  the .ipa's bundle id and build number are the ones the lane asked for, and
      ITSAppUsesNonExemptEncryption is NO (so App Store Connect asks nothing by hand).

Standard library only (run with python3 -I). Prints one line per finding; exits 1 if any.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import html
import plistlib
import re
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath

# What the Xcode project bundles from the repo root (the DugOut target's Resources phase, Assets
# aside) — checked against the project file, so this list cannot silently drift.
SHIPPED = ["index.html", "css", "js", "vendor", "shadow-sprite.jpg", "swing-shadow.mp4"]
ENTRY = "index.html"
NATIVE_DIR = "ios/DugOut"
# Every folder whose Swift is compiled into the app: the target's own sources and each local package it links.
NATIVE_DIRS = ["ios/DugOut", "ios/DugOutCore/Sources/DugOutCore"]
PBXPROJ = "ios/DugOut.xcodeproj/project.pbxproj"
CONFIG_JS = "js/config.js"
LOOPBACK = {"127.0.0.1", "localhost", "::1", "[::1]"}
# The one outside address a shipped script may hold: the AI adapter (CLAUDE.md invariant 3). It is
# called only with a key the user enters on the device, and never loads code.
SCRIPT_ALLOWED = {("js/ai.js", "api.anthropic.com")}      # (file, host)
TEXT_SUFFIXES = {".html", ".htm", ".xhtml", ".css", ".js", ".mjs", ".json", ".webmanifest", ".map", ".svg",
                 ".xml", ".txt", ".md", ".plist", ".strings", ".swift"}
PAGE_SUFFIXES = {".html", ".htm", ".xhtml"}
SHAREPOINT_MARKS = ["xmlns:mso", "CustomDocumentProperties", "urn:schemas-microsoft-com:office"]
CREDENTIAL_PATTERNS = ["*.p8", "*.p8.*", "*.p12", "*.pem", "*.cer", "*.key", "*.keychain", "*.mobileprovision",
                       ".env", ".env.*", "*.env", "AuthKey_*",
                       "*.pfx", "*.jks", "*.keystore", "*.der", "*.crt"]
SECRET_RE = re.compile(rb"sk-ant-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}")
BINARY_URL_RE = re.compile(rb"(?i)\b(?:https?|wss?)://([^\x00/\s\"'\\)>]*)")
W3C_NS_RE = re.compile(r"https?://www\.w3\.org/(?:2000/svg|1999/xlink|1999/xhtml|1998/Math/MathML|XML/1998/namespace)\b", re.I)
SCHEME_PIECE_RE = re.compile(r"""(?<!\bhttp)(?<!\bhttps)(?<!\bws)(?<!\bwss)://|(["'`])(?:https?|wss?):\1""", re.I)
DETECTOR_RE = re.compile(r"\bcreateDetector\s*\((?:[^{}()]|\{[^{}]*\}|\([^()]*\))*\)", re.S)
IGNORED_EXTRAS = {".DS_Store"}          # Xcode's folder copy drops these

URL_RE = re.compile(r"\b(https?|wss?)://([^/\s\"'\\)>]*)", re.IGNORECASE)
SCHEME_RE = re.compile(r"\b(https?|wss?)\s*:", re.IGNORECASE)
W3C_NAMESPACE_RE = re.compile(r"""\bxmlns(:[\w-]+)?\s*=\s*(["'])https?://www\.w3\.org/[^"']*\2""", re.IGNORECASE)
PROTOCOL_RELATIVE_RE = re.compile(r"(?<![:\w/\\])//(?=[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d+)?([/?#\"'`)\s,;>\]}]|$))")
BASE_RE = re.compile(r"<base\b[^>]*\bhref\s*=", re.IGNORECASE)
REFRESH_RE = re.compile(r"""<meta\b[^>]*http-equiv\s*=\s*["']?\s*refresh""", re.IGNORECASE)
HEAD_RE = re.compile(r"<head\b[^>]*>(.*?)</head\s*>", re.IGNORECASE | re.DOTALL)
TITLE_RE = re.compile(r"<title\b[^>]*>(.*?)</title\s*>", re.IGNORECASE | re.DOTALL)
ASSET_RE = re.compile(r"""<(script|link)\b[^>]*?\b(src|href)\s*=\s*["']([^"']+)["']""", re.IGNORECASE)
INVISIBLE = " ​‌‍⁠﻿"
MODEL_URL_RE = re.compile(r"""\bMODEL_URL\s*:\s*(["'])(.*?)\1""")
DEBUG_RE = re.compile(r"^\s*DEBUG\s*:\s*([^,\s/]+)", re.MULTILINE)
NATIVE_FORBIDDEN_APIS = ["URLSession", "NSURLConnection", "WKDownload", "URLComponents", "loadFileURL",
                         "loadHTMLString", "load(_ data", "loadSimulatedRequest"]


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []

    def fail(self, rule: str, where: str, what: str) -> None:
        self.failures.append(f"FAIL [{rule}] {where}: {what}")


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def decode(data: bytes) -> str:
    """Text as WebKit would read it: a BOM decides the encoding, otherwise UTF-8."""
    if data.startswith(b"\xef\xbb\xbf"):
        return data[3:].decode("utf-8", errors="replace")
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16", errors="replace")
    return data.decode("utf-8", errors="replace")


def strip_swift_comments(src: str) -> str:
    """Swift source with // and /* */ comments blanked (strings kept; offsets kept)."""
    out, i, n = list(src), 0, len(src)
    in_str = None                                    # '"' or '"""'
    while i < n:
        if in_str:
            if src.startswith(in_str, i):
                i += len(in_str); in_str = None; continue
            if src[i] == "\\":
                i += 2; continue
            i += 1; continue
        if src[i] == "#":
            j = i
            while j < n and src[j] == "#": j += 1
            if j < n and src[j] == '"':
                q = '"""' if src.startswith('"""', j) else '"'
                close = q + "#" * (j - i)
                k = src.find(close, j + len(q)); i = n if k < 0 else k + len(close); continue
        if src.startswith('"""', i):
            in_str = '"""'; i += 3; continue
        if src[i] == '"':
            in_str = '"'; i += 1; continue
        if src.startswith("//", i):
            j = src.find("\n", i); j = n if j < 0 else j
            for k in range(i, j): out[k] = " "
            i = j; continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2); j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n": out[k] = " "
            i = j; continue
        i += 1
    return "".join(out)


def url_host(authority: str) -> str:
    """Host of a URL authority: user info and port removed, lower case."""
    host = authority.rsplit("@", 1)[-1]
    if host.startswith("["):
        return host[: host.find("]") + 1].lower()
    return host.split(":", 1)[0].lower()


def is_credential(name: str) -> bool:
    base = PurePosixPath(name).name
    return any(fnmatch.fnmatch(base.lower(), p.lower()) for p in CREDENTIAL_PATTERNS)


# ---------------------------------------------------------------- DUG-96 / DUG-44: native entry point

def check_native_entry(repo: Path, rep: Report) -> None:
    sources = sorted(p for d in NATIVE_DIRS for p in (repo / d).rglob("*.swift"))
    if not sources:
        rep.fail("DUG-96", NATIVE_DIR, "no Swift sources found — cannot tell what the app opens")
        return
    loopback_entry = serves_bundle = False
    for src in sources:
        raw = src.read_text(encoding="utf-8")
        code = strip_swift_comments(raw)
        rel = src.relative_to(repo)
        for m in re.finditer(r"\b(https?|wss?)://([^/\s\"?#]*)", code, re.I):
            if "@" in m.group(2):
                rep.fail("DUG-96", f"{rel}:{line_of(code, m.start())}", f"user info in a URL in the app's code: {m.group(0)}")
        for m in SCHEME_PIECE_RE.finditer(code):
            rep.fail("DUG-96", f"{rel}:{line_of(code, m.start())}", f"a URL assembled from pieces in the app's code: {m.group(0)}")
        for m in URL_RE.finditer(code):
            host = url_host(m.group(2))
            if host not in LOOPBACK:
                what = f"outside address in the app's code: {m.group(0)}" if host and not host.startswith("\\(") \
                    else f"a URL whose host is assembled at run time: {m.group(0)}"
                rep.fail("DUG-96", f"{rel}:{line_of(code, m.start())}", what)
        for api in NATIVE_FORBIDDEN_APIS:
            for m in re.finditer(re.escape(api) if not api.isidentifier() else rf"\b{api}\b", code):
                rep.fail("DUG-44", f"{rel}:{line_of(code, m.start())}",
                         f"{api} in the app's code — the app opens only the loopback server's shipped files")
        if re.search(r'"https?://(127\.0\.0\.1|localhost):\\\(\w+\)/(index\.html)?"', code):
            loopback_entry = True
        if re.search(r"LocalHTTPServer\(\s*docRoot:\s*Bundle\.main\.resourceURL\b", code):
            serves_bundle = True
    if not loopback_entry:
        rep.fail("DUG-96", NATIVE_DIR, "the web view does not open the loopback index.html")
    if not serves_bundle:
        rep.fail("DUG-44", NATIVE_DIR, "the loopback server does not serve from the app bundle (Bundle.main.resourceURL)")
    plist = repo / NATIVE_DIR / "Info.plist"
    if plist.exists():
        check_plist_urls(plist.read_bytes(), str(plist.relative_to(repo)), rep, source=True)


def check_plist_urls(data: bytes, where: str, rep: Report, source: bool = False) -> None:
    try:
        info = plistlib.loads(data)
    except Exception as exc:  # noqa: BLE001
        if source:   # the source plist may hold build-setting placeholders; plistlib still reads it
            rep.fail("DUG-96", where, f"unreadable: {exc}")
        return

    def walk(v, path):
        if isinstance(v, dict):
            for k, x in v.items(): walk(x, f"{path}.{k}")
        elif isinstance(v, list):
            for i, x in enumerate(v): walk(x, f"{path}[{i}]")
        elif isinstance(v, str):
            for m in URL_RE.finditer(v):
                if url_host(m.group(2)) not in LOOPBACK:
                    rep.fail("DUG-96", f"{where} {path.lstrip('.')}", f"outside address in the app's settings: {m.group(0)}")
    walk(info, "")


# ---------------------------------------------------------------- DUG-96: web entry point and scripts

def outside_refs(text: str) -> list[tuple[int, str, str]]:
    """(offset, snippet, scanned text) of every outside address a page or stylesheet could fetch."""
    clean = W3C_NS_RE.sub(lambda m: " " * len(m.group(0)), html.unescape(W3C_NAMESPACE_RE.sub(lambda m: " " * len(m.group(0)), text)))
    hits = [(m.start(), m.group(0)) for m in SCHEME_RE.finditer(clean)]
    hits += [(m.start(), f"URL assembled from pieces: {m.group(0)}") for m in SCHEME_PIECE_RE.finditer(clean)]
    hits += [(m.start(), clean[m.start():m.start() + 40].split()[0] if clean[m.start():].strip() else "//")
             for m in PROTOCOL_RELATIVE_RE.finditer(clean)]
    hits += [(m.start(), "<base href>") for m in BASE_RE.finditer(clean)]
    hits += [(m.start(), "refresh redirect") for m in REFRESH_RE.finditer(clean)]
    return [(off, snippet, clean) for off, snippet in sorted(set(hits))]


def check_web_entry(entry_text: str, entry_label: str, exists, rep: Report) -> None:
    for off, snippet, clean in outside_refs(entry_text):
        rep.fail("DUG-96", f"{entry_label}:{line_of(clean, off)}", f"outside address in the entry point: {snippet}")
    for m in ASSET_RE.finditer(entry_text):
        ref = html.unescape(m.group(3)).split("#")[0].split("?")[0]
        if not ref or SCHEME_RE.match(ref) or ref.startswith(("//", "\\")) or ref.startswith("data:"):
            continue          # outside addresses are reported above; data: URIs carry their bytes
        if not exists(ref.lstrip("./")):
            rep.fail("DUG-96", f"{entry_label}:{line_of(entry_text, m.start())}",
                     f"{m.group(1)} {m.group(2)}=\"{ref}\" is not a file that ships")


def check_stylesheets(files: dict[str, bytes], rep: Report, where: str) -> None:
    for name, data in files.items():
        if PurePosixPath(name).suffix.lower() != ".css":
            continue
        text = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), decode(data), flags=re.S)   # comments are not fetched
        text = re.sub(r"\\([0-9a-fA-F]{1,6})[ \t]?", lambda m: chr(min(int(m.group(1), 16), 0x10FFFF)) if int(m.group(1), 16) != 10 else " ", text)   # CSS escapes: \68ttps is https
        for off, snippet, clean in outside_refs(text):
            rep.fail("DUG-96", f"{where}{name}:{line_of(clean, off)}", f"outside address in a stylesheet: {snippet}")


def check_scripts(files: dict[str, bytes], rep: Report, where: str) -> None:
    """js/ (our own code; vendor/ is third-party and is covered by the MODEL_URL rule)."""
    for name, data in files.items():
        if not name.startswith("js/") or PurePosixPath(name).suffix.lower() not in (".js", ".mjs"):
            continue
        text = W3C_NS_RE.sub(lambda m: " " * len(m.group(0)), decode(data).replace("\\/", "/"))   # "https:\/\/host" is "https://host"
        for m in SCHEME_PIECE_RE.finditer(text):
            rep.fail("DUG-96", f"{where}{name}:{line_of(text, m.start())}", f"a URL assembled from pieces in a shipped script: {m.group(0)}")
        for m in DETECTOR_RE.finditer(text):
            if not re.search(r"\bmodelUrl\s*:\s*CFG\.MODEL_URL\b", m.group(0)):
                rep.fail("DUG-96", f"{where}{name}:{line_of(text, m.start())}", "createDetector without modelUrl: CFG.MODEL_URL — the detector would fetch its model from the internet")
        for m in URL_RE.finditer(text):
            if url_host(m.group(2)) in LOOPBACK or (name, url_host(m.group(2))) in SCRIPT_ALLOWED:
                continue
            rep.fail("DUG-96", f"{where}{name}:{line_of(text, m.start())}", f"outside address in a shipped script: {m.group(0)}")
        for m in PROTOCOL_RELATIVE_RE.finditer(text):
            if text[m.start() - 1:m.start()] in ("'", '"', "`", "(", "}"):     # a string, not a // comment
                rep.fail("DUG-96", f"{where}{name}:{line_of(text, m.start())}", "protocol-relative address in a shipped script")
    cfg = files.get(CONFIG_JS)
    if cfg is None:
        rep.fail("DUG-96", where + CONFIG_JS, "missing — cannot tell where the pose model loads from")
        return
    m = MODEL_URL_RE.search(decode(cfg))
    model = m.group(2) if m else ""
    if not model or SCHEME_RE.match(model) or model.startswith(("//", "\\")) or model.lstrip("./") not in files:
        rep.fail("DUG-96", where + CONFIG_JS, f"MODEL_URL {model!r} is not a file that ships — the pose detector "
                                              "would fetch its model from the internet")


# ---------------------------------------------------------------- DUG-153: debug is off

def check_debug_off(files: dict[str, bytes], rep: Report, where: str) -> None:
    cfg = files.get(CONFIG_JS)
    if cfg is None:
        rep.fail("DUG-153", where + CONFIG_JS, "missing — cannot tell whether debug is off")
        return
    text = decode(cfg)
    values = DEBUG_RE.findall(text)
    if values != ["false"]:
        found = ", ".join(values) if values else "no DEBUG setting"
        rep.fail("DUG-153", where + CONFIG_JS, f"DEBUG must be exactly false in a build that leaves the Mac (found: {found}) — "
                                              "on, it logs detector confidences (R-13)")


# ---------------------------------------------------------------- DUG-97: SharePoint marks

def check_sharepoint(files: dict[str, bytes], rep: Report, where: str) -> None:
    for name, data in files.items():
        suffix = PurePosixPath(name).suffix.lower()
        if suffix not in TEXT_SUFFIXES:
            continue
        text = decode(data)
        for mark in SHAREPOINT_MARKS:
            for m in re.finditer(re.escape(mark), text, re.IGNORECASE):
                rep.fail("DUG-97", f"{where}{name}:{line_of(text, m.start())}", f"SharePoint mark: {mark}")
        if suffix in PAGE_SUFFIXES:
            head = HEAD_RE.search(text)
            title = TITLE_RE.search(head.group(1)) if head else None
            if not title:
                rep.fail("DUG-97", f"{where}{name}", "no <title> in <head> — SharePoint blanks or strips it")
            elif not re.sub(r"<!--.*?-->", "", html.unescape(title.group(1)), flags=re.DOTALL).strip(" \t\r\n" + INVISIBLE):
                rep.fail("DUG-97", f"{where}{name}", "blank <title> in <head> — the SharePoint signature")


# ---------------------------------------------------------------- what ships

def git(repo: Path, *args: str) -> list[str]:
    out = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"FAIL [DUG-44] {repo}: git {' '.join(args)} failed — the checks need a git checkout\n{out.stderr}")
    return [l for l in out.stdout.split("\0" if "-z" in args else "\n") if l]


def tracked_shipped(repo: Path) -> list[str]:
    return sorted(git(repo, "ls-files", "-z", "--", *SHIPPED))


def repo_shipped_files(repo: Path) -> dict[str, bytes]:
    """Every tracked file the app bundles, as it is on disk now (what Xcode will copy)."""
    return {name: (repo / name).read_bytes() for name in tracked_shipped(repo) if (repo / name).is_file()}


def check_secrets(files: dict[str, bytes], rep: Report, where: str) -> None:
    for name, data in files.items():
        if SECRET_RE.search(data):
            rep.fail("DUG-44", where + name, "secret-like content (API key or private key) in a shipped file")


def macho_without_signature(data: bytes) -> bytes:
    """A thin 64-bit Mach-O up to its code signature (the signature's certificates name Apple's CRL/OCSP hosts)."""
    import struct
    try:
        ncmds, off = struct.unpack_from("<I", data, 16)[0], 32
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", data, off)
            if cmd == 0x1D:                               # LC_CODE_SIGNATURE
                return data[:struct.unpack_from("<I", data, off + 8)[0]]
            off += size
    except struct.error:
        pass
    return data


def check_binaries(shipped: dict[str, bytes], rep: Report, where: str) -> None:
    for name, data in shipped.items():
        if data[:4] == b"\xca\xfe\xba\xbe":
            rep.fail("DUG-96", where + name, "a fat binary — the URL scan reads thin arm64 only")
        if data[:4] == b"\xcf\xfa\xed\xfe":
            data = macho_without_signature(data)
            for m in BINARY_URL_RE.finditer(data):
                if url_host(m.group(1).decode("latin-1")) not in LOOPBACK:
                    rep.fail("DUG-96", where + name, f"outside address compiled into the app: {m.group(0).decode('latin-1')}")


def commit_shipped_files(repo: Path, commit: str) -> dict[str, bytes]:
    """Every file the app bundles, as the commit has it (not as the working tree has it now)."""
    out = {}
    for name in git(repo, "ls-tree", "-r", "-z", "--name-only", commit, "--", *SHIPPED):
        r = subprocess.run(["git", "-C", str(repo), "cat-file", "blob", f"{commit}:{name}"], capture_output=True)
        if r.returncode != 0:
            raise SystemExit(f"FAIL [DUG-44] {name}: cannot read it from {commit}")
        out[name] = r.stdout
    return out


def check_untracked(repo: Path, rep: Report) -> None:
    """Files on disk in a bundled folder that the commit does not have — ignored ones included."""
    for name in sorted(git(repo, "ls-files", "-z", "--others", "--", *SHIPPED)):
        if PurePosixPath(name).name in IGNORED_EXTRAS:
            continue
        rep.fail("DUG-44", name, "not in the commit, but inside a folder the app bundles — it would ship"
                                 + (" (and it looks like a credential)" if is_credential(name) else ""))


def check_project_resources(repo: Path, rep: Report) -> None:
    pbx = (repo / PBXPROJ).read_text(encoding="utf-8")
    bundled = None
    for phase in re.finditer(r"isa = PBXResourcesBuildPhase;.*?files = \((.*?)\);", pbx, re.DOTALL):
        names = re.findall(r"/\* (.+?) in Resources \*/", phase.group(1))
        if "index.html" in names:
            bundled = sorted(n for n in names if n != "Assets.xcassets")
    if bundled is None:
        rep.fail("DUG-44", PBXPROJ, "no Resources phase bundles index.html — cannot tell what the app ships")
    elif bundled != sorted(SHIPPED):
        rep.fail("DUG-44", PBXPROJ, f"the app bundles {bundled}, but these checks cover {sorted(SHIPPED)} — "
                                    "update SHIPPED in scripts/ship_checks.py")
    compiled = {p.name for d in NATIVE_DIRS for p in (repo / d).rglob("*.swift")}
    for phase in re.finditer(r"isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);", pbx, re.DOTALL):
        for name in re.findall(r"/\* (.+?) in Sources \*/", phase.group(1)):
            if name not in compiled:
                rep.fail("DUG-44", PBXPROJ, f"the app compiles {name}, which is outside {NATIVE_DIRS} — extend the checks first")
    for m in re.finditer(r"isa = XCSwiftPackageProductDependency;\s*(?:package = \w+[^;]*;\s*)?productName = \"?([\w-]+)\"?;", pbx):
        if f"ios/{m.group(1)}/Sources/{m.group(1)}" not in NATIVE_DIRS:
            rep.fail("DUG-44", PBXPROJ, f"the app links the package {m.group(1)}, whose Swift these checks do not read — add it to NATIVE_DIRS")
    for m in re.finditer(r"isa = (PBXCopyFilesBuildPhase|PBXShellScriptBuildPhase);", pbx):
        rep.fail("DUG-44", PBXPROJ, f"a {m.group(1)} could put unchecked files in the app — extend the checks first")


def run_source(repo: Path) -> Report:
    rep = Report()
    for item in SHIPPED:
        if not (repo / item).exists():
            rep.fail("DUG-44", item, "a file the app bundles is missing from the repo")
    check_project_resources(repo, rep)
    check_untracked(repo, rep)
    files = repo_shipped_files(repo)
    for name in files:
        if is_credential(name):
            rep.fail("DUG-44", name, "a credential-like file is committed inside a folder the app bundles")
    check_native_entry(repo, rep)
    if ENTRY in files:
        check_web_entry(decode(files[ENTRY]), ENTRY, lambda r: r in files, rep)
    check_stylesheets(files, rep, "")
    check_scripts(files, rep, "")
    check_debug_off(files, rep, "")
    native = {p.relative_to(repo).as_posix(): p.read_bytes() for d in NATIVE_DIRS for p in sorted((repo / d).rglob("*"))
              if p.is_file() and p.suffix in (".swift", ".plist", ".strings")}
    check_sharepoint({**files, **native}, rep, "")
    check_secrets({**files, **native}, rep, "")
    return rep


def run_ipa(repo: Path, ipa: Path, bundle_id: str, build: str, commit: str | None = None) -> Report:
    rep = Report()
    with zipfile.ZipFile(ipa) as z:
        apps = sorted({n.split("/")[1] for n in z.namelist() if n.startswith("Payload/") and n.split("/")[1].endswith(".app")})
        if len(apps) != 1:
            rep.fail("DUG-63", str(ipa), f"expected one app in Payload/, found {apps}")
            return rep
        root = f"Payload/{apps[0]}/"
        shipped = {n[len(root):]: z.read(n) for n in z.namelist() if n.startswith(root) and not n.endswith("/")}
    where = f"{ipa.name}!{apps[0]}/"

    # DUG-44: exactly the commit's web files, untouched; nothing credential-like anywhere
    repo_files = commit_shipped_files(repo, commit) if commit else repo_shipped_files(repo)
    for name, data in repo_files.items():
        if name not in shipped:
            rep.fail("DUG-44", where + name, "missing from the app")
        elif hashlib.sha256(shipped[name]).digest() != hashlib.sha256(data).digest():
            rep.fail("DUG-44", where + name, "differs from the repo — the build changed a shipped file")
    for name in sorted(shipped):
        top = name.split("/")[0]
        if top in SHIPPED and name not in repo_files and PurePosixPath(name).name not in IGNORED_EXTRAS:
            rep.fail("DUG-44", where + name, "in the app but not in the commit")
        if is_credential(name) and name != "embedded.mobileprovision":
            rep.fail("DUG-44", where + name, "a credential-like file is inside the app")

    # DUG-96 / DUG-97 over the whole bundle, not only the web folders
    if ENTRY in shipped:
        check_web_entry(decode(shipped[ENTRY]), where + ENTRY, lambda r: r in shipped, rep)
    else:
        rep.fail("DUG-96", where + ENTRY, "the entry point is not inside the app")
    for name, data in shipped.items():
        if name != ENTRY and PurePosixPath(name).suffix.lower() in PAGE_SUFFIXES:
            for off, snippet, clean in outside_refs(decode(data)):
                rep.fail("DUG-96", f"{where}{name}:{line_of(clean, off)}", f"outside address in a page the server serves: {snippet}")
    check_stylesheets(shipped, rep, where)
    check_scripts(shipped, rep, where)
    check_debug_off(shipped, rep, where)
    check_sharepoint({n: d for n, d in shipped.items() if n != "Info.plist"}, rep, where)
    check_secrets(shipped, rep, where)
    check_binaries(shipped, rep, where)

    # packaging: what App Store Connect will read
    try:
        info = plistlib.loads(shipped["Info.plist"])
    except Exception as exc:  # noqa: BLE001 — any unreadable plist is a failed build
        rep.fail("DUG-63", where + "Info.plist", f"unreadable: {exc}")
        return rep
    check_plist_urls(shipped["Info.plist"], where + "Info.plist", rep)
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
    i.add_argument("--commit", help="compare with this commit instead of the working tree (real runs)")
    args = ap.parse_args(argv)

    repo = args.repo.resolve()
    rep = run_source(repo) if args.mode == "source" else run_ipa(repo, args.ipa.resolve(), args.bundle_id, args.build, args.commit)
    label = "source" if args.mode == "source" else args.ipa.name
    for f in rep.failures:
        print(f)
    if rep.failures:
        print(f"ship checks FAILED on {label}: {len(rep.failures)} finding(s) — the build stops here.")
        return 1
    print(f"ship checks passed on {label}: entry point is local (DUG-96), no SharePoint marks (DUG-97), debug off (DUG-153), "
          f"only the commit's web files ship{' unchanged' if args.mode == 'ipa' else ''} (DUG-44).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
