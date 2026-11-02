"""On a phone, a tap on a text area in a card that is a link focuses it and
stays on the page, and a tap on the card's own text follows the link
(spec/ui.md 6)."""

CARD = "Fitting at Kari Nordmann's"

# Whether each control in the card is the element found at its own centre,
# that is, above the title link that covers the card.
ON_TOP = """(title) => {
  const card = [...document.querySelectorAll('.tun-card[data-variant=link]')]
    .find((c) => c.querySelector('.tun-card-link')?.textContent === title);
  const onTop = (element) => {
    const r = element.getBoundingClientRect();
    const found = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    return found === element || element.contains(found);
  };
  return {textarea: onTop(card.querySelector('textarea')),
          label: onTop(card.querySelector('label')),
          button: onTop(card.querySelector('button'))};
}"""


def run(t):
    page = t.phone()
    # The specimen's link leads nowhere in the showcase; the check answers it.
    page.route("**/jobs/1042", lambda route: route.fulfill(
        status=200, content_type="text/html", body="<!doctype html><title>Job</title>"))
    page.goto("/ui/card")
    card = page.locator(".tun-card[data-variant=link]").filter(
        has=page.get_by_role("link", name=CARD, exact=True))
    card.scroll_into_view_if_needed()
    on_top = page.evaluate(ON_TOP, CARD)
    t.check(on_top["textarea"], "the text area is above the card's link")
    t.check(on_top["label"], "so is its label")
    t.check(on_top["button"], "so is the button")

    card.locator("textarea").tap()
    page.wait_for_timeout(300)
    t.check(page.evaluate("document.activeElement?.tagName") == "TEXTAREA",
            "a tap on the text area focuses it")
    t.check(page.url.endswith("/ui/card"), f"and stays on the page ({page.url})")

    # A tap where the card's text is, which the link covers: a locator's tap
    # would refuse an element under another.
    text = card.locator(".tun-card-description").bounding_box()
    page.touchscreen.tap(text["x"] + text["width"] / 2, text["y"] + text["height"] / 2)
    page.wait_for_url("**/jobs/1042")
    t.check(page.url.endswith("/jobs/1042"), "a tap on the card's text follows its link")
