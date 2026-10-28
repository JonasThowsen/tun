"""A button's shortcut shows as key caps on a wide screen, an icon button
growing to hold them, and not on a phone, where it stays a square; Ctrl
reads ⌘ on a Mac (spec/ui.md 6)."""

MEASURE = """() => {
  const search = document.querySelector('.tun-page-header-actions [aria-label=Search]');
  const filter = document.querySelector('.tun-page-header-actions [aria-label=Filter]');
  const caps = search.querySelector('[data-tun-shortcut]');
  const box = search.getBoundingClientRect();
  const keys = caps.getBoundingClientRect();
  const header = document.querySelector('.tun-page-header');
  const title = header.querySelector('.tun-page-header-title').getBoundingClientRect();
  const actions = header.querySelector('.tun-page-header-actions').getBoundingClientRect();
  return {width: box.width, height: box.height, filterHeight: filter.getBoundingClientRect().height,
          capsShown: keys.width > 0 && getComputedStyle(caps).display !== 'none',
          capsInside: keys.left >= box.left && keys.right <= box.right
            && keys.top >= box.top && keys.bottom <= box.bottom,
          keys: [...caps.querySelectorAll('kbd')].map((key) => key.textContent),
          shortcut: search.getAttribute('aria-keyshortcuts'),
          oneRow: Math.abs(title.top - actions.top) < 20 && actions.left > title.right};
}"""

# A Mac, as far as the components' script can tell.
MAC = "Object.defineProperty(Navigator.prototype, 'platform', {get: () => 'MacIntel'});"

# A copy of the header's buttons, swapped in by htmx after the page loaded.
SWAP = """async () => {
  const holder = document.createElement('div');
  holder.id = 'swapped';
  document.body.append(holder);
  await htmx.ajax('GET', '/items', {target: '#swapped', swap: 'innerHTML',
                                    select: '.tun-page-header-actions'});
  await new Promise((done) => setTimeout(done, 300));
  return holder.querySelector('kbd[data-tun-key=ctrl]')?.textContent;
}"""


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/items")
    m = page.evaluate(MEASURE)
    t.check(m["capsShown"] and m["keys"] == ["Ctrl", "K"], f"a desktop shows Ctrl K in «Search»: {m['keys']}")
    t.check(m["capsInside"], "the caps sit inside the button, on its one line")
    t.check(m["width"] > m["height"] + 20, f"the icon button grows to hold them ({m['width']:.0f}px)")
    t.check(abs(m["height"] - m["filterHeight"]) < 1,
            f"at the height of the buttons beside it ({m['height']:.0f}px)")
    t.check(m["shortcut"] == "Control+K Meta+K", f"aria-keyshortcuts says it: {m['shortcut']}")
    t.check(m["oneRow"], "the header stays one row")
    page.keyboard.press("Control+k")
    t.check(page.locator("dialog#search[open]").count() == 1, "Ctrl+K opens the search it names")

    page = t.desktop(768, 800)
    page.sign_in("employee:anna")
    page.goto("/items")
    t.check(page.evaluate(MEASURE)["capsShown"], "48rem wide shows the caps")

    for width, height in ((390, 844), (767, 1024)):
        page = t.phone(width, height)
        page.sign_in("employee:anna")
        page.goto("/items")
        m = page.evaluate(MEASURE)
        t.check(not m["capsShown"], f"{width}px wide hides the caps")
        t.check(abs(m["width"] - m["height"]) < 1, f"«Search» is a square there ({m['width']:.0f}px)")
        t.check(m["oneRow"], f"{width}px: the header stays one row")

    page = t.desktop()
    page.add_init_script(MAC)
    page.sign_in("employee:anna")
    page.goto("/items")
    t.check(page.evaluate(MEASURE)["keys"] == ["⌘", "K"], "a Mac reads ⌘ K")
    t.check(page.evaluate(SWAP) == "⌘", "also in what htmx swaps in")
    page.keyboard.press("Meta+k")
    t.check(page.locator("dialog#search[open]").count() == 1, "and ⌘K opens the search")
