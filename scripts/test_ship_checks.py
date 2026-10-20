#!/usr/bin/env python3
"""Tests for scripts/ship_checks.py: the real tree passes, and every planted violation fails.

    python3 -I scripts/test_ship_checks.py

Each test copies the shipped files, the iOS sources and .gitignore into a temporary git
checkout, plants one problem, and runs the same checks the TestFlight lane runs. The plants
include every bypass the DUG-63 pre-flight review proved. Standard library only.
"""
from __future__ import annotations

import io
import plistlib
import shutil
import subprocess
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
VC = "ios/DugOut/ViewController.swift"
ENTRY_URL = 'URL(string: "http://127.0.0.1:\\(port)/index.html")'


def run(mode: str, *args: str) -> tuple[int, str]:
    out = io.StringIO()
    with redirect_stdout(out):
        code = ship_checks.main([mode, *args])
    return code, out.getvalue()


def git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(cwd), "-c", "user.name=ship-checks-test", "-c", "user.email=test@invalid", *args],
                   check=True, capture_output=True)


class ShipChecks(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="ship-checks-"))
        for rel in subprocess.run(["git", "-C", str(REPO), "ls-files", "-z", "--", *ship_checks.SHIPPED, "ios/DugOut",
                                   ship_checks.PBXPROJ, ".gitignore"], capture_output=True, text=True, check=True
                                  ).stdout.split("\0"):
            if rel:
                (self.tmp / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(REPO / rel, self.tmp / rel)
        git(self.tmp, "init", "-q")
        git(self.tmp, "add", "-A")
        git(self.tmp, "commit", "-q", "-m", "fixture")

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp)

    # helpers
    def read(self, rel: str) -> str:
        return (self.tmp / rel).read_text(encoding="utf-8")

    def write(self, rel: str, text: str | bytes) -> None:
        p = self.tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        (p.write_bytes if isinstance(text, bytes) else lambda t: p.write_text(t, encoding="utf-8"))(text)

    def edit(self, rel: str, old: str, new: str) -> None:
        text = self.read(rel)
        self.assertIn(old, text, f"test setup: {old!r} not in {rel}")
        self.write(rel, text.replace(old, new, 1))

    def head(self, extra: str) -> None:
        self.edit("index.html", "</head>", extra + "\n</head>")

    def passes(self, mode: str = "source", *args: str) -> None:
        code, out = run(mode, str(self.tmp), *args)
        self.assertEqual(code, 0, f"expected the checks to pass; output:\n{out}")

    def assert_fails(self, rule: str, needle: str, mode: str = "source", *args: str) -> str:
        code, out = run(mode, str(self.tmp), *args)
        self.assertEqual(code, 1, f"expected the build to stop; output:\n{out}")
        self.assertTrue(any(l.startswith(f"FAIL [{rule}]") and needle in l for l in out.splitlines()),
                        f"expected a [{rule}] finding mentioning {needle!r}; output:\n{out}")
        return out

    def make_ipa(self, build: str = "7", info_extra: dict | None = None, tamper=None, extra: dict | None = None) -> Path:
        info = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleVersion": build, "CFBundleShortVersionString": "1.0",
                "ITSAppUsesNonExemptEncryption": False}
        info.update(info_extra or {})
        ipa = self.tmp / "DugOut.ipa"
        with zipfile.ZipFile(ipa, "w") as z:
            z.writestr("Payload/DugOut.app/Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            z.writestr("Payload/DugOut.app/DugOut", b"\xcf\xfa\xed\xfe binary")
            z.writestr("Payload/DugOut.app/embedded.mobileprovision", b"profile")
            for name, data in ship_checks.repo_shipped_files(self.tmp).items():
                if tamper:
                    data = tamper(name, data)
                    if data is None:
                        continue
                z.writestr(f"Payload/DugOut.app/{name}", data)
            for name, data in (extra or {}).items():
                z.writestr(f"Payload/DugOut.app/{name}", data)
        return ipa

    def ipa_args(self, ipa: Path, build: str = "7") -> tuple[str, ...]:
        return ("ipa", str(ipa), "--bundle-id", BUNDLE_ID, "--build", build)

    # ---------------------------------------------------------------- the real tree

    def test_real_tree_passes(self) -> None:
        code, out = run("source", str(REPO))
        self.assertEqual(code, 0, out)

    def test_copy_passes_before_planting(self) -> None:
        self.passes()

    # ---------------------------------------------------------------- DUG-96: the web entry point

    def test_planted_cdn_script(self) -> None:
        self.head('<script src="https://cdn.example.com/app.js"></script>')
        self.assert_fails("DUG-96", "https:")

    def test_planted_google_fonts_preconnect_uppercase(self) -> None:
        self.head('<LINK REL="preconnect" HREF="HTTPS://fonts.googleapis.com">')
        self.assert_fails("DUG-96", "HTTPS:")

    def test_planted_protocol_relative_stylesheet(self) -> None:
        self.head('<link rel="stylesheet" href="//cdn.example.com/a.css">')
        self.assert_fails("DUG-96", "//cdn.example.com")

    def test_planted_srcset_second_candidate(self) -> None:
        self.edit("index.html", "</body>", '<img srcset="shadow-sprite.jpg 1x, //cdn.example.com/b.png 2x">\n</body>')
        self.assert_fails("DUG-96", "//cdn.example.com")

    def test_planted_inline_fetch_protocol_relative(self) -> None:
        self.edit("index.html", "</body>", '<script>fetch("//api.example.com/v1")</script>\n</body>')
        self.assert_fails("DUG-96", "//api.example.com")

    def test_planted_entity_encoded_scheme(self) -> None:
        self.head('<script src="&#104;ttps&colon;//cdn.example.com/a.js"></script>')
        self.assert_fails("DUG-96", "https")

    def test_planted_base_href(self) -> None:
        self.head('<base href="/">')
        self.assert_fails("DUG-96", "<base href>")

    def test_planted_refresh_redirect(self) -> None:
        self.head('<meta http-equiv="refresh" content="0; url=/x">')
        self.assert_fails("DUG-96", "refresh redirect")

    def test_w3c_svg_namespace_is_not_an_outside_address(self) -> None:
        self.edit("index.html", "</body>",
                  '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"></svg>\n</body>')
        self.passes()

    def test_a_variable_called_xmlns_does_not_hide_an_address(self) -> None:
        self.edit("index.html", "</body>", '<script>var xmlns="https://cdn.example.com/a.js"</script>\n</body>')
        self.assert_fails("DUG-96", "https:")

    def test_planted_script_that_does_not_ship(self) -> None:
        self.head('<script src="js/not-there.js"></script>')
        self.assert_fails("DUG-96", "not a file that ships")

    def test_planted_outside_font_in_stylesheet(self) -> None:
        css = sorted(p for p in (self.tmp / "css").glob("*.css"))[0].relative_to(self.tmp).as_posix()
        self.write(css, self.read(css) + "\n@font-face{src:url(https://fonts.example.com/x.woff2)}\n")
        self.assert_fails("DUG-96", "stylesheet")

    def test_planted_minified_import_and_image_set(self) -> None:
        css = sorted(p for p in (self.tmp / "css").glob("*.css"))[0].relative_to(self.tmp).as_posix()
        self.write(css, self.read(css) + '\n@import"//cdn.example.com/x.css";\n.a{background:image-set("//cdn.example.com/b.png" 1x)}\n')
        self.assert_fails("DUG-96", "//cdn.example.com")

    def test_planted_utf16_uppercase_stylesheet(self) -> None:
        self.write("css/EXTRA.CSS", "@import url(https://cdn.example.com/x.css);".encode("utf-16"))
        git(self.tmp, "add", "css/EXTRA.CSS")
        self.assert_fails("DUG-96", "EXTRA.CSS")

    # ---------------------------------------------------------------- DUG-96: scripts and the model

    def test_planted_outside_address_in_our_script(self) -> None:
        self.edit("js/app.js", "(function", "const FONTS = 'https://fonts.googleapis.com/css2';\n(function")
        self.assert_fails("DUG-96", "fonts.googleapis.com")

    def test_planted_protocol_relative_fetch_in_our_script(self) -> None:
        self.edit("js/app.js", "(function", "fetch('//cdn.example.com/model.json');\n(function")
        self.assert_fails("DUG-96", "protocol-relative")

    def test_ai_adapter_endpoint_is_the_one_allowed_address(self) -> None:
        self.assertIn("https://api.anthropic.com", self.read("js/ai.js"))
        self.passes()

    def test_ai_endpoint_elsewhere_is_not_allowed(self) -> None:
        self.edit("js/app.js", "(function", "const X = 'https://api.anthropic.com/v1/messages';\n(function")
        self.assert_fails("DUG-96", "js/app.js")

    def test_planted_remote_model(self) -> None:
        self.edit("js/config.js", "MODEL_URL: 'vendor/movenet/model.json'",
                  "MODEL_URL: 'https://tfhub.dev/google/tfjs-model/movenet/singlepose/lightning/4'")
        self.assert_fails("DUG-96", "MODEL_URL")

    def test_empty_model_url_falls_back_to_the_internet(self) -> None:
        self.edit("js/config.js", "MODEL_URL: 'vendor/movenet/model.json'", "MODEL_URL: ''")
        self.assert_fails("DUG-96", "MODEL_URL")

    # ---------------------------------------------------------------- DUG-96 / DUG-44: the native entry point

    def test_planted_outside_entry_url_in_the_app(self) -> None:
        self.edit(VC, ENTRY_URL, 'URL(string: "https://dugout.example.com/index.html")')
        out = self.assert_fails("DUG-96", "https://dugout.example.com")
        self.assertIn("does not open the loopback index.html", out)

    def test_loopback_root_is_an_acceptable_entry(self) -> None:
        self.edit(VC, ENTRY_URL, 'URL(string: "http://127.0.0.1:\\(port)/")')
        self.passes()

    def test_user_info_trick_is_an_outside_address(self) -> None:
        self.edit(VC, ENTRY_URL, 'URL(string: "http://localhost:8384@dugout.example.com/index.html")')
        self.assert_fails("DUG-96", "dugout.example.com")

    def test_host_assembled_at_run_time(self) -> None:
        self.edit(VC, "override func viewDidLoad() {", 'override func viewDidLoad() {\n        let h = "x"; _ = URL(string: "https://\\(h)/a")')
        self.assert_fails("DUG-96", "assembled at run time")

    def test_url_components(self) -> None:
        self.edit(VC, "override func viewDidLoad() {", "override func viewDidLoad() {\n        var c = URLComponents(); c.host = \"x\"")
        self.assert_fails("DUG-44", "URLComponents")

    def test_planted_network_fetch_in_a_subfolder(self) -> None:
        self.write("ios/DugOut/Updates/WebUpdater.swift",
                   'import Foundation\nfunc update() { URLSession.shared.dataTask(with: URL(string: "https://cdn.example.com/web.zip")!) { _, _, _ in }.resume() }\n')
        out = self.assert_fails("DUG-44", "URLSession")
        self.assertIn("cdn.example.com", out)

    def test_load_file_url(self) -> None:
        self.edit(VC, "override func viewDidLoad() {", "override func viewDidLoad() {\n        // offline copy\n        webView?.loadFileURL(u, allowingReadAccessTo: u)")
        self.assert_fails("DUG-44", "loadFileURL")

    def test_server_must_serve_from_the_bundle(self) -> None:
        self.edit(VC, "LocalHTTPServer(docRoot: Bundle.main.resourceURL!)",
                  "LocalHTTPServer(docRoot: FileManager.default.temporaryDirectory)")
        self.assert_fails("DUG-44", "app bundle")

    def test_comments_are_not_code(self) -> None:
        self.edit(VC, "override func viewDidLoad() {",
                  "// See https://developer.apple.com/documentation/webkit — and never use URLSession here.\n"
                  "    override func viewDidLoad() {")
        self.passes()

    def test_planted_start_url_in_info_plist(self) -> None:
        self.edit("ios/DugOut/Info.plist", "<key>LSRequiresIPhoneOS</key>",
                  "<key>DugOutStartURL</key>\n\t<string>https://staging.example.com/index.html</string>\n\t<key>LSRequiresIPhoneOS</key>")
        self.assert_fails("DUG-96", "DugOutStartURL")

    def test_project_bundling_a_file_the_checks_do_not_cover(self) -> None:
        self.edit(ship_checks.PBXPROJ, "/* swing-shadow.mp4 in Resources */,",
                  "/* swing-shadow.mp4 in Resources */,\n\t\t\t\tD0600000000000000000FFFF /* extra in Resources */,")
        self.assert_fails("DUG-44", "update SHIPPED")

    def test_project_copy_files_phase(self) -> None:
        self.edit(ship_checks.PBXPROJ, "/* Begin PBXResourcesBuildPhase section */",
                  "/* Begin PBXCopyFilesBuildPhase section */\n\t\tAAAA /* CopyFiles */ = {\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t};\n"
                  "/* End PBXCopyFilesBuildPhase section */\n\n/* Begin PBXResourcesBuildPhase section */")
        self.assert_fails("DUG-44", "PBXCopyFilesBuildPhase")

    # ---------------------------------------------------------------- DUG-44: only the commit ships

    def test_ignored_env_file_inside_js(self) -> None:
        self.write("js/.env", "ASC_KEY_ID=planted\n")
        self.assert_fails("DUG-44", "js/.env")

    def test_ignored_key_inside_vendor(self) -> None:
        self.write("vendor/AuthKey_PLANTED.p8", "-----BEGIN PRIVATE KEY-----\nplanted\n")
        self.assert_fails("DUG-44", "credential")

    def test_untracked_file_inside_css(self) -> None:
        self.write("css/notes.txt", "draft\n")
        self.assert_fails("DUG-44", "css/notes.txt")

    def test_ds_store_is_not_a_finding(self) -> None:
        self.write("css/.DS_Store", b"\x00\x00")
        self.passes()

    def test_committed_credential_inside_js(self) -> None:
        self.write("js/signing.p12", b"planted")
        git(self.tmp, "add", "-f", "js/signing.p12")
        self.assert_fails("DUG-44", "credential-like file is committed")

    # ---------------------------------------------------------------- DUG-97: SharePoint marks

    def test_planted_mso_namespace(self) -> None:
        self.edit("index.html", "<html", '<html xmlns:mso="urn:schemas-microsoft-com:office:office"')
        self.assert_fails("DUG-97", "xmlns:mso")

    def test_planted_custom_document_properties(self) -> None:
        self.head("<!--[if gte mso 9]><xml><mso:CustomDocumentProperties></mso:CustomDocumentProperties></xml><![endif]-->")
        self.assert_fails("DUG-97", "CustomDocumentProperties")

    def _head_title(self) -> str:
        return ship_checks.TITLE_RE.search(ship_checks.HEAD_RE.search(self.read("index.html")).group(1)).group(0)

    def test_planted_blank_title(self) -> None:
        self.edit("index.html", self._head_title(), "<title> </title>")
        self.assert_fails("DUG-97", "blank <title>")

    def test_planted_nbsp_title(self) -> None:
        self.edit("index.html", self._head_title(), "<title>&nbsp;​</title>")
        self.assert_fails("DUG-97", "blank <title>")

    def test_svg_title_does_not_mask_a_blank_head_title(self) -> None:
        self.edit("index.html", self._head_title(), "<title></title>")
        self.edit("index.html", "</body>", "<svg><title>Play</title></svg>\n</body>")
        self.assert_fails("DUG-97", "blank <title>")

    def test_planted_missing_title(self) -> None:
        self.edit("index.html", self._head_title(), "")
        self.assert_fails("DUG-97", "no <title>")

    def test_planted_mark_in_a_script(self) -> None:
        self.write("js/app.js", self.read("js/app.js") + "\n// CustomDocumentProperties\n")
        self.assert_fails("DUG-97", "js/app.js")

    def test_planted_mark_in_utf16_markdown(self) -> None:
        self.write("vendor/NOTES.md", "<o:CustomDocumentProperties/>".encode("utf-16"))
        git(self.tmp, "add", "vendor/NOTES.md")
        self.assert_fails("DUG-97", "vendor/NOTES.md")

    # ---------------------------------------------------------------- the .ipa: what actually ships

    def test_clean_ipa_passes(self) -> None:
        self.passes(*self.ipa_args(self.make_ipa()))

    def test_ipa_with_a_changed_web_file(self) -> None:
        ipa = self.make_ipa(tamper=lambda n, d: d + b"\n/* minified */" if n.endswith(".js") else d)
        self.assert_fails("DUG-44", "differs from the repo", *self.ipa_args(ipa))

    def test_ipa_missing_a_web_file(self) -> None:
        ipa = self.make_ipa(tamper=lambda n, d: None if n == "shadow-sprite.jpg" else d)
        self.assert_fails("DUG-44", "missing from the app", *self.ipa_args(ipa))

    def test_ipa_with_an_ignored_file_that_xcode_copied(self) -> None:
        ipa = self.make_ipa(extra={"js/.env": b"ASC_KEY_ID=planted\n"})
        self.assert_fails("DUG-44", "not in the commit", *self.ipa_args(ipa))

    def test_ipa_with_a_key_at_the_app_root(self) -> None:
        ipa = self.make_ipa(extra={"AuthKey_X.p8": b"planted"})
        self.assert_fails("DUG-44", "credential-like file is inside the app", *self.ipa_args(ipa))

    def test_ipa_with_an_outside_address_in_the_entry_point(self) -> None:
        ipa = self.make_ipa(tamper=lambda n, d: d.replace(b"</head>", b'<script src="https://x.example/a.js"></script></head>')
                            if n == "index.html" else d)
        out = self.assert_fails("DUG-96", "https:", *self.ipa_args(ipa))
        self.assertIn("differs from the repo", out)

    def test_ipa_with_an_extra_page_outside_the_web_folders(self) -> None:
        ipa = self.make_ipa(extra={"help.html": b'<html><head><title>Help</title><script src="https://cdn.example.com/a.js"></script></head></html>'})
        self.assert_fails("DUG-96", "help.html", *self.ipa_args(ipa))

    def test_ipa_with_a_start_url_in_its_info_plist(self) -> None:
        ipa = self.make_ipa(info_extra={"DugOutStartURL": "https://staging.example.com/"})
        self.assert_fails("DUG-96", "DugOutStartURL", *self.ipa_args(ipa))

    def test_ipa_wrong_build_number(self) -> None:
        self.assert_fails("DUG-63", "build number", *self.ipa_args(self.make_ipa(build="6")))

    def test_ipa_wrong_bundle_id(self) -> None:
        ipa = self.make_ipa(info_extra={"CFBundleIdentifier": "com.restorativelabs.dugout"})
        self.assert_fails("DUG-63", "bundle id", *self.ipa_args(ipa))

    def test_ipa_without_the_encryption_answer(self) -> None:
        ipa = self.make_ipa(info_extra={"ITSAppUsesNonExemptEncryption": True})
        self.assert_fails("DUG-63", "ITSAppUsesNonExemptEncryption", *self.ipa_args(ipa))


if __name__ == "__main__":
    unittest.main(verbosity=2)
