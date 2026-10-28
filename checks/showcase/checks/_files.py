"""What the file checks share (spec/files.md 6): the files they attach, the
way to a card's page, and files dropped or pasted as a browser gives them.

A file whose name starts with _ is not a check (spec/preview.md 4)."""

import base64
import pathlib

FILES = pathlib.Path(__file__).parent / "files"

TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".pdf": "application/pdf", ".txt": "text/plain"}


def path(name):
    return str(FILES / name)


def card_page(page, title):
    """Open the page of the card TITLE from the board; its path."""
    page.goto("/items")
    href = page.card(title).locator("a").first.get_attribute("href")
    page.goto(href)
    return href


def file_data(name, as_name=None, size=None):
    """A file for the page's JavaScript: the fixture NAME's bytes, or SIZE
    zero bytes, under AS_NAME, with its type by NAME's extension."""
    suffix = pathlib.Path(name).suffix
    data = b"" if size is not None else (FILES / name).read_bytes() if (FILES / name).exists() else b"text"
    return {"name": as_name if as_name is not None else name, "type": TYPES.get(suffix, ""),
            "data": base64.b64encode(data).decode(), "size": size}


MAKE_FILES = """(files) => {
  const transfer = new DataTransfer();
  for (const file of files) {
    const bytes = file.size !== null ? new Uint8Array(file.size)
      : Uint8Array.from(atob(file.data), (c) => c.charCodeAt(0));
    transfer.items.add(new File([bytes], file.name, { type: file.type }));
  }
  return transfer;
}
"""


def drag(page, selector, kind, files):
    """Send a drag event of KIND (dragenter, dragover, drop) with FILES to SELECTOR."""
    page.evaluate(
        """([selector, kind, files, make]) => {
             const transfer = (new Function('return ' + make))()(files);
             document.querySelector(selector).dispatchEvent(
               new DragEvent(kind, { dataTransfer: transfer, bubbles: true, cancelable: true }));
           }""", [selector, kind, files, MAKE_FILES])


def paste(page, selector, files):
    """Paste FILES in SELECTOR's element, as a clipboard holding them would."""
    page.evaluate(
        """([selector, files, make]) => {
             const transfer = (new Function('return ' + make))()(files);
             document.querySelector(selector).dispatchEvent(
               new ClipboardEvent('paste', { clipboardData: transfer, bubbles: true, cancelable: true }));
           }""", [selector, files, MAKE_FILES])


def listed(page):
    """The names the file control lists, in order."""
    return page.locator(".tun-file-input-name").evaluate_all(
        "items => items.map((item) => item.firstChild.textContent)")


def attached(page):
    """The names of the files a card's page shows."""
    return page.locator(".tun-attachments-caption").all_inner_texts()
