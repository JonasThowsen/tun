"""An accordion's content rises and fades as it opens and nothing around it
slides; a generated record's action that asks first asks in the confirm
dialog and its yes posts the server's token; a Markdown table of ten
columns scrolls in its own box on a phone, reached by the keyboard
(spec/ui.md 2.1, 6, 6.2, 8)."""

# Marks the accordion item titled TITLE's summary, content and the next
# item's summary, closing the item first when it is open.
MARK = """(title) => {
  const item = [...document.querySelectorAll('.tun-specimen-preview .tun-accordion-item')]
    .find((each) => each.querySelector('.tun-accordion-title').textContent.includes(title));
  if (item.open) item.querySelector('summary').click();
  item.querySelector('summary').dataset.check = 'summary';
  item.querySelector('.tun-accordion-content').dataset.check = 'content';
  item.nextElementSibling.querySelector('summary').dataset.check = 'next';
  return !item.open;
}"""

# The marked parts at this moment: the content's opacity and the boxes.
MOMENT = """() => {
  const part = (name) => document.querySelector(`[data-check=${name}]`);
  const box = (name) => part(name).getBoundingClientRect();
  return {opacity: parseFloat(getComputedStyle(part('content')).opacity),
          top: box('summary').top, height: box('summary').height, next: box('next').top,
          open: part('summary').parentElement.open};
}"""

# Closes the marked item and looks at the next frame.
CLOSE = """async () => {
  const summary = document.querySelector('[data-check=summary]');
  summary.click();
  await new Promise((resolve) => requestAnimationFrame(resolve));
  return {open: summary.parentElement.open,
          shown: document.querySelector('[data-check=content]').checkVisibility()};
}"""

CONTENT = "[data-check=content]"
SUMMARY = "[data-check=summary]"
# A click on the summary from the page's script: a pointer's click would
# scroll it into view first, and the check measures that nothing moves.
CLICK = "() => document.querySelector('[data-check=summary]').click()"

CONFIRM = """() => {
  const dialog = document.querySelector('[data-tun-confirm-dialog] > dialog');
  const ok = dialog.querySelector('[data-tun-confirm-ok]');
  const sentence = dialog.querySelector('.tun-dialog-description');
  const active = document.activeElement;
  return {open: dialog.open, question: dialog.querySelector('.tun-dialog-title').textContent,
          detail: sentence.hidden ? null : sentence.textContent, ok: ok.textContent.trim(),
          variant: ok.dataset.variant, color: getComputedStyle(ok).color,
          focus: active ? (active.getAttribute('aria-label') || active.textContent.trim()) : null,
          steps: document.querySelectorAll('[data-tun-confirm-step]').length};
}"""

ACTIVE = """() => {
  const element = document.activeElement;
  return element ? (element.getAttribute('aria-label') || element.textContent.trim()) : null;
}"""

TABLE = """() => {
  const root = document.querySelector('#comment');
  const [narrow, wide] = root.querySelectorAll('.tun-markdown-table');
  const box = (element) => element.getBoundingClientRect();
  const value = (text) => [...wide.querySelectorAll('td')]
    .find((td) => td.textContent.includes(text)).querySelector('.tun-markdown-table-value');
  const lines = (text) => Math.round(box(value(text)).height / parseFloat(getComputedStyle(value(text)).lineHeight));
  const rem = parseFloat(getComputedStyle(document.documentElement).fontSize);
  return {
    pageScrolls: document.documentElement.scrollWidth > innerWidth,
    row: getComputedStyle(wide.querySelector('tbody tr')).display,
    headings: getComputedStyle(wide.querySelector('thead tr')).display,
    inside: box(wide).left >= box(root).left - 0.5 && box(wide).right <= box(root).right + 0.5,
    scrolls: wide.scrollWidth > wide.clientWidth,
    narrowFits: narrow.scrollWidth <= narrow.clientWidth,
    oneLine: [lines('Fjord Coffee Ltd'), lines('In progress'), lines('€128,950.00')],
    note: {lines: lines('The site is closed'), width: box(value('The site is closed')).width,
           cap: Math.min(16 * rem, 0.75 * box(root).width)},
  };
}"""

LAST_COLUMN = """() => {
  const wide = document.querySelectorAll('#comment .tun-markdown-table')[1];
  wide.scrollLeft = wide.scrollWidth;
  const last = wide.querySelector('thead th:last-child').getBoundingClientRect();
  const box = wide.getBoundingClientRect();
  return {left: last.left, right: last.right, boxLeft: box.left, boxRight: box.right};
}"""

# A button put right before the wide table's box, focused, so the next Tab
# shows where the keyboard goes from there.
BEFORE_BOX = """() => {
  const wide = document.querySelectorAll('#comment .tun-markdown-table')[1];
  const before = document.createElement('button');
  before.id = 'before-the-box';
  before.textContent = 'before';
  wide.before(before);
  before.focus();
  return document.activeElement === before;
}"""

IN_BOX = """() => {
  const wide = document.querySelectorAll('#comment .tun-markdown-table')[1];
  return {focused: document.activeElement === wide, left: wide.scrollLeft};
}"""


def rgb(text):
    return tuple(int(float(part)) for part in text[text.index("(") + 1:text.index(")")].split(",")[:3])


def opening(page):
    """Open the marked item with its motion held: its animations, and the
    moments 0, 50, 100 and 150 ms into it and its end."""
    page.hold_motion()
    closed = page.evaluate(MOMENT)
    page.evaluate(CLICK)
    animations = page.animations(CONTENT)
    moments = []
    for ms in (0, 50, 100, 150):
        page.seek_motion(CONTENT, ms)
        moments.append({"at": ms, **page.evaluate(MOMENT)})
    page.seek_motion(CONTENT, None)
    end = page.evaluate(MOMENT)
    page.release_motion()
    return closed, animations, moments, end


def accordion(t):
    for width, make in ((390, t.phone), (1280, t.desktop)):
        page = make()
        page.goto("/ui/accordion")
        t.check(page.evaluate(MARK, "Contact details"), f"{width}px: the item starts closed")
        closed, animations, moments, end = opening(page)
        motion = [(a["kind"], a["name"], a["duration_ms"]) for a in animations]
        t.check(motion == [("animation", "tun-accordion-open", 200)],
                f"{width}px: opening runs tun-accordion-open over --duration, 200 ms: {motion}")
        frames = animations[0]["keyframes"] if animations else []
        t.check(frames and float(frames[0].get("opacity", 1)) < 1 and "translate" in str(frames[0]),
                f"{width}px: from below and faded: {frames}")
        opacities = [m["opacity"] for m in moments] + [end["opacity"]]
        t.check(opacities[0] < 1 and opacities[-1] == 1 and opacities == sorted(opacities),
                f"{width}px: the content fades in over it, held at 0, 50, 100, 150 ms and its end: "
                f"{[round(o, 2) for o in opacities]}")
        t.check(all(abs(m["top"] - closed["top"]) <= 0.5 and abs(m["height"] - closed["height"]) <= 0.5
                    for m in moments + [end]),
                f"{width}px: the summary row stays where it was: {closed}")
        t.check(all(abs(m["next"] - end["next"]) <= 0.5 for m in moments),
                f"{width}px: the next item stands where it ends from the first moment: "
                f"{sorted({round(m['next'], 1) for m in moments + [end]})}")
        shut = page.evaluate(CLOSE)
        t.check(not shut["open"] and not shut["shown"],
                f"{width}px: closing hides the content in the next frame")
        if width == 390:
            page.hold_motion()
            page.locator(SUMMARY).scroll_into_view_if_needed()
            page.evaluate(CLICK)
            page.seek_motion(CONTENT, 60)
            page.screenshot(path=str(t.out / "ui-motion-accordion-opening-390.png"))
            page.release_motion()

    page = t.phone()
    page._page.emulate_media(reduced_motion="reduce")
    page.goto("/ui/accordion")
    page.evaluate(MARK, "Contact details")
    closed, animations, moments, end = opening(page)
    t.check(animations == [] and moments[0]["opacity"] == 1 and end["open"],
            f"under reduced motion nothing moves and the content shows: {animations}, "
            f"{moments[0]['opacity']}")

    page = t.phone(javascript=False)
    page.goto("/ui/accordion")
    item = page.locator(".tun-specimen-preview .tun-accordion-item",
                        has_text="The fitter's notes").first
    item.locator("summary").click()
    opened = item.get_attribute("open") is not None
    item.locator("summary").click()
    t.check(opened and item.get_attribute("open") is None,
            "without JavaScript an item opens and closes on a click")


def meeting_paths(page):
    page.goto("/meetings")
    links = page.locator("table a[href^='/meetings/mtg_']")
    return [links.nth(i).get_attribute("href") for i in range(links.count())]


def posts_to(page, path):
    seen = []
    page.on("request", lambda request: seen.append(request.post_data or "")
            if request.method == "POST" and request.url.endswith(path) else None)
    return seen


def confirm(t):
    page = t.desktop(javascript=False)
    page.sign_in("employee:anna")
    first, second = meeting_paths(page)[:2]

    # Without JavaScript the server's page asks, as before.
    page.goto(first)
    page.get_by_role("button", name="Cancel the meeting").click()
    page.wait_for_load_state()
    t.check(page.url.endswith(f"{first}/meetings_cancel")
            and page.locator(".tun-confirm-panel input[name=confirmation_token]").count() == 1
            and "Cancel the meeting?" in page.content(),
            f"without JavaScript the confirmation page asks, with its token form: {page.url}")

    # 1280px: buttons in the header.
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto(first)
    sent = posts_to(page, f"{first}/meetings_cancel")
    held = page.get_by_role("button", name="Mark as held")
    held.click()
    page.wait_for_function("() => document.querySelector('[data-tun-confirm-dialog] > dialog').open")
    shown = page.evaluate(CONFIRM)
    t.check(shown["question"] == "Mark as held?" and shown["variant"] == "primary"
            and shown["focus"] == "Mark as held" and page.url.endswith(first),
            f"1280px: «Mark as held» asks with the primary action, the focus on it: {shown}")
    page.keyboard.press("Escape")
    page.wait_for_timeout(300)

    cancel = page.get_by_role("button", name="Cancel the meeting")
    cancel.click()
    page.wait_for_function("() => document.querySelector('[data-tun-confirm-dialog] > dialog').open")
    shown = page.evaluate(CONFIRM)
    t.check(shown["question"] == "Cancel the meeting?"
            and shown["detail"] == "Cancel «Bread van signage». It stays in the list as cancelled."
            and shown["ok"] == "Cancel the meeting" and shown["variant"] == "destructive",
            f"1280px: the dialog asks the operation's question with its summary: {shown}")
    red = rgb(shown["color"])
    t.check(red[0] > red[1] + 80 and shown["focus"] == "Cancel" and page.url.endswith(first),
            f"1280px: a warning's action is red, the focus on «Cancel», the address kept: {shown}")
    page.screenshot(path=str(t.out / "ui-motion-confirm-1280.png"))
    page.locator("[data-tun-confirm-cancel]").first.click()
    page.wait_for_timeout(300)
    shown = page.evaluate(CONFIRM)
    t.check(not shown["open"] and len(sent) == 1 and shown["steps"] == 0
            and shown["focus"] == "Cancel the meeting" and page.url.endswith(first),
            f"1280px: «Cancel» posts nothing more, leaves no step, gives the focus back: "
            f"{shown['focus']}, {len(sent)} posts, {shown['steps']} steps")
    cancel.click()
    page.wait_for_function("() => document.querySelector('[data-tun-confirm-dialog] > dialog').open")
    page.keyboard.press("Escape")
    page.wait_for_timeout(300)
    shown = page.evaluate(CONFIRM)
    t.check(not shown["open"] and len(sent) == 2 and shown["steps"] == 0
            and shown["focus"] == "Cancel the meeting",
            f"1280px: Escape posts nothing more and gives the focus back: {shown['focus']}, {len(sent)}")
    cancel.click()
    page.wait_for_function("() => document.querySelector('[data-tun-confirm-dialog] > dialog').open")
    page.locator("[data-tun-confirm-ok]").first.click()
    page.wait_for_function("() => document.querySelector('.tun-page-header')?.textContent.includes('Cancelled')")
    page.wait_for_timeout(300)
    t.check(len(sent) == 4 and "confirmation_token=" in sent[3]
            and all("confirmation_token" not in each for each in sent[:3]),
            f"1280px: the yes posts once, with the token: {len(sent)} posts")
    t.check(page.url.endswith(first) and page.locator(".tun-page-header .tun-badge").inner_text() == "Cancelled",
            f"1280px: the record shows the meeting cancelled at its address: {page.url}")

    # 390px: the actions fold into «More actions».
    page = t.phone()
    page.sign_in("employee:anna")
    page.goto(second)
    sent = posts_to(page, f"{second}/meetings_cancel")
    more = page.get_by_role("button", name="More actions")

    def ask():
        more.click()
        page.get_by_role("menuitem", name="Cancel the meeting").click()
        page.wait_for_function("() => document.querySelector('[data-tun-confirm-dialog] > dialog').open")
        return page.evaluate(CONFIRM)

    shown = ask()
    t.check(shown["question"] == "Cancel the meeting?" and shown["variant"] == "destructive"
            and shown["focus"] == "Cancel" and page.url.endswith(second),
            f"390px: the item asks in the dialog, the focus on «Cancel»: {shown}")
    page.screenshot(path=str(t.out / "ui-motion-confirm-390.png"))
    page.locator("[data-tun-confirm-cancel]").first.click()
    page.wait_for_timeout(300)
    shown = page.evaluate(CONFIRM)
    t.check(not shown["open"] and shown["focus"] == "More actions" and shown["steps"] == 0,
            f"390px: «Cancel» gives the focus to «More actions»: {shown['focus']}")
    ask()
    page.keyboard.press("Escape")
    page.wait_for_timeout(300)
    shown = page.evaluate(CONFIRM)
    t.check(not shown["open"] and shown["focus"] == "More actions" and len(sent) == 2,
            f"390px: Escape too, nothing more posted: {shown['focus']}, {len(sent)}")
    ask()
    page.locator("[data-tun-confirm-ok]").first.click()
    page.wait_for_function("() => document.querySelector('.tun-page-header')?.textContent.includes('Cancelled')")
    t.check(len(sent) == 4 and "confirmation_token=" in sent[3] and page.url.endswith(second),
            f"390px: the yes posts the token once and the record shows it: {len(sent)}, {page.url}")


def markdown(t):
    for width in (320, 360, 390):
        page = t.phone(width=width)
        page.sign_in("employee:anna")
        page.goto("/markdown")
        m = page.evaluate(TABLE)
        name = f"{width}px"
        t.check(not m["pageScrolls"], f"{name}: the page does not scroll sideways")
        t.check(m["row"] == "table-row" and m["headings"] == "table-row",
                f"{name}: ten columns stay a table: {m['row']}, {m['headings']}")
        t.check(m["inside"] and m["scrolls"], f"{name}: in its own box inside the comment, which scrolls")
        t.check(m["narrowFits"], f"{name}: the table of three columns fits")
        t.check(m["oneLine"] == [1, 1, 1], f"{name}: a short value stands on one line: {m['oneLine']}")
        t.check(m["note"]["lines"] > 1 and m["note"]["width"] <= m["note"]["cap"] + 0.5,
                f"{name}: a long note wraps within 16rem and three quarters of the comment: {m['note']}")
        page.locator("#comment .tun-markdown-table").nth(1).screenshot(
            path=str(t.out / f"ui-motion-markdown-table-{width}.png"))
        page.screenshot(path=str(t.out / f"ui-motion-markdown-{width}.png"), full_page=True)
        end = page.evaluate(LAST_COLUMN)
        t.check(end["right"] <= end["boxRight"] + 0.5 and end["right"] >= end["boxRight"] - 1
                and end["left"] < end["boxRight"],
                f"{name}: scrolled to its end, the last column's end is in the box: {end}")
        page.evaluate("() => { document.querySelectorAll('#comment .tun-markdown-table')[1].scrollLeft = 0; }")
        t.check(page.evaluate(BEFORE_BOX), f"{name}: a control before the box has the focus")
        page.keyboard.press("Tab")
        page.keyboard.press("ArrowRight")
        page.wait_for_timeout(300)
        reached = page.evaluate(IN_BOX)
        t.check(reached["focused"] and reached["left"] > 0,
                f"{name}: Tab reaches the box and the arrow keys scroll it: {reached}")


def run(t):
    accordion(t)
    confirm(t)
    markdown(t)
