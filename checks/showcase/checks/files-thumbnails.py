"""On a phone, a card's screenshot is a lazy thumbnail of its own size that
opens the whole image in a dialog, which Escape closes, and its PDF a tile
linking to the file; the page does not scroll sideways (spec/files.md 6.3)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _files  # noqa: E402


def run(t):
    page = t.phone()
    page.sign_in("employee:anna")
    _files.card_page(page, "Eksport til regnskap")
    thumbnail = page.locator(".tun-attachments-image img")
    t.check(thumbnail.count() == 1, "one thumbnail")
    t.check((thumbnail.get_attribute("width"), thumbnail.get_attribute("height")) == ("640", "400"),
            "of the image's own width and height")
    t.check(thumbnail.get_attribute("loading") == "lazy", "loaded lazily")
    url = page.locator(".tun-attachments-image").get_attribute("href")
    t.check(url.startswith("/files/fil_"), f"linking to the file: {url}")
    page.locator(".tun-attachments-image").click()
    dialog = page.locator(".tun-attachments-dialog")
    t.check(dialog.evaluate("(d) => d.open"), "a click opens the dialog")
    full = dialog.locator(".tun-attachments-full")
    full.evaluate("(img) => img.decode()")
    t.check(full.evaluate("(img) => img.naturalWidth") == 640, "showing the whole image")
    t.check(dialog.get_by_role("link", name="Åpne original").get_attribute("href").endswith(url),
            "«Åpne original» links to the file")
    page.keyboard.press("Escape")
    t.check(not dialog.evaluate("(d) => d.open"), "Escape closes it")
    pdf = page.locator(".tun-attachments-file")
    t.check(pdf.count() == 1 and pdf.get_attribute("href").startswith("/files/fil_"),
            "the PDF is a tile linking to its file")
    t.check("kvittering.pdf" in page.locator(".tun-attachments").inner_text(), "with its name")
    t.check(page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"),
            "the page does not scroll sideways")
