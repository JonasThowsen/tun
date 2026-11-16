"""The «Document» page shows the board's estimate as text, made with
pdf-text, read on a phone without sideways scrolling; «Make the PDF» makes
it with make-pdf and keeps it on a record, and the page then links to the
file, which answers a PDF as a download (spec/pdf.md 4)."""


def run(t):
    page = t.phone()
    page.sign_in("employee:anna")
    page.goto("/document")
    text = page.locator(".tun-code-block").inner_text()
    t.check("The board's estimate" in text, "the document's title is in its text")
    t.check("Export to accounting" in text and " | " in text,
            "its lines are the cards, their cells separated by « | »")
    t.check(page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"),
            "the page does not scroll sideways")
    before = page.locator("[data-document-file]").count()
    # The post answers 303 to the page itself, so its address does not
    # change: wait for the page that answers the redirect.
    with page.expect_navigation():
        page.get_by_role("button", name="Make the PDF").click()
    links = page.locator("[data-document-file]")
    # The page may list PDFs made before: wait for one more.
    page.wait_until("(n) => document.querySelectorAll('[data-document-file]').length > n",
                    before, what="a link to the PDF made")
    t.check(links.count() == before + 1, f"a link to the PDF made: {links.count()} after {before}")
    href = links.first.get_attribute("href")
    # A file's address is whole, at the server's public URL (spec/files.md 4.2).
    t.check("/files/fil_" in href, f"to its file: {href}")
    t.check("board-estimate.pdf" in links.first.inner_text(), "named by its file")
    answer = page.request.get(href)
    t.check(answer.status == 200, f"the file answers 200: {answer.status}")
    t.check(answer.headers.get("content-type") == "application/pdf",
            f"as a PDF: {answer.headers.get('content-type')}")
    t.check(answer.headers.get("content-disposition", "").startswith("attachment"),
            "to be downloaded")
    t.check(answer.body()[:5] == b"%PDF-", "its bytes are a PDF's")
    t.check(page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"),
            "the page with its link does not scroll sideways")
