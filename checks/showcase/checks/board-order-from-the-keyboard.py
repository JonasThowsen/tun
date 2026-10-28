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
    return f"items-{card_id(page, title)}-move-trigger"


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
    with page.expect_post("/items/move") as post:
        page.keyboard.press("Enter")
    page.wait_for_timeout(500)
    return post


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/items")

    post = choose(page, "Item 2", "Move up")
    t.check("column=new" in post.body and f"before={card_id(page, 'Item 1')}" in post.body,
            f"«Move up» posts the card above as before=: {post.body}")
    t.check(titles(page, "new")[1:3] == ["Item 2", "Item 1"],
            f"the answer has the card one place up: {titles(page, 'new')[:4]}")
    t.check(page.evaluate("document.activeElement.id") == trigger(page, "Item 2"),
            "focus is on its menu button")
    t.check(status(page) == "Moved “Item 2” to place 2 of 26 in New.",
            f"and the board says where it went: «{status(page)}»")

    post = choose(page, "Item 2", "Move to the bottom")
    t.check("before=&" in post.body + "&", f"«Move to the bottom» posts before= empty: {post.body}")
    t.check(titles(page, "new")[-1] == "Item 2", "and the card is last")
    t.check(status(page) == "Moved “Item 2” to place 26 of 26 in New.", f"«{status(page)}»")

    post = choose(page, "Item 2", "Planned")
    t.check("column=planned" in post.body and "before=&" in post.body + "&",
            f"«Move to» posts the column and before= empty: {post.body}")
    t.check(titles(page, "planned")[-1] == "Item 2", f"it is last there: {titles(page, 'planned')}")
    t.check(page.evaluate("document.activeElement.id") == trigger(page, "Item 2"),
            "focus is on its menu button, in its new column")
    t.check(status(page) == "Moved “Item 2” to place 4 of 4 in Planned.", f"«{status(page)}»")

    before = titles(page, "new")
    other = card_id(page, "New page for invoices")
    page.evaluate(f"document.querySelector('#items-{card_id(page, 'Item 3')}-form "
                  f"[data-tun-board-before]').value = '{other}'")
    post = choose(page, "Item 3", "In progress")
    t.check(post.status == 409, f"a before= in another column is refused: {post.status} {post.body}")
    t.check(titles(page, "new") == before, "the answer is the board as it was")
    t.check("The card was not moved" in page.locator(".tun-board-message").text_content(),
            "with the error above the columns")
    t.check(status(page) == "", f"and nothing said about a move: «{status(page)}»")
