"""A form's alert naming its fields by their labels, and Enter saving in a
form with an asked choice without JavaScript, on the showcase's «New item»
(written by hand, its alert given its fields) and the generated «Meetings»,
with 405 customers: the alert's lines «Title must be filled in» and
«Reported on must be a date …», in English and Norwegian, at 390 and 1280
px, each a link to its field with and without JavaScript; with JavaScript
off, Enter in the title of either form saving it, and «Find» still finding;
with it on, Enter saving too; and a generated form's empty customer «Customer
must be chosen» (spec/ui.md 6, choice-input, «Enter saves»; 8, «Forms», «A
client's pages»)."""

import re

SCENARIO = "choices"

WIDE_PAGE = "() => document.scrollingElement.scrollWidth > document.documentElement.clientWidth + 1"

ALERT = ".tun-alert[data-code=invalid_input]"
SUBMIT = "form[action='/items/new'] button[type=submit]:not([name]):not(.tun-choice-input-default)"
MEETINGS = "form[data-tool=meetings_create]"

# The lines of the alert, each its text and the id its link names.
LINES = """(selector) => [...document.querySelectorAll(`${selector} li`)].map((li) => {
  const link = li.querySelector('a');
  return {text: li.textContent.trim(), target: link ? link.hash.slice(1) : null};
})"""


def refused_item(page):
    """Post «New item» with no title and a date no one can read; the lines
    of its alert."""
    page.goto("/items/new")
    page.fill("input[name=reported_on]", "32.13.2026")
    page.locator(SUBMIT).click()
    page.wait_for_selector(ALERT, timeout=5000)
    return page.evaluate(LINES, ALERT)


def alert_names_fields(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    lines = refused_item(page)
    texts = [line["text"] for line in lines]
    t.check(texts[0] == "Title must be filled in"
            and texts[1].startswith("Reported on must be a date"),
            f"the alert names the fields by their labels: {texts}")
    t.check(all(line["target"] for line in lines), f"each line is a link to its field: {lines}")
    title = page.locator("input[name=title]").get_attribute("id")
    t.check(lines[0]["target"] == title, "the title's line links to the title's field")
    page.locator(f"{ALERT} a").first.click()
    page.wait_for_timeout(200)
    focused = page.evaluate("() => document.activeElement.id")
    t.check(focused == title,
            f"with JavaScript, pressing a line puts the focus in its field: {focused}")
    page.locator(f"{ALERT} a").nth(1).click()
    page.wait_for_timeout(200)
    focused = page.evaluate("() => document.activeElement.name")
    t.check(focused == "reported_on", f"the date's line focuses the date's field: {focused}")

    page = t.desktop(javascript=False)
    page.sign_in("employee:anna")
    lines = refused_item(page)
    page.locator(f"{ALERT} a").nth(1).click()
    page.wait_for_timeout(200)
    hash_ = page.evaluate("() => location.hash.slice(1)")
    t.check(hash_ == lines[1]["target"] and hash_,
            f"without JavaScript, the browser goes to the field: #{hash_}")

    page = t.phone()
    page.sign_in("employee:anna")
    refused_item(page)
    t.check(not page.evaluate(WIDE_PAGE), "390px: the alert does not widen the page")


def enter_saves(t):
    page = t.desktop(javascript=False)
    page.sign_in("employee:anna")
    page.goto("/items/new")
    page.fill("input[name=title]", "Saved by Enter")
    page.press("input[name=title]", "Enter")
    page.wait_for_load_state()
    t.check(re.search(r"/items/crd_", page.url) is not None,
            f"without JavaScript, Enter in «New item»'s title saves the item: {page.url}")

    page.goto("/items/new")
    page.fill("#card-customer-find", "bjorn")
    page.locator("form[action='/items/new'] button[name=tun-find]").click()
    page.wait_for_load_state()
    labels = page.locator("select#card-customer option").all_inner_texts()
    t.check(labels[1:2] == ["Bjørn Åsen"], f"«Find» still finds: {labels}")

    page.goto("/meetings")
    page.fill("#meetings_create-customer-find", "bjorn")
    page.locator(f"{MEETINGS} button[name=tun-find]").click()
    page.wait_for_load_state()
    labels = page.locator("select#meetings_create-customer option").all_inner_texts()
    t.check(labels[1:] == ["Bjørn Åsen"], f"the generated form's «Find» still finds: {labels}")
    page.locator("select#meetings_create-customer").select_option(label="Bjørn Åsen")
    page.fill("#meetings_create-name", "Planned with Enter")
    page.press("#meetings_create-name", "Enter")
    page.wait_for_load_state()
    t.check(re.search(r"/meetings/mtg_", page.url) is not None
            and "Planned with Enter" in page.content(),
            f"without JavaScript, Enter in the generated form's title saves the meeting: "
            f"{page.url}")

    page.goto("/meetings")
    page.fill("#meetings_create-name", "No one chosen")
    page.press("#meetings_create-name", "Enter")
    page.wait_for_load_state()
    summary = page.locator(".tun-error-summary").inner_text()
    t.check("Customer must be chosen" in summary,
            f"a generated form's empty customer must be chosen: {summary!r}")

    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/items/new")
    page.wait_for_function("() => document.querySelector('[data-tun-choice][data-tun-ready]')")
    page.fill("input[name=title]", "Saved by Enter with scripts")
    page.press("input[name=title]", "Enter")
    page.wait_for_url(re.compile(r"/items/crd_"), timeout=5000)
    t.check(True, "with JavaScript, Enter in «New item»'s title saves the item too")


def set_norwegian(page):
    page.goto("/settings")
    language = "#setting-locale-language"
    page.locator(language).select_option(label="Norsk (bokmål)")
    form = page.locator("form").filter(has=page.locator(language))
    form.get_by_role("button", name="Save", exact=True).click()
    page.wait_for_url(re.compile(r"/settings\?saved=locale\.language$"))


def pictures(t):
    """The refused «New item» at 390 and 1280 px, light and dark, in
    English, then in Norwegian."""
    for language in ("en", "nb"):
        if language == "nb":
            page = t.desktop()
            page.sign_in("admin:jonas")
            set_norwegian(page)
        for scheme in ("light", "dark"):
            for width, make in ((390, t.phone), (1280, t.desktop)):
                page = make(scheme=scheme)
                page.sign_in("employee:anna")
                lines = refused_item(page)
                page.locator(ALERT).scroll_into_view_if_needed()
                page.wait_for_timeout(300)
                name = f"form-nits-alert-{width}-{scheme}-{language}.png"
                page.screenshot(path=str(t.out / name))
                if language == "nb":
                    texts = [line["text"] for line in lines]
                    t.check(texts[0] == "Tittel må fylles ut"
                            and texts[1].startswith("Meldt må være"),
                            f"{width}px {scheme}: in Norwegian by the Norwegian labels: {texts}")
                else:
                    t.check(True, f"{width}px {scheme}: a picture of the alert")


def run(t):
    alert_names_fields(t)
    enter_saves(t)
    pictures(t)
