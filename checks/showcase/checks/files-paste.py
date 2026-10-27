"""Pasting a screenshot into «Meld en sak» lists it as skjermbilde-HHMMSS.png
by the device's clock, -2 for a second; a pasted JPEG is .jpg and a named
file keeps its name; pasting text pastes the text; sending creates the card
with its files (spec/files.md 6.1)."""

import datetime
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _files  # noqa: E402

TITLE = "input[name=title]"


def run(t):
    page = t.desktop(permissions=["clipboard-read", "clipboard-write"])
    page.sign_in("employee:anna")
    page.goto("/saker/ny")
    page.clock.set_fixed_time(datetime.datetime(2026, 10, 26, 14, 23, 5))
    page.evaluate("navigator.clipboard.writeText('Eksporten feiler')")
    page.locator(TITLE).focus()
    page.keyboard.press("Control+V")
    t.check(page.locator(TITLE).input_value() == "Eksporten feiler", "pasting text pastes the text")
    t.check(_files.listed(page) == [], "and lists nothing")
    _files.paste(page, TITLE, [_files.file_data("skjermbilde.png", "image.png")])
    t.check(_files.listed(page) == ["skjermbilde-142305.png"],
            f"a pasted screenshot is named by the clock: {_files.listed(page)}")
    t.check(page.locator(TITLE).input_value() == "Eksporten feiler", "the title is as it was")
    _files.paste(page, TITLE, [_files.file_data("skjermbilde.png", "image.png")])
    _files.paste(page, TITLE, [_files.file_data("foto.jpg", "image.jpeg")])
    _files.paste(page, TITLE, [_files.file_data("kvittering.pdf")])
    expected = ["skjermbilde-142305.png", "skjermbilde-142305-2.png", "skjermbilde-142305.jpg",
                "kvittering.pdf"]
    t.check(_files.listed(page) == expected, f"named as the rule says: {_files.listed(page)}")
    with page.expect_navigation():
        page.get_by_role("button", name="Meld saken").click()
    page.wait_for_selector(".tun-attachments-item")
    t.check(page.locator("h1").inner_text().strip() == "Eksporten feiler", "the card is made")
    t.check(_files.attached(page) == expected, f"with its files: {_files.attached(page)}")
