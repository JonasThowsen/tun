"""«Download the PDF» on the «Document» page answers the board's estimate
as a PDF made on the spot, a download kept nowhere (spec/files.md 5.5): on
a phone with and without JavaScript, and wide, the browser saves it and
stays on the page, and no document is stored; a viewer is refused it."""

import pathlib


def download_from(t, page, what):
    page.sign_in("employee:anna")
    page.goto("/document")
    made = page.locator("[data-document-file]").count()
    address = page.url
    link = page.locator("[data-document-download]")
    t.check(link.is_visible(), f"{what}: «Download the PDF» is shown")
    with page.expect_download() as info:
        link.click()
    download = info.value
    t.check(download.suggested_filename == "board-estimate.pdf",
            f"{what}: named board-estimate.pdf: {download.suggested_filename}")
    octets = pathlib.Path(download.path()).read_bytes()
    t.check(octets[:5] == b"%PDF-", f"{what}: its bytes are a PDF's")
    t.check(page.url == address, f"{what}: the page stays where it was: {page.url}")
    t.check(page.locator("[data-document-download]").is_visible(),
            f"{what}: and still shows the page")
    page.goto("/document")
    t.check(page.locator("[data-document-file]").count() == made,
            f"{what}: no document was stored ({made} made before and after)")
    t.check(page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"),
            f"{what}: the page does not scroll sideways")


def run(t):
    download_from(t, t.phone(), "on a phone")
    download_from(t, t.phone(javascript=False), "on a phone without JavaScript")
    page = t.desktop()
    download_from(t, page, "wide")
    answer = page.request.get(t.url + "/document/board-estimate.pdf")
    t.check(answer.status == 200, f"the download answers 200: {answer.status}")
    t.check(answer.headers.get("content-type") == "application/pdf",
            f"as a PDF: {answer.headers.get('content-type')}")
    t.check(answer.headers.get("content-disposition", "").startswith(
        'attachment; filename="board-estimate.pdf"'),
        f"to be downloaded: {answer.headers.get('content-disposition')}")
    t.check(answer.headers.get("x-content-type-options") == "nosniff", "never sniffed")
    t.check(answer.headers.get("cache-control") == "no-store", "kept nowhere")
    t.close_pages()
    viewer = t.phone()
    viewer.sign_in("viewer:vera")
    refused = viewer.request.get(t.url + "/document/board-estimate.pdf")
    t.check(refused.status == 403, f"a viewer is refused it: {refused.status}")
    t.check("content-disposition" not in refused.headers, "and gets no file")
    t.check(refused.body()[:5] != b"%PDF-", "nor its bytes")
