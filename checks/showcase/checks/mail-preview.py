"""The «E-post» page previews a summary of the cards as a mail, made with
render-mail (spec/mail.md 2.1): in a frame whose sandbox allows nothing,
read on a phone without sideways scrolling and with its text at 16 px or
more, its column at most 600 px wide on a desktop, and its links, written
as paths, whole at the preview's public URL."""

MEASURE = """() => {
  const column = document.body.firstElementChild;
  const paragraph = document.querySelector('p');
  return {scrollWidth: document.documentElement.scrollWidth,
          clientWidth: document.documentElement.clientWidth,
          columnWidth: column.getBoundingClientRect().width,
          fontSize: parseFloat(getComputedStyle(paragraph).fontSize),
          links: [...document.querySelectorAll('a')].map((a) => a.getAttribute('href')),
          title: document.title,
          external: document.querySelectorAll('script, link, style').length};
}"""


def preview(page):
    """The sandbox attribute of the page's mail frame, and what MEASURE reads in it."""
    page.sign_in("employee:anna")
    page.goto("/e-post")
    element = page.locator("iframe[data-mail-preview]")
    sandbox = element.get_attribute("sandbox")
    frame = element.element_handle().content_frame()
    frame.wait_for_load_state()
    return sandbox, frame.evaluate(MEASURE)


def run(t):
    sandbox, m = preview(t.phone())
    t.check(sandbox == "", f"the frame's sandbox allows nothing: {sandbox!r}")
    t.check(m["title"] == "Sammendrag fra tavla", f"the subject is the mail's title: {m['title']}")
    t.check(m["scrollWidth"] <= m["clientWidth"],
            f"on a phone it does not scroll sideways ({m['scrollWidth']} in {m['clientWidth']})")
    t.check(m["fontSize"] >= 16, f"its text is 16 px or more: {m['fontSize']}")
    t.check(m["external"] == 0, "it has no script, link or style element")
    base = t.url.rstrip("/") + "/saker"
    t.check(m["links"] and all(link.startswith(base) for link in m["links"]),
            f"its links are whole, at {base}: {m['links'][:3]}")
    t.check(len(m["links"]) >= 5, f"each card listed is a link: {len(m['links'])}")

    text = t.page.locator(".tun-code-block").inner_text()
    t.check("Sammendrag fra tavla" in text and f"({base}/" in text,
            "the text part below gives each link as «title (url)»")

    sandbox, m = preview(t.desktop())
    t.check(m["columnWidth"] <= 600,
            f"on a desktop its column is at most 600 px: {m['columnWidth']}")
    t.check(m["scrollWidth"] <= m["clientWidth"], "and does not scroll sideways")
