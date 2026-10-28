"""With a mouse, a card on an ordered board goes between the two cards it is
dropped between, in its own column or another, and the post says where; a
drop where it started posts nothing; and a board that is not ordered posts
as before (spec/ui.md 6.1)."""


def titles(page, key):
    return page.column(key).locator(".tun-board-cards > [data-tun-board-card] .tun-board-card-title") \
        .all_text_contents()


def card_id(page, title):
    return page.card(title).get_attribute("data-tun-board-card")


def status(page):
    return page.locator("[data-tun-board-status]").text_content().strip()


def press(page, title):
    box = page.card(title).bounding_box()
    page.mouse.move(box["x"] + 30, box["y"] + 20)
    page.mouse.down()
    page.mouse.move(box["x"] + 60, box["y"] + 20, steps=4)


def drag_before(page, title, target):
    """Drag TITLE to just inside the top of the card TARGET: the gap above it."""
    box = page.card(target).bounding_box()
    press(page, title)
    page.mouse.move(box["x"] + box["width"] / 2, box["y"] + 4, steps=10)


def drop(page, path):
    with page.expect_post(path) as post:
        page.mouse.up()
    page.wait_for_timeout(400)
    return post


def posts_of(page):
    posts = []
    page.on("request", lambda request: posts.append(request.url) if request.method == "POST" else None)
    return posts


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/items")
    posts = posts_of(page)
    t.check(titles(page, "new")[:3] == ["Urgent: the customer cannot sign in", "Item 1", "Item 2"],
            f"the board shows the order the page gives: {titles(page, 'new')[:3]}")

    drag_before(page, "Item 4", "Item 2")
    t.check(titles(page, "new")[1:4] == ["Item 1", "Item 4", "Item 2"],
            f"while it is dragged up, the card sits between the two: {titles(page, 'new')[:5]}")
    post = drop(page, "/items/move")
    t.check("column=new" in post.body and f"before={card_id(page, 'Item 2')}" in post.body,
            f"the drop posts its own column and the card below: {post.body}")
    t.check(titles(page, "new")[1:4] == ["Item 1", "Item 4", "Item 2"],
            f"the answer has it there: {titles(page, 'new')[:5]}")
    t.check(status(page) == "Moved “Item 4” to place 3 of 26 in New.",
            f"and says where it went: «{status(page)}»")

    drag_before(page, "Item 1", "Item 3")
    post = drop(page, "/items/move")
    t.check(f"before={card_id(page, 'Item 3')}" in post.body, f"dragged down, the card below: {post.body}")
    t.check(titles(page, "new")[1:5] == ["Item 4", "Item 2", "Item 1", "Item 3"],
            f"and the answer has it there: {titles(page, 'new')[:6]}")

    page.reload()
    t.check(titles(page, "new")[1:5] == ["Item 4", "Item 2", "Item 1", "Item 3"],
            "the page kept the order")

    drag_before(page, "Item 5", "Export to accounting")
    t.check(titles(page, "planned") == ["New page for invoices", "Item 5", "Export to accounting",
                                         "Notification by email"],
            f"over another column it sits between two cards there: {titles(page, 'planned')}")
    post = drop(page, "/items/move")
    t.check("column=planned" in post.body and f"before={card_id(page, 'Export to accounting')}" in post.body,
            f"the drop posts that column and the card below: {post.body}")
    t.check(titles(page, "planned")[1] == "Item 5", f"the answer has it there: {titles(page, 'planned')}")

    last = page.card("Notification by email").bounding_box()
    press(page, "Item 6")
    page.mouse.move(last["x"] + last["width"] / 2, last["y"] + last["height"] + 12, steps=10)
    post = drop(page, "/items/move")
    t.check("column=planned" in post.body and "before=&" in post.body + "&",
            f"dropped under the last card, before= is empty: {post.body}")
    t.check(titles(page, "planned")[-1] == "Item 6", f"and it is last: {titles(page, 'planned')}")

    count = len(posts)
    box = page.card("Item 7").bounding_box()
    press(page, "Item 7")
    page.mouse.move(box["x"] + 30, box["y"] + 22, steps=4)
    page.mouse.up()
    page.wait_for_timeout(600)
    t.check(len(posts) == count, "a card dropped where it started posts nothing")

    plain = t.desktop()
    plain.sign_in("employee:anna")
    plain.goto("/board")
    posts = posts_of(plain)
    before = titles(plain, "new")
    drag_before(plain, "Item 8", "Item 7")
    plain.mouse.up()
    plain.wait_for_timeout(600)
    t.check(not posts and titles(plain, "new") == before,
            "on a board that is not ordered, a card dropped in its own column goes back, unposted")
    target = plain.column("in_progress").bounding_box()
    press(plain, "Item 8")
    plain.mouse.move(target["x"] + target["width"] / 2, target["y"] + 80, steps=10)
    post = drop(plain, "/board/move")
    t.check("column=in_progress" in post.body and "before" not in post.body,
            f"and one dropped in another column posts card and column alone: {post.body}")
    t.check(status(plain) == "Moved “Item 8” to In progress.", f"which is said: «{status(plain)}»")
