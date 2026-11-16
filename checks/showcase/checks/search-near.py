"""A word typed wrong still finds, below every exact hit (spec/ui.md 6.4,
«Near matches»): the kit script's rule answers the table of cases the
server answers, the search dialog finds by a misspelled word with the whole
word marked and the exact results first, and a choice's given options are
narrowed the same way, the exact ones first (spec/ui.md 6, choice-input)."""

import json
import pathlib

SCENARIO = "search"

DIALOG = "dialog#tun-search"
FIELD = "#tun-search-field"
GIVEN = "#specimen-given-search"

CASES = json.loads((pathlib.Path(__file__).resolve().parents[3] / "tests" / "search-cases.json")
                   .read_text(encoding="utf-8"))["cases"]

RESULTS = """() => [...document.querySelectorAll('dialog#tun-search [role=option]')].map((row) => ({
  title: row.querySelector('.tun-search-results-title').textContent,
  marks: [...row.querySelectorAll('mark')].map((m) => m.textContent),
  selected: row.getAttribute('aria-selected')}))"""

GIVEN_STATE = """(selector) => {
  const root = document.querySelector(selector).closest('[data-tun-choice]');
  const field = root.querySelector('[data-tun-choice-field]');
  const options = [...root.querySelectorAll('[data-tun-choice-list] [role=option]')]
    .filter((o) => !o.hidden);
  const active = options.find((o) => o.getAttribute('aria-selected') === 'true');
  return {texts: options.map((o) => o.querySelector('.tun-choice-options-text').textContent),
          active: active ? options.indexOf(active) : -1,
          activedescendant: field.getAttribute('aria-activedescendant'),
          activeId: active ? active.id : null,
          chosen: root.querySelector('[data-tun-choice-select]').value};
}"""


def wait_shown(page, text):
    page.wait_until(
        """(text) => document.querySelector('dialog#tun-search [data-tun-search-query]')
                       ?.getAttribute('data-tun-search-query') === text""", text,
        what=f"the search's answer for «{text}»")


def ask(page, text):
    page.fill(FIELD, "")
    page.keyboard.type(text)
    wait_shown(page, text)
    page.wait_for_timeout(200)
    return page.evaluate(RESULTS)


def rule(t):
    page = t.desktop()
    page.goto("/ui/choice-input")
    page.wait_for_function("() => typeof tunSearchFinds === 'function'")
    found = page.evaluate("(cases) => cases.map(([typed, text]) => tunSearchFinds(typed, text))",
                          CASES)
    wrong = [(typed, text, expected, got) for (typed, text, expected), got in zip(CASES, found)
             if (got or "none") != expected]
    t.check(len(CASES) >= 40 and not wrong,
            f"the script answers the {len(CASES)} cases of tests/search-cases.json as the server: {wrong}")


def dialog(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards")
    page.keyboard.press("Control+k")
    page.wait_until("""() => document.activeElement === document.querySelector('#tun-search-field')""",
                    what="the search open with the focus in its field")
    rows = ask(page, "nordvk")
    t.check(rows and rows[0]["title"] == "Nordvik Bakery Ltd" and rows[0]["marks"] == ["Nordvik"],
            f"«nordvk» finds Nordvik Bakery Ltd, «Nordvik» marked whole: {rows}")
    t.check(rows[0]["selected"] == "true", "and marks its row, for Enter")
    rows = ask(page, "catring")
    t.check([r["title"] for r in rows] == ["Berg Catering"] and rows[0]["marks"] == ["Catering"],
            f"«catring» finds Berg Catering, «Catering» marked: {rows}")
    rows = ask(page, "hansen")
    titles = [r["title"] for r in rows]
    t.check("Hansen Plumbing" in titles and "Hanssen Rigging" in titles
            and titles.index("Hansen Plumbing") < titles.index("Hanssen Rigging"),
            f"«hansen»: Hansen Plumbing, found exactly, before Hanssen Rigging, found nearly: {titles}")
    near = rows[titles.index("Hanssen Rigging")]
    exact = rows[titles.index("Hansen Plumbing")]
    t.check(near["marks"] == ["Hanssen"] and exact["marks"] == ["Hansen"],
            f"each marked: {exact['marks']} {near['marks']}")
    rows = ask(page, "zebra")
    t.check(rows == [], "«zebra», five letters, still finds nothing")
    page.keyboard.press("Escape")


def given(t):
    page = t.desktop()
    page.goto("/ui/choice-input")
    page.wait_for_function("() => document.querySelector('#specimen-given-trigger')")
    page.locator("#specimen-given-trigger").click()
    page.wait_for_timeout(300)
    all_texts = page.evaluate(GIVEN_STATE, GIVEN)["texts"]
    t.check(all_texts[-1] == "Nordvika Marina", f"the given options end with Nordvika Marina: {all_texts}")
    for text, expected in (("nordvika", ["Nordvika Marina", "Nordvik Bakery Ltd"]),
                           ("nordvk", ["Nordvik Bakery Ltd", "Nordvika Marina"]),
                           ("hansen", ["Hansen Plumbing", "Kari Hansen"]),
                           ("bicycel", ["Tromsø Bicycle Workshop"])):
        page.fill(GIVEN, "")
        page.keyboard.type(text)
        s = page.evaluate(GIVEN_STATE, GIVEN)
        t.check(s["texts"] == expected and s["active"] == 0 and s["activedescendant"] == s["activeId"],
                f"«{text}» shows {expected}, the first active: {s}")
    page.fill(GIVEN, "")
    page.keyboard.type("nordvika")
    page.keyboard.press("ArrowDown")
    s = page.evaluate(GIVEN_STATE, GIVEN)
    t.check(s["active"] == 1 and s["activedescendant"] == s["activeId"],
            f"↓ moves to the option found nearly, in the order shown: {s}")
    page.keyboard.press("Enter")
    page.wait_for_timeout(300)
    s = page.evaluate(GIVEN_STATE, GIVEN)
    t.check(s["chosen"] == "cus_1", f"Enter chooses it: {s['chosen']}")
    page.locator("#specimen-given-trigger").click()
    page.wait_for_timeout(300)
    s = page.evaluate(GIVEN_STATE, GIVEN)
    t.check(s["texts"] == all_texts, f"opened again, every option in the order given: {s['texts']}")


def pictures(t):
    """The search found by a misspelled word, and by a word that finds one
    customer exactly and another nearly, at 390 and 1280 px, light and dark;
    the given options for «nordvika»."""
    for scheme in ("light", "dark"):
        for width, make in ((390, t.phone), (1280, t.desktop)):
            page = make(scheme=scheme)
            page.sign_in("employee:anna")
            page.goto("/cards")
            page.wait_for_timeout(400)
            if width == 390:
                page.locator(".tun-app-shell-bar > [data-tun-search-open]").click()
            else:
                page.keyboard.press("Control+k")
            page.wait_for_timeout(500)
            page.keyboard.type("nordvk")
            wait_shown(page, "nordvk")
            page.wait_for_timeout(300)
            page.screenshot(path=str(t.out / f"search-near-nordvk-{width}-{scheme}.png"))
            page.fill(FIELD, "")
            page.keyboard.type("hansen")
            wait_shown(page, "hansen")
            page.wait_for_timeout(300)
            page.screenshot(path=str(t.out / f"search-near-hansen-{width}-{scheme}.png"))
            page = make(scheme=scheme)
            page.goto("/ui/choice-input")
            page.wait_for_function("() => document.querySelector('#specimen-given-trigger')")
            page.locator("#specimen-given-trigger").click()
            page.wait_for_timeout(400)
            page.keyboard.type("nordvika")
            page.wait_for_timeout(300)
            page.screenshot(path=str(t.out / f"search-near-given-{width}-{scheme}.png"))
            t.check(True, f"{width}px {scheme}: pictures of the search and the given options")


def run(t):
    rule(t)
    dialog(t)
    given(t)
    pictures(t)
