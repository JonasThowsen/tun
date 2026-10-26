"""Screenshots of a running preview for the feature loop (spec/loop.md 6).

Usage: tun-check-python tun_shots.py OUT URL ACTOR PATH...

Each PATH of the preview at URL is shot at a phone's width (390x844, touch)
and a desktop's (1280x800), the whole page, signed in as ACTOR (claimed
identity; empty for nobody). OUT gets phone-SLUG.png and desktop-SLUG.png
for each, and shots.json: for each path, its files and the JavaScript
errors its pages raised. `tun loop show` calls this.
"""

import json
import pathlib
import re
import sys

from playwright.sync_api import sync_playwright

SIZES = {
    "phone": dict(viewport={"width": 390, "height": 844}, has_touch=True, is_mobile=True,
                  device_scale_factor=2),
    "desktop": dict(viewport={"width": 1280, "height": 800}),
}


def slug(path):
    return re.sub(r"[^a-z0-9]+", "-", path.lower()).strip("-") or "root"


def main(argv):
    if len(argv) < 5:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    out, url, actor, paths = pathlib.Path(argv[1]), argv[2].rstrip("/"), argv[3], argv[4:]
    out.mkdir(parents=True, exist_ok=True)
    shots = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        contexts = {name: browser.new_context(**options) for name, options in SIZES.items()}
        for name, context in contexts.items():
            if actor:
                context.new_page().goto(f"{url}/login?actor={actor}")
        for path in paths:
            shot = {"path": path, "errors": []}
            for name, context in contexts.items():
                page = context.new_page()
                page.on("pageerror", lambda error: shot["errors"].append(str(error)))
                page.goto(url + path)
                page.wait_for_load_state("networkidle")
                file = out / f"{name}-{slug(path)}.png"
                page.screenshot(path=str(file), full_page=True)
                shot[name] = file.name
                page.close()
            shots.append(shot)
        browser.close()
    (out / "shots.json").write_text(json.dumps(shots, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
