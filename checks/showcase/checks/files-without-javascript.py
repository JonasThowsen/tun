"""Without JavaScript, a file chosen in the browser's own control is
attached when the form is sent (spec/files.md 6.1)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _files  # noqa: E402


def run(t):
    page = t.phone(javascript=False)
    page.sign_in("employee:anna")
    _files.card_page(page, "Item 3")
    t.check(page.locator(".tun-card [data-tun-file-input-drop]").is_hidden(),
            "no promise of dragging and pasting without a script")
    page.locator(".tun-card input[type=file][name=files]").set_input_files(_files.path("photo.jpg"))
    with page.expect_navigation():
        page.get_by_role("button", name="Attach", exact=True).click()
    t.check(_files.attached(page) == ["photo.jpg"], f"the file is attached: {_files.attached(page)}")
