"""On a phone, files chosen in a card's file control are listed with their
previews, names and sizes before anything is sent; «Remove» takes one out of
the list and the input, and sending attaches the rest (spec/files.md 6.1)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _files  # noqa: E402


def run(t):
    page = t.phone()
    page.sign_in("employee:anna")
    href = _files.card_page(page, "Notification by email")
    control = page.locator(".tun-card input[type=file][name=files]")
    control.set_input_files([_files.path("screenshot.png"), _files.path("photo.jpg"),
                             _files.path("receipt.pdf")])
    t.check(_files.listed(page) == ["screenshot.png", "photo.jpg", "receipt.pdf"],
            f"the three are listed under their own names: {_files.listed(page)}")
    t.check(page.locator(".tun-file-input-item img.tun-file-input-preview").count() == 2,
            "the images have a preview")
    t.check(" kB" in page.locator(".tun-file-input-item").first.inner_text(), "each has its size")
    t.check(page.locator(".tun-attachments-item").count() == 0, "nothing is sent yet")
    page.get_by_role("button", name="Remove photo.jpg").click()
    t.check(_files.listed(page) == ["screenshot.png", "receipt.pdf"], "«Remove» takes it out of the list")
    t.check(control.evaluate("(input) => Array.from(input.files).map((f) => f.name)")
            == ["screenshot.png", "receipt.pdf"], "and out of the input")
    with page.expect_navigation():
        page.get_by_role("button", name="Attach", exact=True).click()
    page.wait_for_selector(".tun-attachments-item")
    t.check(_files.attached(page) == ["screenshot.png", "receipt.pdf"],
            f"the card shows the two: {_files.attached(page)}")
    page.goto(href)
    t.check(_files.attached(page) == ["screenshot.png", "receipt.pdf"], "and still after a reload")
