"""Files chosen in a dialog's file field are attached: a dialog with a file
field posts them, as a page's form does (spec/files.md 6.4)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _files  # noqa: E402


def run(t):
    page = t.phone()
    page.sign_in("employee:anna")
    href = _files.card_page(page, "Varsel på e-post")
    before = _files.attached(page)
    page.get_by_role("button", name="Legg ved i et vindu").click()
    dialog = page.locator("dialog#legg-ved")
    t.check(dialog.is_visible(), "the dialog opens")
    t.check(dialog.locator("form").get_attribute("enctype") == "multipart/form-data",
            "its form posts files")
    dialog.locator("input[type=file][name=filer]").set_input_files([_files.path("skjermbilde.png")])
    with page.expect_navigation():
        dialog.get_by_role("button", name="Legg ved", exact=True).click()
    page.wait_for_selector(".tun-attachments-item")
    t.check(_files.attached(page) == before + ["skjermbilde.png"],
            f"the card shows the file sent from the dialog: {_files.attached(page)}")
    page.goto(href)
    t.check(_files.attached(page)[-1:] == ["skjermbilde.png"], "and still after a reload")
