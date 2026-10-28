"""Pasting a screenshot into «New item» lists it as screenshot-HHMMSS.png
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
    page.goto("/items/new")
    page.clock.set_fixed_time(datetime.datetime(2026, 10, 26, 14, 23, 5))
    page.evaluate("navigator.clipboard.writeText('The export fails')")
    page.locator(TITLE).focus()
    page.keyboard.press("Control+V")
    t.check(page.locator(TITLE).input_value() == "The export fails", "pasting text pastes the text")
    t.check(_files.listed(page) == [], "and lists nothing")
    _files.paste(page, TITLE, [_files.file_data("screenshot.png", "image.png")])
    t.check(_files.listed(page) == ["screenshot-142305.png"],
            f"a pasted screenshot is named by the clock: {_files.listed(page)}")
    t.check(page.locator(TITLE).input_value() == "The export fails", "the title is as it was")
    _files.paste(page, TITLE, [_files.file_data("screenshot.png", "image.png")])
    _files.paste(page, TITLE, [_files.file_data("photo.jpg", "image.jpeg")])
    _files.paste(page, TITLE, [_files.file_data("receipt.pdf")])
    expected = ["screenshot-142305.png", "screenshot-142305-2.png", "screenshot-142305.jpg",
                "receipt.pdf"]
    t.check(_files.listed(page) == expected, f"named as the rule says: {_files.listed(page)}")
    with page.expect_navigation():
        page.get_by_role("button", name="Report the item").click()
    page.wait_for_selector(".tun-attachments-item")
    t.check(page.locator("h1").inner_text().strip() == "The export fails", "the card is made")
    t.check(_files.attached(page) == expected, f"with its files: {_files.attached(page)}")
