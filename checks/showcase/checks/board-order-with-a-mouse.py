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
    page.goto("/saker")
    posts = posts_of(page)
    t.check(titles(page, "ny")[:3] == ["Haster: kunden får ikke logget inn", "Sak nummer 1", "Sak nummer 2"],
            f"the board shows the order the page gives: {titles(page, 'ny')[:3]}")

    drag_before(page, "Sak nummer 4", "Sak nummer 2")
    t.check(titles(page, "ny")[1:4] == ["Sak nummer 1", "Sak nummer 4", "Sak nummer 2"],
            f"while it is dragged up, the card sits between the two: {titles(page, 'ny')[:5]}")
    post = drop(page, "/saker/flytt")
    t.check("column=ny" in post.body and f"before={card_id(page, 'Sak nummer 2')}" in post.body,
            f"the drop posts its own column and the card below: {post.body}")
    t.check(titles(page, "ny")[1:4] == ["Sak nummer 1", "Sak nummer 4", "Sak nummer 2"],
            f"the answer has it there: {titles(page, 'ny')[:5]}")
    t.check(status(page) == "Flyttet «Sak nummer 4» til plass 3 av 26 i Ny.",
            f"and says where it went: «{status(page)}»")

    drag_before(page, "Sak nummer 1", "Sak nummer 3")
    post = drop(page, "/saker/flytt")
    t.check(f"before={card_id(page, 'Sak nummer 3')}" in post.body, f"dragged down, the card below: {post.body}")
    t.check(titles(page, "ny")[1:5] == ["Sak nummer 4", "Sak nummer 2", "Sak nummer 1", "Sak nummer 3"],
            f"and the answer has it there: {titles(page, 'ny')[:6]}")

    page.reload()
    t.check(titles(page, "ny")[1:5] == ["Sak nummer 4", "Sak nummer 2", "Sak nummer 1", "Sak nummer 3"],
            "the page kept the order")

    drag_before(page, "Sak nummer 5", "Eksport til regnskap")
    t.check(titles(page, "planlagt") == ["Ny side for fakturaer", "Sak nummer 5", "Eksport til regnskap",
                                         "Varsel på e-post"],
            f"over another column it sits between two cards there: {titles(page, 'planlagt')}")
    post = drop(page, "/saker/flytt")
    t.check("column=planlagt" in post.body and f"before={card_id(page, 'Eksport til regnskap')}" in post.body,
            f"the drop posts that column and the card below: {post.body}")
    t.check(titles(page, "planlagt")[1] == "Sak nummer 5", f"the answer has it there: {titles(page, 'planlagt')}")

    last = page.card("Varsel på e-post").bounding_box()
    press(page, "Sak nummer 6")
    page.mouse.move(last["x"] + last["width"] / 2, last["y"] + last["height"] + 12, steps=10)
    post = drop(page, "/saker/flytt")
    t.check("column=planlagt" in post.body and "before=&" in post.body + "&",
            f"dropped under the last card, before= is empty: {post.body}")
    t.check(titles(page, "planlagt")[-1] == "Sak nummer 6", f"and it is last: {titles(page, 'planlagt')}")

    count = len(posts)
    box = page.card("Sak nummer 7").bounding_box()
    press(page, "Sak nummer 7")
    page.mouse.move(box["x"] + 30, box["y"] + 22, steps=4)
    page.mouse.up()
    page.wait_for_timeout(600)
    t.check(len(posts) == count, "a card dropped where it started posts nothing")

    plain = t.desktop()
    plain.sign_in("employee:anna")
    plain.goto("/tavle")
    posts = posts_of(plain)
    before = titles(plain, "ny")
    drag_before(plain, "Sak nummer 8", "Sak nummer 7")
    plain.mouse.up()
    plain.wait_for_timeout(600)
    t.check(not posts and titles(plain, "ny") == before,
            "on a board that is not ordered, a card dropped in its own column goes back, unposted")
    target = plain.column("under_arbeid").bounding_box()
    press(plain, "Sak nummer 8")
    plain.mouse.move(target["x"] + target["width"] / 2, target["y"] + 80, steps=10)
    post = drop(plain, "/tavle/flytt")
    t.check("column=under_arbeid" in post.body and "before" not in post.body,
            f"and one dropped in another column posts card and column alone: {post.body}")
    t.check(status(plain) == "Flyttet «Sak nummer 8» til Under arbeid.", f"which is said: «{status(plain)}»")
