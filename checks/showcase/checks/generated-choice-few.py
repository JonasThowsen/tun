"""The generated pages choosing a record among few, on the showcase's
generated «Meetings» with the default scenario's four customers: the
form's «Customer» field holds every customer with the page and narrows
them in the browser without asking, and the list's filter likewise
(spec/ui.md 8, «Choosing a record», item 3)."""

SCENARIO = "default"

OPTIONS = """(selector) => {
  const root = document.querySelector(selector).closest('[data-tun-choice]');
  const field = root.querySelector('[data-tun-choice-field]');
  return {asks: field.getAttribute('hx-get'),
          texts: [...root.querySelectorAll('[data-tun-choice-list] [role=option]')]
            .filter((o) => !o.hidden)
            .map((o) => o.querySelector('.tun-choice-options-text').textContent)};
}"""


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/meetings")
    page.wait_for_function("() => document.querySelector('[data-tun-choice][data-tun-ready]')")
    asked = []
    page.on("request", lambda request: asked.append(request.url)
            if "/choices/" in request.url else None)
    field = "#meetings_create-customer-search"
    s = page.evaluate(OPTIONS, field)
    t.check(s["asks"] is None and sorted(s["texts"]) == ["Berg Catering", "Fjord Events",
                                                         "Hansen Plumbing", "Nordvik Bakery Ltd"],
            f"with four customers the field holds them all and asks nothing: {s}")
    page.locator("#meetings_create-customer-trigger").click()
    page.wait_for_timeout(300)
    page.keyboard.type("fjord")
    page.wait_for_timeout(400)
    s = page.evaluate(OPTIONS, field)
    t.check(s["texts"] == ["Fjord Events"] and not asked,
            f"typing «fjord» leaves «Fjord Events» alone, with no request: {s['texts']} {asked}")
    page.keyboard.press("Escape")
    filter_field = "#tun-list-toolbar-customer-search"
    s = page.evaluate(OPTIONS, filter_field)
    t.check(s["asks"] is None and len(s["texts"]) == 4,
            f"the list's filter holds the four too: {s}")
    for scheme in ("light", "dark"):
        for width, make in ((390, t.phone), (1280, t.desktop)):
            p = make(scheme=scheme)
            p.sign_in("employee:anna")
            p.goto("/meetings")
            p.wait_for_function("() => document.querySelector('[data-tun-choice][data-tun-ready]')")
            p.locator("#meetings_create-customer-trigger").click()
            p.wait_for_timeout(400)
            p.screenshot(path=str(t.out / f"generated-choice-few-{width}-{scheme}.png"))
            t.check(True, f"{width}px {scheme}: a picture of the field with four customers")
