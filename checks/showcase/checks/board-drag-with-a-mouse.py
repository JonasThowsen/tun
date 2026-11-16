"""With a mouse, a card dragged to another column moves there, one dragged to
the board's edge scrolls the columns steadily, and Escape puts a card back
(spec/ui.md 6.1)."""


def column_of(page, title):
    return page.card(title).evaluate("card => card.closest('[data-tun-board-column]').dataset.tunBoardColumn")


def drag(page, title, x, y):
    box = page.card(title).bounding_box()
    page.mouse.move(box["x"] + 30, box["y"] + 20)
    page.mouse.down()
    page.mouse.move(box["x"] + 60, box["y"] + 20, steps=4)
    page.mouse.move(x, y, steps=10)


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/items")
    target = page.column("planned").bounding_box()
    drag(page, "Item 1", target["x"] + target["width"] / 2, target["y"] + 80)
    t.check(page.locator("[data-tun-board-ghost]").count() == 1, "a copy of the card follows the pointer")
    t.check(column_of(page, "Item 1") == "planned", "the card moves while it is dragged")
    with page.expect_htmx(), page.expect_post("/items/move") as post:
        page.mouse.up()
    t.check("column=planned" in post.body, f"the drop moves it: {post.body}")
    t.check(page.url.endswith("/items"), "without following the card's link")
    t.check(page.locator("[data-tun-board-ghost]").count() == 0, "the copy is gone")

    narrow = t.desktop(760, 800)
    narrow.sign_in("employee:anna")
    narrow.goto("/items")
    box = narrow.locator(".tun-board-columns").bounding_box()
    drag(narrow, "Item 2", box["x"] + box["width"] - 10, box["y"] + 200)
    first = narrow.evaluate("document.querySelector('.tun-board-columns').scrollLeft")
    last = narrow.wait_until("(first) => { const left = document.querySelector('.tun-board-columns').scrollLeft;"
                             " return left > first + 24 && left; }", first,
                             what="the columns to scroll on at the board's edge")
    t.check(first < last, f"at the board's edge the columns scroll steadily: {first} → {last}")
    narrow.keyboard.press("Escape")
    narrow.mouse.up()
    t.check(column_of(narrow, "Item 2") == "new", "Escape puts the card back")
