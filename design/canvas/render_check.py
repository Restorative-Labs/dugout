#!/usr/bin/env python3
"""
Render every artboard at the real device size and MEASURE it.

The source tells you nothing about overflow. This renders each .dc.html the
way the runtime does for a static artboard — helmet <style> plus the markup
inside <x-dc> — at 390x844, and reports anything that clips.

A previous mockup pass on this project shipped five screens with the primary
button cut off, including one where the second action was gone entirely. That
is what this exists to catch.
"""
import os
import re
import sys
import json
from playwright.sync_api import sync_playwright

OUT = os.path.dirname(os.path.abspath(__file__))
W, H = 390, 844

STYLE = re.compile(r"<style>(.*?)</style>", re.S)
XDC = re.compile(r"<x-dc>(.*?)</x-dc>", re.S)
HELMET = re.compile(r"<helmet>.*?</helmet>", re.S)
FONTS = re.compile(r'<link rel="stylesheet" href="(https://fonts\.googleapis[^"]+)"')


def as_page(src):
    css = "\n".join(STYLE.findall(src))
    inner = XDC.search(src).group(1)
    inner = HELMET.sub("", inner)
    link = FONTS.search(src)
    head = f'<link rel="stylesheet" href="{link.group(1)}">' if link else ""
    return f"<!doctype html><html><head><meta charset='utf-8'>{head}<style>{css}</style></head><body>{inner}</body></html>"


def main():
    files = sorted(f for f in os.listdir(OUT) if f.endswith(".dc.html"))
    shots = os.path.join(OUT, "_shots")
    os.makedirs(shots, exist_ok=True)
    problems = []

    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path="/opt/pw-browsers/chromium-1194/chrome-linux/chrome")
        page = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=2)
        for f in files:
            src = open(os.path.join(OUT, f), encoding="utf-8").read()
            page.set_content(as_page(src), wait_until="networkidle")
            page.wait_for_timeout(220)
            m = page.evaluate("""() => {
                const d = document.documentElement, b = document.body;
                const over = [];
                for (const el of document.querySelectorAll('*')) {
                    const r = el.getBoundingClientRect();
                    if (r.bottom > %d + 1 && r.height > 0 && r.width > 0) {
                        over.push({tag: el.tagName.toLowerCase(),
                                   cls: (el.className || '').toString().slice(0, 28),
                                   bottom: Math.round(r.bottom),
                                   txt: (el.textContent || '').trim().slice(0, 34)});
                    }
                }
                return {scrollH: b.scrollHeight, clientH: b.clientHeight,
                        docScroll: d.scrollHeight, over: over.slice(0, 4)};
            }""" % H)
            page.screenshot(path=os.path.join(shots, f.replace(".dc.html", ".png")))
            clip = m["scrollH"] - m["clientH"]
            if clip > 0 or m["over"]:
                problems.append((f, clip, m["over"]))
                print(f"  OVERFLOW  {f:28} +{clip}px")
                for o in m["over"]:
                    print(f"            └ {o['tag']}.{o['cls']} bottom={o['bottom']} «{o['txt']}»")
            else:
                print(f"  ok        {f:28} fits {W}x{H}")
        browser.close()

    print()
    if problems:
        print(f"{len(problems)} of {len(files)} artboards CLIP at {W}x{H} — fix before publishing.")
        sys.exit(1)
    print(f"all {len(files)} artboards fit {W}x{H} with nothing clipped.")


if __name__ == "__main__":
    main()
