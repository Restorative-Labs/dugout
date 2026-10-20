#!/usr/bin/env python3
"""Tests for scripts/ship_checks.py: the real tree passes, and every planted violation fails.

    python3 scripts/test_ship_checks.py

Each test copies the shipped files and the iOS sources into a temporary folder, plants one
problem, and runs the same checks the TestFlight lane runs. Standard library only.
"""
from __future__ import annotations

import io
import plistlib
import shutil
import sys
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
import ship_checks  # noqa: E402

BUNDLE_ID = "com.restorativelabs.dugout-ios"


def run(mode: str, *args: str) -> tuple[int, str]:
    out = io.StringIO()
    with redirect_stdout(out):
        code = ship_checks.main([mode, *args])
    return code, out.getvalue()


class ShipChecks(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="ship-checks-"))
        for item in ship_checks.SHIPPED:
            src = REPO / item
            (shutil.copytree if src.is_dir() else shutil.copy2)(src, self.tmp / item)
        shutil.copytree(REPO / "ios" / "DugOut", self.tmp / "ios" / "DugOut")
        (self.tmp / "ios" / "DugOut.xcodeproj").mkdir(parents=True)
        shutil.copy2(REPO / ship_checks.PBXPROJ, self.tmp / ship_checks.PBXPROJ)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp)

    # helpers
    def edit(self, rel: str, old: str, new: str) -> None:
        p = self.tmp / rel
        text = p.read_text(encoding="utf-8")
        self.assertIn(old, text, f"test setup: {old!r} not in {rel}")
        p.write_text(text.replace(old, new, 1), encoding="utf-8")

    def assert_fails(self, rule: str, needle: str, mode: str = "source", *args: str) -> str:
        code, out = run(mode, str(self.tmp), *args)
        self.assertEqual(code, 1, f"expected the build to stop; output:\n{out}")
        self.assertTrue(any(l.startswith(f"FAIL [{rule}]") and needle in l for l in out.splitlines()),
                        f"expected a [{rule}] finding mentioning {needle!r}; output:\n{out}")
        return out

    def make_ipa(self, build: str = "7", info_extra: dict | None = None, tamper=None) -> Path:
        info = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleVersion": build, "CFBundleShortVersionString": "1.0",
                "ITSAppUsesNonExemptEncryption": False}
        info.update(info_extra or {})
        ipa = self.tmp / "DugOut.ipa"
        with zipfile.ZipFile(ipa, "w") as z:
            z.writestr("Payload/DugOut.app/Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            z.writestr("Payload/DugOut.app/DugOut", b"\xcf\xfa\xed\xfe binary")
            for name, data in ship_checks.repo_shipped_files(self.tmp).items():
                if tamper:
                    data = tamper(name, data)
                    if data is None:
                        continue
                z.writestr(f"Payload/DugOut.app/{name}", data)
        return ipa

    # ---------------------------------------------------------------- the real tree

    def test_real_tree_passes(self) -> None:
        code, out = run("source", str(REPO))
        self.assertEqual(code, 0, out)

    def test_copy_passes_before_planting(self) -> None:
        code, out = run("source", str(self.tmp))
        self.assertEqual(code, 0, out)

    # ---------------------------------------------------------------- DUG-96: web entry point

    def test_planted_outside_script(self) -> None:
        self.edit("index.html", "</head>", '<script src="https://cdn.example.com/app.js"></script>\n</head>')
        self.assert_fails("DUG-96", "https:")

    def test_planted_protocol_relative_stylesheet(self) -> None:
        self.edit("index.html", "</head>", '<link rel="stylesheet" href="//cdn.example.com/a.css">\n</head>')
        self.assert_fails("DUG-96", "//")

    def test_planted_base_href(self) -> None:
        self.edit("index.html", "</head>", '<base href="/">\n</head>')
        self.assert_fails("DUG-96", "<base href>")

    def test_planted_refresh_redirect(self) -> None:
        self.edit("index.html", "</head>", '<meta http-equiv="refresh" content="0; url=/x">\n</head>')
        self.assert_fails("DUG-96", "refresh redirect")

    def test_svg_namespace_is_not_an_outside_address(self) -> None:
        self.edit("index.html", "</body>",
                  '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"></svg>\n</body>')
        code, out = run("source", str(self.tmp))
        self.assertEqual(code, 0, out)

    def test_planted_script_that_does_not_ship(self) -> None:
        self.edit("index.html", "</head>", '<script src="js/not-there.js"></script>\n</head>')
        self.assert_fails("DUG-96", "not a file that ships")

    def test_planted_outside_font_in_stylesheet(self) -> None:
        css = sorted((self.tmp / "css").glob("*.css"))[0]
        css.write_text(css.read_text(encoding="utf-8") + "\n@font-face{src:url(https://fonts.example.com/x.woff2)}\n",
                       encoding="utf-8")
        self.assert_fails("DUG-96", "stylesheet")

    # ---------------------------------------------------------------- DUG-96 / DUG-44: native entry point

    def test_planted_outside_entry_url_in_the_app(self) -> None:
        self.edit("ios/DugOut/ViewController.swift", 'URL(string: "http://127.0.0.1:\\(port)/index.html")',
                  'URL(string: "https://dugout.example.com/index.html")')
        out = self.assert_fails("DUG-96", "https://dugout.example.com")
        self.assertIn("does not open the loopback index.html", out)

    def test_planted_network_fetch_in_the_app(self) -> None:
        self.edit("ios/DugOut/ViewController.swift", "override func viewDidLoad() {",
                  "override func viewDidLoad() {\n        _ = URLSession.shared")
        self.assert_fails("DUG-44", "URLSession")

    def test_server_must_serve_from_the_bundle(self) -> None:
        self.edit("ios/DugOut/ViewController.swift", "LocalHTTPServer(docRoot: Bundle.main.resourceURL!)",
                  "LocalHTTPServer(docRoot: FileManager.default.temporaryDirectory)")
        self.assert_fails("DUG-44", "app bundle")

    def test_project_bundling_a_file_the_checks_do_not_cover(self) -> None:
        self.edit(ship_checks.PBXPROJ, "/* swing-shadow.mp4 in Resources */,",
                  "/* swing-shadow.mp4 in Resources */,\n\t\t\t\tD0600000000000000000FFFF /* extra in Resources */,")
        self.assert_fails("DUG-44", "update SHIPPED")

    # ---------------------------------------------------------------- DUG-97: SharePoint marks

    def test_planted_mso_namespace(self) -> None:
        self.edit("index.html", "<html", '<html xmlns:mso="urn:schemas-microsoft-com:office:office"')
        self.assert_fails("DUG-97", "xmlns:mso")

    def test_planted_custom_document_properties(self) -> None:
        self.edit("index.html", "</head>", "<!--[if gte mso 9]><xml><mso:CustomDocumentProperties>"
                                           "</mso:CustomDocumentProperties></xml><![endif]-->\n</head>")
        self.assert_fails("DUG-97", "CustomDocumentProperties")

    def test_planted_blank_title(self) -> None:
        text = (self.tmp / "index.html").read_text(encoding="utf-8")
        title = ship_checks.TITLE_RE.search(text).group(0)
        self.edit("index.html", title, "<title> </title>")
        self.assert_fails("DUG-97", "blank <title>")

    def test_planted_missing_title(self) -> None:
        text = (self.tmp / "index.html").read_text(encoding="utf-8")
        self.edit("index.html", ship_checks.TITLE_RE.search(text).group(0), "")
        self.assert_fails("DUG-97", "no <title>")

    def test_planted_mark_in_a_script(self) -> None:
        js = sorted((self.tmp / "js").glob("*.js"))[0]
        js.write_text(js.read_text(encoding="utf-8") + "\n// CustomDocumentProperties\n", encoding="utf-8")
        self.assert_fails("DUG-97", js.name)

    # ---------------------------------------------------------------- the .ipa: what actually ships

    def test_clean_ipa_passes(self) -> None:
        ipa = self.make_ipa()
        code, out = run("ipa", str(self.tmp), str(ipa), "--bundle-id", BUNDLE_ID, "--build", "7")
        self.assertEqual(code, 0, out)

    def test_ipa_with_a_changed_web_file(self) -> None:
        ipa = self.make_ipa(tamper=lambda n, d: d + b"\n/* minified */" if n.endswith(".js") else d)
        self.assert_fails("DUG-44", "differs from the repo", "ipa", str(ipa), "--bundle-id", BUNDLE_ID, "--build", "7")

    def test_ipa_missing_a_web_file(self) -> None:
        ipa = self.make_ipa(tamper=lambda n, d: None if n == "shadow-sprite.jpg" else d)
        self.assert_fails("DUG-44", "missing from the app", "ipa", str(ipa), "--bundle-id", BUNDLE_ID, "--build", "7")

    def test_ipa_with_an_outside_address_in_the_entry_point(self) -> None:
        ipa = self.make_ipa(tamper=lambda n, d: d.replace(b"</head>", b'<script src="https://x.example/a.js"></script></head>')
                            if n == "index.html" else d)
        out = self.assert_fails("DUG-96", "https:", "ipa", str(ipa), "--bundle-id", BUNDLE_ID, "--build", "7")
        self.assertIn("differs from the repo", out)

    def test_ipa_wrong_build_number(self) -> None:
        ipa = self.make_ipa(build="6")
        self.assert_fails("DUG-63", "build number", "ipa", str(ipa), "--bundle-id", BUNDLE_ID, "--build", "7")

    def test_ipa_wrong_bundle_id(self) -> None:
        ipa = self.make_ipa(info_extra={"CFBundleIdentifier": "com.restorativelabs.dugout"})
        self.assert_fails("DUG-63", "bundle id", "ipa", str(ipa), "--bundle-id", BUNDLE_ID, "--build", "7")

    def test_ipa_without_the_encryption_answer(self) -> None:
        ipa = self.make_ipa(info_extra={"ITSAppUsesNonExemptEncryption": True})
        self.assert_fails("DUG-63", "ITSAppUsesNonExemptEncryption", "ipa", str(ipa), "--bundle-id", BUNDLE_ID, "--build", "7")


if __name__ == "__main__":
    unittest.main(verbosity=2)
