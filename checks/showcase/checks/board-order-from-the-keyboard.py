"""From the keyboard, a card's menu moves it up, to the bottom of its column
and to the end of another column; focus stays on its menu button, the board
says where it went, and a refused move says nothing there (spec/ui.md
6.1)."""


def titles(page, key):
    return page.column(key).locator(".tun-board-cards > [data-tun-board-card] .tun-board-card-title") \
        .all_text_contents()


def card_id(page, title):
    return page.card(title).get_attribute("data-tun-board-card")


def status(page):
    return page.locator("[data-tun-board-status]").text_content().strip()


def trigger(page, title):
    return f"saker-{card_id(page, title)}-move-trigger"


def choose(page, title, label):
    """Open TITLE's menu with Enter from its focused button, go down to LABEL
    with the arrow keys and choose it with Enter; answer what was posted."""
    page.locator(f"#{trigger(page, title)}").focus()
    page.keyboard.press("Enter")
    page.locator(".tun-dropdown-menu-content:popover-open").wait_for()
    # Each key press moves focus after it returns: wait until it has moved
    # into the menu, and on after each arrow, before reading where it is.
    page.wait_for_function(
        "document.activeElement.closest('.tun-dropdown-menu-content:popover-open') !== null")
    for _ in range(12):
        focused = page.evaluate("document.activeElement.textContent.trim()")
        if focused == label:
            break
        page.keyboard.press("ArrowDown")
        page.wait_for_function("(before) => document.activeElement.textContent.trim() !== before",
                               arg=focused)
    with page.expect_post("/saker/flytt") as post:
        page.keyboard.press("Enter")
    page.wait_for_timeout(500)
    return post


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/saker")

    post = choose(page, "Sak nummer 2", "Flytt opp")
    t.check("column=ny" in post.body and f"before={card_id(page, 'Sak nummer 1')}" in post.body,
            f"«Flytt opp» posts the card above as before=: {post.body}")
    t.check(titles(page, "ny")[1:3] == ["Sak nummer 2", "Sak nummer 1"],
            f"the answer has the card one place up: {titles(page, 'ny')[:4]}")
    t.check(page.evaluate("document.activeElement.id") == trigger(page, "Sak nummer 2"),
            "focus is on its menu button")
    t.check(status(page) == "Flyttet «Sak nummer 2» til plass 2 av 26 i Ny.",
            f"and the board says where it went: «{status(page)}»")

    post = choose(page, "Sak nummer 2", "Flytt nederst")
    t.check("before=&" in post.body + "&", f"«Flytt nederst» posts before= empty: {post.body}")
    t.check(titles(page, "ny")[-1] == "Sak nummer 2", "and the card is last")
    t.check(status(page) == "Flyttet «Sak nummer 2» til plass 26 av 26 i Ny.", f"«{status(page)}»")

    post = choose(page, "Sak nummer 2", "Planlagt")
    t.check("column=planlagt" in post.body and "before=&" in post.body + "&",
            f"«Flytt til» posts the column and before= empty: {post.body}")
    t.check(titles(page, "planlagt")[-1] == "Sak nummer 2", f"it is last there: {titles(page, 'planlagt')}")
    t.check(page.evaluate("document.activeElement.id") == trigger(page, "Sak nummer 2"),
            "focus is on its menu button, in its new column")
    t.check(status(page) == "Flyttet «Sak nummer 2» til plass 4 av 4 i Planlagt.", f"«{status(page)}»")

    before = titles(page, "ny")
    other = card_id(page, "Ny side for fakturaer")
    page.evaluate(f"document.querySelector('#saker-{card_id(page, 'Sak nummer 3')}-form "
                  f"[data-tun-board-before]').value = '{other}'")
    post = choose(page, "Sak nummer 3", "Under arbeid")
    t.check(post.status == 409, f"a before= in another column is refused: {post.status} {post.body}")
    t.check(titles(page, "ny") == before, "the answer is the board as it was")
    t.check("Kortet ble ikke flyttet" in page.locator(".tun-board-message").text_content(),
            "with the error above the columns")
    t.check(status(page) == "", f"and nothing said about a move: «{status(page)}»")
