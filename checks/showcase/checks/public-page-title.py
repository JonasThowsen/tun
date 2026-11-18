"""A customer's quote, a public page the page sweep does not reach, does
not scroll sideways at 390 or 1280 px. The names its frame shows are the
server's, and its page tests read them (tests/pages.lisp,
a-public-page-shows-the-name-the-client-answers)."""


def run(t):
    for width, page in ((390, t.phone()), (1280, t.desktop())):
        page.goto("/quote/q1")
        t.check(page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"),
                f"{width} px: the quote does not scroll sideways")
