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
    _files.card_page(page, "Ny side for fakturaer")
    png = [_files.file_data("skjermbilde.png")]
    _files.drag(page, ZONE, "dragenter", png)
    _files.drag(page, ZONE, "dragover", png)
    zone = page.locator(ZONE)
    t.check(zone.get_attribute("data-dragging") is not None, "the zone is marked while a file is over it")
    t.check("Slipp for å legge ved" in zone.inner_text(), "and says what dropping does")
    _files.drag(page, ZONE, "drop", png)
    t.check(zone.get_attribute("data-dragging") is None, "no longer marked after the drop")
    t.check(_files.listed(page) == ["skjermbilde.png"], f"the dropped file is listed: {_files.listed(page)}")
    _files.drag(page, ZONE, "drop", [_files.file_data("notat.txt")])
    t.check(_files.listed(page) == ["skjermbilde.png"], "a text file is not added")
    t.check("«notat.txt»: filtypen er ikke tillatt." in zone.inner_text(), "and the list says why")
    with page.expect_navigation():
        page.get_by_role("button", name="Legg ved", exact=True).click()
    page.wait_for_selector(".tun-attachments-item")
    t.check(_files.attached(page) == ["skjermbilde.png"], f"the PNG is attached: {_files.attached(page)}")

    other = t.desktop()
    other.sign_in("employee:anna")
    _files.card_page(other, "Rett skrivefeil")
    nine = 9 * 1000 * 1000
    _files.drag(other, ZONE, "drop", [_files.file_data("a.png", "a.png", nine),
                                      _files.file_data("b.png", "b.png", nine),
                                      _files.file_data("c.png", "c.png", nine)])
    t.check(_files.listed(other) == ["a.png", "b.png"], f"two of 9 MB are listed: {_files.listed(other)}")
    t.check("Filene kan ikke være større enn 25 MB til sammen." in other.locator(ZONE).inner_text(),
            "the third would pass 25 MB, and the list says so")
