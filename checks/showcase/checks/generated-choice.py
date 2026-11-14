"""The generated pages choosing a record by typing, on the showcase's
generated «Meetings» with 405 customers: the form's «Customer» field asking
/choices/customer as one types, Enter choosing and the meeting saved for
the chosen customer; the list's «Customer» filter choosing into the address
and the list; without JavaScript the find step, saving and «Apply»; and the
file field of «New item» inside its column at 320, 360 and 390 px, and the
specimen's find-step example chosen (spec/ui.md 8, «Choosing a record»,
spec/files.md 6.1)."""

import re

SCENARIO = "choices"

WIDE_PAGE = "() => document.scrollingElement.scrollWidth > document.documentElement.clientWidth + 1"

# The state of the choice whose root holds the element SELECTOR, as
# ui-choice.py reads it.
STATE = """(selector) => {
  const root = document.querySelector(selector).closest('[data-tun-choice]');
  const field = root.querySelector('[data-tun-choice-field]');
  const list = root.querySelector('[data-tun-choice-list] [role=listbox]');
  const options = [...list.querySelectorAll('[role=option]')].filter((o) => !o.hidden);
  const select = root.querySelector('[data-tun-choice-select]');
  const text = root.querySelector('[data-tun-choice-text]');
  return {value: field.value, answered: list.getAttribute('data-tun-choice-query'),
          asks: field.getAttribute('hx-get'),
          texts: options.map((o) => o.querySelector('.tun-choice-options-text').textContent),
          values: options.map((o) => o.dataset.value),
          chosen: select.value, shown: text ? text.textContent : null,
          more: list.querySelector('.tun-choice-options-more')?.textContent ?? null};
}"""

UNREGISTER = """async () => {
  for (const registration of await navigator.serviceWorker.getRegistrations())
    await registration.unregister();
}"""

# The boxes of the file field of «New item»: its column (the field), the
# drop zone and the browser's control.
FILE_BOXES = """() => {
  const zone = document.querySelector('.tun-file-input');
  const control = zone.querySelector('.tun-file-input-control');
  const column = zone.closest('.tun-field');
  const box = (e) => { const r = e.getBoundingClientRect(); return {left: r.left, right: r.right, width: r.width}; };
  return {column: box(column), zone: box(zone), control: box(control),
          window: document.documentElement.clientWidth};
}"""

FORM = "#meetings_create-customer-trigger"
# The form's own submit button: not the find step's, nor the choice's
# default button that Enter presses (spec/ui.md 6, «Enter saves»).
SAVE = ("form[data-tool=meetings_create] button[type=submit]"
        ":not([name=tun-find]):not(.tun-choice-input-default)")
FIELD = "#meetings_create-customer-search"
SELECT = "select#meetings_create-customer"
FILTER_BUTTON = "#tun-list-toolbar-customer-button"
FILTER_FIELD = "#tun-list-toolbar-customer-search"


def state(page, selector=FIELD):
    return page.evaluate(STATE, selector)


def wait_answered(page, text, selector=FIELD, timeout=4000):
    page.wait_for_function(
        """([selector, text]) => document.querySelector(selector).closest('[data-tun-choice]')
             .querySelector('[data-tun-choice-list] [role=listbox]')
             ?.getAttribute('data-tun-choice-query') === text""",
        arg=[selector, text], timeout=timeout)


def open_meetings(t, make=None, **options):
    page = (make or t.desktop)(**options)
    page.sign_in("employee:anna")
    page.goto("/meetings")
    page.evaluate(UNREGISTER)
    page.goto("/meetings")
    page.wait_for_function("() => document.querySelector('[data-tun-choice][data-tun-ready]')")
    return page


def form(t):
    page = open_meetings(t)
    asked = []
    page.on("request", lambda request: asked.append(request.url)
            if "/choices/customer" in request.url else None)
    t.check(state(page)["asks"] == "/choices/customer",
            f"with 405 customers the form's field asks /choices/customer: {state(page)['asks']}")
    page.locator(FORM).click()
    wait_answered(page, "")
    s = state(page)
    t.check(len(s["texts"]) == 20 and s["more"] == "385 more. Type to narrow them.",
            f"it opens with the first 20 and the rest counted: {len(s['texts'])} {s['more']}")
    page.keyboard.type("bjorn ase")
    wait_answered(page, "bjorn ase")
    s = state(page)
    t.check(s["texts"][:1] == ["Bjørn Åsen"],
            f"«bjorn ase» finds «Bjørn Åsen» by the search's rule: {s['texts'][:3]}")
    t.check(all("/choices/customer" in url for url in asked) and len(asked) >= 2,
            f"asked of the kernel's address: {asked}")
    chosen = s["values"][0]
    page.keyboard.press("Enter")
    page.wait_for_timeout(300)
    s = state(page)
    t.check(s["chosen"] == chosen and s["shown"] == "Bjørn Åsen",
            f"Enter chooses him, his id the select's value: {s['chosen']} {s['shown']}")
    page.fill("#meetings_create-name", "Planned by typing")
    page.locator(SAVE).click()
    page.wait_for_url(re.compile(r"/meetings/mtg_"), timeout=5000)
    details = page.locator(".tun-summary-list").inner_text()
    t.check("Bjørn Åsen" in details and "Planned by typing" in page.content(),
            f"«Create meeting» saves a meeting for him, named on its page: {details!r}")


def filter_(t):
    page = open_meetings(t)
    page.evaluate("() => { window.tunChoiceMark = 1; }")
    page.locator(FILTER_BUTTON).click()
    wait_answered(page, "", FILTER_FIELD)
    page.keyboard.type("bjorn")
    wait_answered(page, "bjorn", FILTER_FIELD)
    chosen = state(page, FILTER_FIELD)["values"][0]
    page.keyboard.press("Enter")
    page.wait_for_url(re.compile(r"customer=cus_"), timeout=5000)
    page.wait_for_timeout(600)
    titles = page.locator(".tun-table tbody tr td:first-child").all_inner_texts()
    button = page.locator(FILTER_BUTTON).inner_text()
    # The form's check before saved a meeting with him too.
    t.check(f"customer={chosen}" in page.url and "Lights for the summer party" in titles
            and "Bread van signage" not in titles and "Pipes for the new shop" not in titles,
            f"the filter puts the id in the address and the list shows his meetings: {page.url} {titles}")
    t.check(page.evaluate("() => window.tunChoiceMark === 1") and "Customer: Bjørn Åsen" in button,
            f"without loading the page, its button naming him: {button}")
    page.goto(f"/meetings?customer={chosen}")
    t.check("Customer: Bjørn Åsen" in page.locator(FILTER_BUTTON).inner_text(),
            "an address written by hand reads the same")


def without_javascript(t):
    page = t.desktop(javascript=False)
    page.sign_in("employee:anna")
    page.goto("/meetings")
    t.check(page.locator(SELECT).is_visible() and not page.locator(FORM).is_visible(),
            "without JavaScript the field is a select")
    page.fill("#meetings_create-customer-find", "bjorn")
    page.locator("form[data-tool=meetings_create] button[name=tun-find]").click()
    page.wait_for_load_state()
    labels = page.locator(f"{SELECT} option").all_inner_texts()
    found = page.locator(".tun-choice-input-found").inner_text()
    t.check(labels[1:] == ["Bjørn Åsen"] and found == "1 found",
            f"«Find» shows the form again with the match in the select: {labels} {found}")
    t.check(page.locator(".tun-error-summary").count() == 0, "nothing was saved or refused")
    page.locator(SELECT).select_option(label="Bjørn Åsen")
    page.fill("#meetings_create-name", "Planned without scripts")
    page.locator(SAVE).click()
    page.wait_for_url(re.compile(r"/meetings/mtg_"), timeout=5000)
    t.check("Bjørn Åsen" in page.locator(".tun-summary-list").inner_text(),
            "saving posts the chosen customer's id")

    page = t.phone(javascript=False)
    page.sign_in("employee:anna")
    page.goto("/meetings")
    page.locator(FILTER_BUTTON).click()
    page.wait_for_timeout(300)
    page.fill("#tun-list-toolbar-customer-find", "nordvik")
    page.locator("[data-tun-list-toolbar-apply]").click()
    page.wait_for_url(re.compile(r"customer-find=nordvik"), timeout=5000)
    page.locator(FILTER_BUTTON).click()
    page.locator("#tun-list-toolbar-customer-choice").select_option(label="Nordvik Bakery Ltd")
    page.locator("[data-tun-list-toolbar-apply]").click()
    page.wait_for_url(re.compile(r"customer=cus_"), timeout=5000)
    titles = page.locator(".tun-table tbody tr td:first-child").all_inner_texts()
    t.check(titles == ["Bread van signage"], f"the filter's «Find» and «Apply» filter the list: {titles}")


def file_field(t):
    for width in (320, 360, 390):
        page = t.phone(width=width)
        page.sign_in("employee:anna")
        page.goto("/items/new")
        page.wait_for_timeout(300)
        boxes = page.evaluate(FILE_BOXES)
        column = boxes["column"]
        inside = all(boxes[part]["left"] >= column["left"] - 0.5
                     and boxes[part]["right"] <= column["right"] + 0.5
                     for part in ("zone", "control"))
        t.check(inside and column["right"] <= boxes["window"],
                f"{width}px: the file field's zone and control end inside its column: {boxes}")
        t.check(not page.evaluate(WIDE_PAGE), f"{width}px: «New item» does not scroll sideways")


def specimen(t):
    page = t.desktop()
    page.goto("/ui/choice-input")
    page.wait_for_function("() => document.querySelector('[data-tun-choice][data-tun-ready]')")
    shown = page.locator("#specimen-found-text").inner_text()
    t.check(shown == "Bjørn Åsen" and not page.locator("#specimen-found-find").is_visible(),
            f"where scripts run, the find step's example is a chosen field: {shown!r}")


def pictures(t):
    """The meetings' form and list at 390 and 1280 px, light and dark: the
    field and the filter closed, open while typing, and in use."""
    for scheme in ("light", "dark"):
        for width, make in ((390, t.phone), (1280, t.desktop)):
            page = open_meetings(t, make=make, scheme=scheme)
            page.screenshot(path=str(t.out / f"generated-choice-list-{width}-{scheme}.png"))
            page.locator("#new").scroll_into_view_if_needed()
            page.wait_for_timeout(200)
            page.screenshot(path=str(t.out / f"generated-choice-form-{width}-{scheme}.png"))
            page.locator(FORM).click()
            wait_answered(page, "")
            page.keyboard.type("bjorn")
            wait_answered(page, "bjorn")
            page.wait_for_timeout(300)
            page.screenshot(path=str(t.out / f"generated-choice-field-{width}-{scheme}.png"))
            page.keyboard.press("Enter")
            page.wait_for_timeout(300)
            chosen = state(page)["chosen"]
            page.locator(FORM).scroll_into_view_if_needed()
            page.screenshot(path=str(t.out / f"generated-choice-chosen-{width}-{scheme}.png"))
            page.goto(f"/meetings?customer={chosen}")
            page.wait_for_timeout(400)
            # One filter: no «Filters» sheet, its own popover on a phone too.
            page.locator(FILTER_BUTTON).click()
            wait_answered(page, "", FILTER_FIELD)
            page.keyboard.type("berg")
            wait_answered(page, "berg", FILTER_FIELD)
            page.wait_for_timeout(300)
            page.screenshot(path=str(t.out / f"generated-choice-filter-{width}-{scheme}.png"))
            t.check(True, f"{width}px {scheme}: pictures of the meetings' field and filter")
    for width in (320, 390):
        page = t.phone(width=width)
        page.sign_in("employee:anna")
        page.goto("/items/new")
        page.wait_for_timeout(300)
        page.screenshot(path=str(t.out / f"generated-choice-file-{width}.png"))


def run(t):
    form(t)
    filter_(t)
    without_javascript(t)
    file_field(t)
    specimen(t)
    pictures(t)
