"""A strict combobox, in a card, finds an item by part of its title: on a
phone, a tap opens every option over the page, typing narrows them and a tap
picks one, which lets
«Open» be pressed; on a desktop, the arrow keys and Enter pick, Escape
closes, and a title typed in full counts; a form htmx swapped in works the
same; without the script the browser's own list stands in; and the table
under it leaves the status out on a phone (spec/ui.md 6)."""

import re

INPUT = ".tun-combobox-input"
LISTBOX = ".tun-combobox [role=listbox]"


def shown(page):
    """The texts of the options the list shows now."""
    return page.locator(f"{LISTBOX} [role=option]").evaluate_all(
        "all => all.filter(o => !o.hidden).map(o => o.textContent)")


def is_open(page):
    # Open, not leaving: a list that closes stays in sight while it fades.
    return page.locator(LISTBOX).evaluate("(list) => list.matches(':popover-open')")


def on_screen(page):
    """Whether the first option shown is inside the window and on top at its
    centre: Playwright counts an option a card cuts off as visible."""
    return page.locator(LISTBOX).evaluate("""list => {
      const option = [...list.querySelectorAll('[role=option]')].find(o => !o.hidden);
      if (!option) return false;
      const box = option.getBoundingClientRect();
      const x = box.left + box.width / 2, y = box.top + box.height / 2;
      return box.height > 0 && y > 0 && y < innerHeight && x > 0 && x < innerWidth
        && option.contains(document.elementFromPoint(x, y));
    }""")


def open_button(page):
    return page.get_by_role("button", name="Open", exact=True)


def status_shown(page):
    """Whether the first row's status cell is shown."""
    return page.locator("td[data-narrow='false']").first.evaluate(
        "td => getComputedStyle(td).display !== 'none'")


def run(t):
    phone = t.phone()
    phone.sign_in("employee:anna")
    phone.goto("/find")
    t.check(open_button(phone).is_disabled(), "phone: «Open» waits for an item")
    t.check(not is_open(phone), "phone: the list starts closed")
    phone.locator(INPUT).tap()
    t.check(is_open(phone) and len(shown(phone)) == 30, f"phone: a tap shows all 30: {len(shown(phone))}")
    t.check(on_screen(phone), "phone: on top of the page, not cut off by the card")
    t.check(phone.locator(INPUT).get_attribute("aria-expanded") == "true", "phone: aria-expanded")
    phone.keyboard.type("ACC")
    t.check(shown(phone) == ["Export to accounting"], f"phone: «ACC» narrows it: {shown(phone)}")
    t.check(on_screen(phone), "phone: the one left is on screen")
    t.check(open_button(phone).is_disabled(), "phone: a part of a title is not an item")
    phone.locator(f"{LISTBOX} [role=option]", has_text="Export to accounting").tap()
    t.check(phone.locator(INPUT).input_value() == "Export to accounting", "phone: a tap picks it")
    t.check(not is_open(phone), "phone: and closes the list")
    t.check(open_button(phone).is_enabled(), "phone: «Open» can be pressed")
    phone.locator(INPUT).fill("")
    phone.keyboard.type("nothing like it")
    t.check(shown(phone) == [] and phone.get_by_text("No match").is_visible(),
            "phone: «No match» when nothing holds the text")
    t.check(open_button(phone).is_disabled(), "phone: and «Open» waits again")
    t.check(not status_shown(phone), "phone: the table leaves the status out")
    t.check(phone.evaluate("document.scrollingElement.scrollWidth <= innerWidth + 1"),
            "phone: the page fits the screen's width")
    phone.screenshot(path=".build/checks/combobox-phone.png")

    desktop = t.desktop()
    desktop.sign_in("employee:anna")
    desktop.goto("/find")
    t.check(status_shown(desktop), "desktop: the table keeps the status")
    desktop.locator(INPUT).focus()
    t.check(is_open(desktop) and on_screen(desktop), "desktop: focus opens the list, on screen")
    desktop.keyboard.type("item 2")
    t.check(shown(desktop) == ["Item 2", "Item 20", "Item 21", "Item 22", "Item 23", "Item 24",
                               "Item 25"], f"desktop: ignoring case: {shown(desktop)}")
    desktop.keyboard.press("ArrowDown")
    desktop.keyboard.press("ArrowDown")
    active = desktop.locator(INPUT).get_attribute("aria-activedescendant")
    t.check(active and desktop.locator(f"#{active}").inner_text() == "Item 20",
            f"desktop: the arrow keys move through the options: {active}")
    desktop.keyboard.press("Enter")
    t.check(desktop.locator(INPUT).input_value() == "Item 20" and not is_open(desktop),
            "desktop: Enter picks it and closes the list")
    t.check(open_button(desktop).is_enabled(), "desktop: «Open» can be pressed")
    desktop.keyboard.type("x")
    t.check(is_open(desktop) and open_button(desktop).is_disabled(),
            "desktop: typing opens it again, and «Open» waits")
    desktop.keyboard.press("Escape")
    t.check(not is_open(desktop), "desktop: Escape closes it")
    desktop.keyboard.press("Backspace")
    desktop.keyboard.press("Backspace")
    t.check(desktop.locator(INPUT).input_value() == "Item 2" and open_button(desktop).is_enabled(),
            "desktop: a title typed in full counts")

    # A page that still offers «Open» for a title no longer there: the
    # server refuses it, htmx swaps the answer in, and its combobox works.
    desktop.locator(INPUT).fill("Item 99")
    desktop.evaluate("""() => { const b = [...document.querySelectorAll('button[type=submit]')]
                                  .find(b => b.textContent.includes('Open'));
                                b.disabled = false; b.click(); }""")
    desktop.get_by_text("Choose an item from the list").first.wait_for()
    t.check(desktop.locator(INPUT).get_attribute("list") is None,
            "desktop: the swapped-in field draws its own list")
    t.check(open_button(desktop).is_disabled(), "desktop: and holds «Open» back for «Item 99»")
    desktop.locator(INPUT).focus()
    desktop.keyboard.press("Control+a")
    desktop.keyboard.type("typo")
    desktop.keyboard.press("ArrowDown")
    desktop.keyboard.press("Enter")
    t.check(desktop.locator(INPUT).input_value() == "Fix a typo", "desktop: it picks as before")
    open_button(desktop).click()
    desktop.wait_for_url(re.compile(r"/items/crd_"))
    t.check(desktop.locator("h1").inner_text().strip() == "Fix a typo", "desktop: «Open» opens it")

    plain = t.phone(javascript=False)
    plain.sign_in("employee:anna")
    plain.goto("/find")
    field = plain.locator(INPUT)
    t.check(field.get_attribute("list") == plain.locator("datalist").get_attribute("id"),
            "without the script: the browser's own list")
    t.check(plain.locator("datalist option").count() == 30, "with every option")
    t.check(open_button(plain).is_enabled(), "and «Open» is not held back")
    t.check(not plain.locator(LISTBOX).is_visible(), "and the script's list stays hidden")
