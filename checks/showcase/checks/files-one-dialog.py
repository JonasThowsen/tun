"""/attachments, with three cards' files in three components, has no image
dialog until an image is opened, and then one, at the end of the body: each
component's image opens in it with its name and «Open the original», and
Escape gives the focus back to the thumbnail (spec/files.md 6.3)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _files  # noqa: E402


def attach(page, title, name):
    """Attach the file NAME to the card TITLE from its page."""
    _files.card_page(page, title)
    page.locator(".tun-card input[type=file][name=files]").set_input_files(_files.path(name))
    with page.expect_navigation():
        page.get_by_role("button", name="Attach", exact=True).click()


DIALOGS = "() => document.querySelectorAll('dialog').length"
LAST = "() => !!document.body.lastElementChild.matches('dialog.tun-attachments-dialog')"
FOCUSED = "(link) => document.activeElement === link"


def open_each(t, page, where):
    components = page.locator(".tun-attachments").filter(has=page.locator(".tun-attachments-image"))
    t.check(components.count() == 3, f"{where}: three components with images: {components.count()}")
    t.check(page.evaluate(DIALOGS) == 0, f"{where}: no dialog before an image is opened")
    dialog = page.locator("dialog.tun-attachments-dialog")
    for i in range(3):
        link = components.nth(i).locator(".tun-attachments-image").first
        name = link.get_attribute("data-tun-attachment-name")
        href = link.get_attribute("href")
        link.focus()
        link.click()
        t.check(page.evaluate(DIALOGS) == 1, f"{where}: one dialog after opening image {i + 1}")
        t.check(page.evaluate(LAST), f"{where}: at the end of the body")
        t.check(dialog.evaluate("(d) => d.open"), f"{where}: the image of component {i + 1} opens in it")
        full = dialog.locator(".tun-attachments-full")
        full.evaluate("(img) => img.decode()")
        t.check(full.get_attribute("src").endswith(href) and full.evaluate("(img) => img.naturalWidth") > 0,
                f"{where}: showing that image, {href}")
        t.check(dialog.locator(".tun-attachments-name").inner_text() == name, f"{where}: named {name}")
        original = dialog.get_by_role("link", name="Open the original")
        t.check(original.get_attribute("href").endswith(href), f"{where}: «Open the original» links to it")
        page.keyboard.press("Escape")
        t.check(not dialog.evaluate("(d) => d.open"), f"{where}: Escape closes it")
        t.check(link.evaluate(FOCUSED), f"{where}: and the focus goes back to the thumbnail")
    t.check(page.evaluate(DIALOGS) == 1, f"{where}: still one dialog for the page")


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    attach(page, "Item 1", "photo.jpg")
    attach(page, "Item 2", "screenshot.png")
    page.goto("/attachments")
    open_each(t, page, "1280px")
    page.screenshot(path=str(t.out / "files-one-dialog-1280.png"))
    phone = t.phone()
    phone.sign_in("employee:anna")
    phone.goto("/attachments")
    open_each(t, phone, "390px")
    phone.locator(".tun-attachments-image").first.click()
    phone.wait_for_timeout(300)
    phone.screenshot(path=str(t.out / "files-one-dialog-390.png"))
