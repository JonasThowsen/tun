"""On a phone, an admin sets the tenant's language to Norwegian on
«Settings», and the next pages are Norwegian: the menu, a board's move
menu, a date and an amount; set back to English, they read English again
(spec/i18n.md 2.3, 5.4, 6.2)."""

import re

LANGUAGE = "#setting-locale-language"


def set_language(page, name, save):
    """Choose the language NAME on «Settings» and press its button SAVE;
    wait for the page it sends the browser back to."""
    page.goto("/settings")
    page.locator(LANGUAGE).select_option(label=name)
    form = page.locator("form").filter(has=page.locator(LANGUAGE))
    form.get_by_role("button", name=save, exact=True).click()
    page.wait_for_url(re.compile(r"/settings\?saved=locale\.language$"))
    page.wait_for_load_state()


def menu_labels(page, button):
    """The labels of the main menu, opened with its button BUTTON."""
    page.get_by_role("button", name=button, exact=True).click()
    nav = page.locator(".tun-nav-list")
    nav.first.wait_for()
    return [label.strip() for label in nav.locator(".tun-nav-list-label").all_inner_texts()]


def move_menu(page, title):
    """The text of the card TITLE's move menu on the board, opened by a tap."""
    page.goto("/items")
    card = page.card(title).get_attribute("data-tun-board-card")
    page.locator(f"#items-{card}-move-trigger").tap()
    menu = page.locator(".tun-dropdown-menu-content:popover-open")
    menu.wait_for()
    return menu.inner_text()


def card_date(page, title):
    """The date the board shows on the card TITLE."""
    return page.card(title).locator(".tun-board-card-meta").inner_text().strip()


def card_estimate(page, title):
    """What the board shows under the card TITLE, with its spaces plain."""
    page.goto("/items")
    return card_date(page, title).replace("\xa0", " ")


ESTIMATE = "Export to accounting"


def run(t):
    page = t.phone()
    page.sign_in("admin:jonas")
    page.goto("/items")
    t.check(page.evaluate("document.documentElement.lang") == "en",
            "the showcase starts in English")
    t.check(re.fullmatch(r"\d{1,2} [A-Z][a-z]{2} \d{4}", card_date(page, "Item 1")),
            f"with dates such as 21 Oct 2026: «{card_date(page, 'Item 1')}»")
    text = card_estimate(page, ESTIMATE)
    t.check("€12,500.00" in text, f"and amounts such as €12,500.00: {text!r}")

    set_language(page, "Norsk (bokmål)", "Save")
    t.check(page.evaluate("document.documentElement.lang") == "nb",
            "the page the save leads to is loaded whole, so it says its new language")
    labels = menu_labels(page, "Meny")
    t.check("Innstillinger" in labels,
            f"set to Norwegian, the menu reads «Innstillinger»: {labels}")
    t.check("Saker" in labels, f"and names the showcase's own pages in Norwegian: {labels}")
    text = move_menu(page, "Item 1")
    t.check(page.evaluate("document.documentElement.lang") == "nb", "a page loaded is Norwegian")
    t.check("Flytt til" in text, f"a card's menu reads «Flytt til»: {text!r}")
    t.check("Planlagt" in text, f"with the columns' Norwegian names: {text!r}")
    t.check(re.fullmatch(r"\d{2}\.\d{2}\.\d{4}", card_date(page, "Item 1")),
            f"a date reads as 21.10.2026: «{card_date(page, 'Item 1')}»")
    text = card_estimate(page, ESTIMATE)
    t.check("12 500,00 €" in text,
            f"an amount reads as 12 500,00 €: {text!r}")

    set_language(page, "English", "Lagre")
    labels = menu_labels(page, "Menu")
    t.check("Settings" in labels and "Items" in labels,
            f"set back to English, the menu reads «Settings»: {labels}")
    text = move_menu(page, "Item 1")
    t.check(page.evaluate("document.documentElement.lang") == "en", "a page loaded is English")
    t.check("Move to" in text and "Planned" in text, f"a card's menu reads «Move to»: {text!r}")
    t.check(card_date(page, "Item 1") == "21 Oct 2026",
            f"and the date reads 21 Oct 2026: «{card_date(page, 'Item 1')}»")
    text = card_estimate(page, ESTIMATE)
    t.check("€12,500.00" in text, f"and the amount €12,500.00: {text!r}")
