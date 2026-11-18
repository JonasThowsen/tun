"""The «Email» page's preview of a mail, in its frame (spec/mail.md 2.1):
read on a phone without sideways scrolling and with its text at 16 px or
more, and its column at most 600 px wide on a desktop. What the frame holds
(its sandbox, the subject, the links, no script) is the server's, and the
page tests read it (tests/pages.lisp,
the-mail-is-previewed-in-a-frame-that-allows-nothing)."""

MEASURE = """() => {
  const column = document.body.firstElementChild;
  const paragraph = document.querySelector('p');
  return {scrollWidth: document.documentElement.scrollWidth,
          clientWidth: document.documentElement.clientWidth,
          columnWidth: column.getBoundingClientRect().width,
          fontSize: parseFloat(getComputedStyle(paragraph).fontSize)};
}"""


def preview(page):
    """What MEASURE reads in the page's mail frame."""
    page.sign_in("employee:anna")
    page.goto("/mail")
    frame = page.locator("iframe[data-mail-preview]").element_handle().content_frame()
    frame.wait_for_load_state()
    return frame.evaluate(MEASURE)


def run(t):
    m = preview(t.phone())
    t.check(m["scrollWidth"] <= m["clientWidth"],
            f"on a phone it does not scroll sideways ({m['scrollWidth']} in {m['clientWidth']})")
    t.check(m["fontSize"] >= 16, f"its text is 16 px or more: {m['fontSize']}")

    m = preview(t.desktop())
    t.check(m["columnWidth"] <= 600,
            f"on a desktop its column is at most 600 px: {m['columnWidth']}")
    t.check(m["scrollWidth"] <= m["clientWidth"], "and does not scroll sideways")
