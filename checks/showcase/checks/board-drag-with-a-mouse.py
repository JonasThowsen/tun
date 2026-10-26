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
    page.goto("/saker")
    target = page.column("planlagt").bounding_box()
    drag(page, "Sak nummer 1", target["x"] + target["width"] / 2, target["y"] + 80)
    t.check(page.locator("[data-tun-board-ghost]").count() == 1, "a copy of the card follows the pointer")
    t.check(column_of(page, "Sak nummer 1") == "planlagt", "the card moves while it is dragged")
    with page.expect_post("/saker/flytt") as post:
        page.mouse.up()
    page.wait_for_timeout(300)
    t.check("column=planlagt" in post.body, f"the drop moves it: {post.body}")
    t.check(page.url.endswith("/saker"), "without following the card's link")
    t.check(page.locator("[data-tun-board-ghost]").count() == 0, "the copy is gone")

    narrow = t.desktop(760, 800)
    narrow.sign_in("employee:anna")
    narrow.goto("/saker")
    box = narrow.locator(".tun-board-columns").bounding_box()
    drag(narrow, "Sak nummer 2", box["x"] + box["width"] - 10, box["y"] + 200)
    positions = []
    for _ in range(5):
        narrow.wait_for_timeout(100)
        positions.append(narrow.evaluate("document.querySelector('.tun-board-columns').scrollLeft"))
    t.check(positions[0] < positions[-1], f"at the board's edge the columns scroll steadily: {positions}")
    narrow.keyboard.press("Escape")
    narrow.mouse.up()
    t.check(column_of(narrow, "Sak nummer 2") == "ny", "Escape puts the card back")
