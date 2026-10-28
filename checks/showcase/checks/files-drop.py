"""On a computer, a PNG dragged over a card's file control marks it, and
dropped there is listed and attached; a text file, or one that would take
the files past 25 MB, is not added and the list says why (spec/files.md 6.1)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _files  # noqa: E402

ZONE = ".tun-card [data-tun-file-input]"


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    _files.card_page(page, "New page for invoices")
    png = [_files.file_data("screenshot.png")]
    _files.drag(page, ZONE, "dragenter", png)
    _files.drag(page, ZONE, "dragover", png)
    zone = page.locator(ZONE)
    t.check(zone.get_attribute("data-dragging") is not None, "the zone is marked while a file is over it")
    t.check("Drop to attach" in zone.inner_text(), "and says what dropping does")
    _files.drag(page, ZONE, "drop", png)
    t.check(zone.get_attribute("data-dragging") is None, "no longer marked after the drop")
    t.check(_files.listed(page) == ["screenshot.png"], f"the dropped file is listed: {_files.listed(page)}")
    _files.drag(page, ZONE, "drop", [_files.file_data("note.txt")])
    t.check(_files.listed(page) == ["screenshot.png"], "a text file is not added")
    t.check("“note.txt”: this file type is not allowed." in zone.inner_text(), "and the list says why")
    with page.expect_navigation():
        page.get_by_role("button", name="Attach", exact=True).click()
    page.wait_for_selector(".tun-attachments-item")
    t.check(_files.attached(page) == ["screenshot.png"], f"the PNG is attached: {_files.attached(page)}")

    other = t.desktop()
    other.sign_in("employee:anna")
    _files.card_page(other, "Fix a typo")
    nine = 9 * 1000 * 1000
    _files.drag(other, ZONE, "drop", [_files.file_data("a.png", "a.png", nine),
                                      _files.file_data("b.png", "b.png", nine),
                                      _files.file_data("c.png", "c.png", nine)])
    t.check(_files.listed(other) == ["a.png", "b.png"], f"two of 9 MB are listed: {_files.listed(other)}")
    t.check("The files can be at most 25 MB together." in other.locator(ZONE).inner_text(),
            "the third would pass 25 MB, and the list says so")
