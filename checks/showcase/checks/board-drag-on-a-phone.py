"""On a phone, a card held at the screen's edge pages the board a column at
a time, a drop there moves it, and the board stays where it was scrolled
(spec/ui.md 6.1)."""

COLUMNS = "document.querySelector('.tun-board-columns')"

# Each place the columns scroll to while a card is held, in turn.
RECORD_PAGES = f"""() => {{
  const box = {COLUMNS};
  window.tunPages = [Math.round(box.scrollLeft)];
  box.addEventListener('scroll', () => {{
    const left = Math.round(box.scrollLeft);
    if (window.tunPages.at(-1) !== left) window.tunPages.push(left);
  }});
}}"""


# Whether the board shows «Item 1» in «Planned», not the copy a drag leaves.
IN_PLANNED = """() => [...document.querySelectorAll(
    '[data-tun-board-column=planned] [data-tun-board-card]:not([data-tun-board-ghost])')]
  .some((card) => card.querySelector('.tun-board-card-title')?.textContent.trim() === 'Item 1')"""


def start_of(page, key):
    return page.evaluate(f"""(() => {{ const box = {COLUMNS};
      return Math.round(box.scrollLeft + document.querySelector('[data-tun-board-column="{key}"]')
        .getBoundingClientRect().left - box.getBoundingClientRect().left); }})()""")


def column_of(page, title):
    return page.card(title).evaluate("card => card.closest('[data-tun-board-column]').dataset.tunBoardColumn")


def scrolled(page):
    return round(page.evaluate(f"{COLUMNS}.scrollLeft"))


def wait_scrolled(page, left, what):
    """Wait until the columns stand at LEFT, while the finger stays held."""
    page.wait_until(f"(left) => Math.round({COLUMNS}.scrollLeft) === left", left, what=what)


def run(t):
    page = t.phone()
    page.sign_in("employee:anna")
    page.goto("/items")
    planned, in_progress = start_of(page, "planned"), start_of(page, "in_progress")
    t.check(scrolled(page) == 0, "the board starts on «New»")

    finger = page.touch.hold_to_drag(page.card("Item 1")).move_to(389, 400, steps=4)
    finger.stay(0.15)
    t.check(scrolled(page) == 0, "a moment at the edge does not page yet")
    wait_scrolled(page, planned, "the board to page to «Planned» under the held card")
    t.check(scrolled(page) == planned, f"held at the very edge, it pages to «Planned» ({scrolled(page)})")
    t.check(page.evaluate(f"getComputedStyle({COLUMNS}).scrollSnapType") == "none",
            "the columns do not snap while a card is dragged")
    # Off the edge at once, before the board pages on a second later.
    finger.move_to(200, 400, steps=2)
    t.check(column_of(page, "Item 1") == "planned", "the card is in «Planned» under the finger")
    with page.expect_htmx(), page.expect_post("/items/move") as post:
        finger.lift()
    t.check(post.status == 200 and "column=planned" in post.body,
            f"the drop moves it: {post.status} {post.body}")
    page.wait_until(IN_PLANNED, what="the answer to show «Item 1» in «Planned»")
    t.check(column_of(page, "Item 1") == "planned", "the answer has it in «Planned»")
    t.check(scrolled(page) == planned, "and keeps «Planned» in view")
    t.check(page.evaluate(f"getComputedStyle({COLUMNS}).scrollSnapType") != "none",
            "the columns snap again")

    finger = page.touch.hold_to_drag(page.card("Item 1")).move_to(1, 300, steps=4)
    wait_scrolled(page, 0, "the board to page back to «New» under the held card")
    t.check(scrolled(page) == 0, "held at the left edge, it pages back to «New»")
    finger.move_to(200, 300, steps=2)
    with page.expect_htmx(), page.expect_post("/items/move") as post:
        finger.lift()
    t.check("column=new" in post.body, f"and a drop there moves it back: {post.body}")

    page.evaluate(f"{COLUMNS}.scrollTo({{left: 0}}); document.activeElement.blur()")
    page.evaluate("document.querySelector('[data-tun-board-column=new] .tun-board-cards').scrollTop = 0")
    page.evaluate(RECORD_PAGES)
    finger = page.touch.hold_to_drag(page.card("Item 2")).move_to(389, 400, steps=4)
    wait_scrolled(page, in_progress, "the board to page on to «In progress» under the held card")
    seen = page.evaluate("() => window.tunPages")
    t.check(planned in seen and in_progress in seen and seen.index(planned) < seen.index(in_progress),
            f"held on, it pages again, a column at a time: {seen}")
    finger.move_to(200, 400, steps=2)
    with page.expect_htmx(), page.expect_post("/items/move"):
        finger.lift()

    page.evaluate(f"{COLUMNS}.scrollTo({{left: 0}}); document.activeElement.blur()")
    cards = "document.querySelector('[data-tun-board-column=new] .tun-board-cards')"
    page.evaluate(f"{cards}.scrollTop = 0")
    page.wait_until(f"() => {COLUMNS}.scrollLeft === 0 && {cards}.scrollTop === 0",
                    what="the board back at its start")
    box = page.locator("[data-tun-board-column=new] .tun-board-cards").bounding_box()
    finger = page.touch.hold_to_drag(page.card("Item 3")).move_to(195, box["y"] + box["height"] - 10)
    page.wait_until(f"() => {cards}.scrollTop > 200",
                    what="the held card's column to scroll past 200 px")
    t.check(page.evaluate(f"{cards}.scrollTop") > 200, "held near a column's bottom, its cards scroll")
    t.check(scrolled(page) == 0 and page.evaluate("scrollY") == 0, "and neither the board nor the page")
    finger.move_to(195, box["y"] + 100).lift()
