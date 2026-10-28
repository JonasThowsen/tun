"""On a phone, a card held and moved up its column goes between the two
cards it is lifted between, one held at the screen's edge is put between two
cards of the next column, a swipe still scrolls, and the card's menu fits
the screen (spec/ui.md 6.1)."""

COLUMNS = "document.querySelector('.tun-board-columns')"


def titles(page, key):
    return page.column(key).locator(".tun-board-cards > [data-tun-board-card] .tun-board-card-title") \
        .all_text_contents()


def card_id(page, title):
    return page.card(title).get_attribute("data-tun-board-card")


def run(t):
    page = t.phone()
    page.sign_in("employee:anna")
    page.goto("/items")
    posts = []
    page.on("request", lambda request: posts.append(request.url) if request.method == "POST" else None)

    target = page.card("Item 1").bounding_box()
    finger = page.touch.hold(page.card("Item 3")).move_to(195, target["y"] + 4, steps=8)
    finger.stay(0.2)
    t.check(titles(page, "new")[:4] == ["Urgent: the customer cannot sign in", "Item 3", "Item 1",
                                       "Item 2"],
            f"held and moved up, the card sits between the two: {titles(page, 'new')[:4]}")
    with page.expect_post("/items/move") as post:
        finger.lift()
    page.wait_for_timeout(500)
    t.check(post.status == 200 and "column=new" in post.body
            and f"before={card_id(page, 'Item 1')}" in post.body,
            f"lifted, it posts its place: {post.body}")
    t.check(titles(page, "new")[1] == "Item 3", f"and the answer has it there: {titles(page, 'new')[:4]}")

    finger = page.touch.hold(page.card("Item 5")).move_to(389, 400, steps=4)
    finger.stay(0.8)
    export = page.card("Export to accounting").bounding_box()
    finger.move_to(200, export["y"] + 4, steps=6)
    finger.stay(0.2)
    with page.expect_post("/items/move") as post:
        finger.lift()
    page.wait_for_timeout(500)
    t.check("column=planned" in post.body and f"before={card_id(page, 'Export to accounting')}" in post.body,
            f"paged to «Planned» and lifted between two cards, it posts that place: {post.body}")
    t.check(titles(page, "planned")[:3] == ["New page for invoices", "Item 5", "Export to accounting"],
            f"and the answer has it there: {titles(page, 'planned')}")

    page.evaluate(f"{COLUMNS}.scrollTo({{left: 0}}); document.activeElement.blur()")
    page.wait_for_timeout(300)
    cards = "document.querySelector('[data-tun-board-column=new] .tun-board-cards')"
    page.evaluate(f"{cards}.scrollTop = 0")
    count = len(posts)
    box = page.locator("[data-tun-board-column=new] .tun-board-cards").bounding_box()
    middle = box["y"] + box["height"] / 2
    page.touch.swipe((195, middle), (195, middle - 150))
    page.wait_for_timeout(500)
    t.check(page.evaluate(f"{cards}.scrollTop") > 50 and len(posts) == count,
            "a swipe without a hold scrolls the column and posts nothing")

    page.evaluate(f"{cards}.scrollTop = 0")
    page.locator(f"#items-{card_id(page, 'Item 2')}-move-trigger").tap()
    menu = page.locator(".tun-dropdown-menu-content:popover-open")
    menu.wait_for()
    box = menu.bounding_box()
    t.check(box["x"] >= 0 and box["x"] + box["width"] <= 390 and box["y"] >= 0
            and box["y"] + box["height"] <= 844,
            f"the card's menu fits the screen: {box}")
    t.check(menu.get_by_text("Position").is_visible() and menu.get_by_text("Move up").is_visible(),
            "with «Position» in it")
