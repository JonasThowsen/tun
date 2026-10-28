"""On a phone, a card held at the screen's edge pages the board a column at
a time, a drop there moves it, and the board stays where it was scrolled
(spec/ui.md 6.1)."""

COLUMNS = "document.querySelector('.tun-board-columns')"


def start_of(page, key):
    return page.evaluate(f"""(() => {{ const box = {COLUMNS};
      return Math.round(box.scrollLeft + document.querySelector('[data-tun-board-column="{key}"]')
        .getBoundingClientRect().left - box.getBoundingClientRect().left); }})()""")


def column_of(page, title):
    return page.card(title).evaluate("card => card.closest('[data-tun-board-column]').dataset.tunBoardColumn")


def scrolled(page):
    return round(page.evaluate(f"{COLUMNS}.scrollLeft"))


def run(t):
    page = t.phone()
    page.sign_in("employee:anna")
    page.goto("/items")
    planned, in_progress = start_of(page, "planned"), start_of(page, "in_progress")
    t.check(scrolled(page) == 0, "the board starts on «New»")

    finger = page.touch.hold(page.card("Item 1")).move_to(389, 400, steps=4)
    finger.stay(0.15)
    t.check(scrolled(page) == 0, "a moment at the edge does not page yet")
    finger.stay(0.7)
    t.check(scrolled(page) == planned, f"held at the very edge, it pages to «Planned» ({scrolled(page)})")
    t.check(page.evaluate(f"getComputedStyle({COLUMNS}).scrollSnapType") == "none",
            "the columns do not snap while a card is dragged")
    finger.move_to(200, 400)
    t.check(column_of(page, "Item 1") == "planned", "the card is in «Planned» under the finger")
    with page.expect_post("/items/move") as post:
        finger.lift()
    page.wait_for_timeout(500)
    t.check(post.status == 200 and "column=planned" in post.body, f"the drop moves it: {post.body}")
    t.check(column_of(page, "Item 1") == "planned", "the answer has it in «Planned»")
    t.check(scrolled(page) == planned, "and keeps «Planned» in view")
    t.check(page.evaluate(f"getComputedStyle({COLUMNS}).scrollSnapType") != "none",
            "the columns snap again")

    finger = page.touch.hold(page.card("Item 1")).move_to(1, 300, steps=4)
    finger.stay(0.9)
    t.check(scrolled(page) == 0, "held at the left edge, it pages back to «New»")
    finger.move_to(200, 300)
    with page.expect_post("/items/move") as post:
        finger.lift()
    page.wait_for_timeout(500)
    t.check("column=new" in post.body, f"and a drop there moves it back: {post.body}")

    page.evaluate(f"{COLUMNS}.scrollTo({{left: 0}}); document.activeElement.blur()")
    page.evaluate("document.querySelector('[data-tun-board-column=new] .tun-board-cards').scrollTop = 0")
    finger = page.touch.hold(page.card("Item 2")).move_to(389, 400, steps=4)
    seen = set()
    for _ in range(22):
        finger.stay(0.1)
        seen.add(scrolled(page))
    t.check(planned in seen and in_progress in seen,
            f"held on, it pages again, a column at a time: {sorted(seen)}")
    finger.move_to(200, 400)
    with page.expect_post("/items/move"):
        finger.lift()
    page.wait_for_timeout(500)

    page.evaluate(f"{COLUMNS}.scrollTo({{left: 0}}); document.activeElement.blur()")
    cards = "document.querySelector('[data-tun-board-column=new] .tun-board-cards')"
    page.evaluate(f"{cards}.scrollTop = 0")
    page.wait_for_timeout(200)
    box = page.locator("[data-tun-board-column=new] .tun-board-cards").bounding_box()
    finger = page.touch.hold(page.card("Item 3")).move_to(195, box["y"] + box["height"] - 10)
    finger.stay(1.0)
    t.check(page.evaluate(f"{cards}.scrollTop") > 200, "held near a column's bottom, its cards scroll")
    t.check(scrolled(page) == 0 and page.evaluate("scrollY") == 0, "and neither the board nor the page")
    finger.move_to(195, box["y"] + 100).lift()
