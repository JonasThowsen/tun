#!/usr/bin/env python3
"""Screenshot the specimen's standalone pages (spec/ui.md 7).

Usage: ui-shots.py SPECIMEN-DIR OUT-DIR [--widths 390,1280] [--schemes light,dark] [NAME...]

For each page (NAME.html, or every page but index.html without NAMEs) and
each width and colour scheme, writes OUT-DIR/NAME-WIDTH-SCHEME.png: the
whole page, at twice the pixel density.  Prints each file it writes.
"""

import argparse
import pathlib
import sys

from playwright.sync_api import sync_playwright

# Open Sans is close to an Android phone's Roboto and has every weight the
# tokens name.  Set through the tokens, the way a client's theme would.
FONTS = (":root { --font-sans: 'Open Sans', sans-serif;"
         " --font-mono: 'Source Code Pro', monospace; }")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("specimen", type=pathlib.Path)
    parser.add_argument("out", type=pathlib.Path)
    parser.add_argument("--widths", default="390,1280")
    parser.add_argument("--schemes", default="light,dark")
    parser.add_argument("names", nargs="*")
    args = parser.parse_args()

    pages = ([args.specimen / f"{name}.html" for name in args.names] if args.names
             else sorted(p for p in args.specimen.glob("*.html") if p.name != "index.html"))
    missing = [p for p in pages if not p.exists()]
    if missing:
        sys.exit("no such page: " + ", ".join(str(p) for p in missing))
    args.out.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        for width in [int(w) for w in args.widths.split(",")]:
            for scheme in args.schemes.split(","):
                context = browser.new_context(viewport={"width": width, "height": 900},
                                              device_scale_factor=2, color_scheme=scheme,
                                              has_touch=width < 600, is_mobile=width < 600)
                page = context.new_page()
                for path in pages:
                    page.goto(path.resolve().as_uri())
                    page.add_style_tag(content=FONTS)
                    shot = args.out / f"{path.stem}-{width}-{scheme}.png"
                    page.screenshot(path=shot, full_page=True)
                    print(shot)
                context.close()
        browser.close()


if __name__ == "__main__":
    main()
