"""Five small things the first client found: a summary list's long label
never runs into its value, a search result shows why it was found, a
section's live facts under its heading, a muted line in the page's flow,
and the specimen's toast leaving its theme switch free on a wide screen
(spec/ui.md 6, 6.4, 7)."""

import re

SCENARIO = "search"

WIDE_PAGE = "() => document.scrollingElement.scrollWidth > innerWidth + 1"

# Every summary list row in ROOT: the right edge of its label's text, from
# the text's own line boxes (a word too long for its box paints beyond
# it), the left edge of its value's box, how many lines the label has, its
# column's width and the width of its words unbroken in the page's font.
LABELS = """(root) => [...document.querySelectorAll(`${root} .tun-summary-list-row`)].map((row) => {
  const key = row.querySelector('.tun-summary-list-key');
  const value = row.querySelector('.tun-summary-list-value');
  const range = document.createRange();
  range.selectNodeContents(key);
  const rects = [...range.getClientRects()].filter((r) => r.width > 0);
  const tops = new Set(rects.map((r) => Math.round(r.top)));
  const probe = document.createElement('span');
  probe.textContent = key.textContent;
  probe.style.whiteSpace = 'nowrap';
  key.append(probe);
  const natural = probe.getBoundingClientRect().width;
  probe.remove();
  return {label: key.textContent, right: Math.max(...rects.map((r) => r.right)),
          column: key.getBoundingClientRect().width, natural,
          valueLeft: value.getBoundingClientRect().left, lines: tops.size,
          keyHeight: key.getBoundingClientRect().height,
          lineHeight: parseFloat(getComputedStyle(key).lineHeight)};
})"""

META = """(root) => {
  const section = document.querySelector(root);
  const title = section.querySelector('.tun-section-title').getBoundingClientRect();
  const meta = section.querySelector('.tun-section-meta');
  const style = getComputedStyle(meta);
  const actions = section.querySelector('.tun-section-actions');
  return {below: meta.getBoundingClientRect().top >= title.bottom - 1,
          left: Math.abs(meta.getBoundingClientRect().left - title.left) <= 1,
          colour: style.color, size: style.fontSize,
          inActions: actions ? actions.contains(meta) : false,
          text: meta.textContent};
}"""

MUTED = """() => {
  const probe = document.createElement('span');
  probe.style.color = 'var(--muted-foreground)';
  document.body.append(probe);
  const colour = getComputedStyle(probe).color;
  probe.remove();
  return colour;
}"""


def labels_never_reach_their_values(t, page, root, where):
    rows = page.evaluate(LABELS, root)
    t.check(rows, f"{where}: there are facts")
    for row in rows:
        t.check(row["right"] <= row["valueLeft"] + 0.5,
                f"{where}: «{row['label']}» stays out of its value "
                f"({row['right']:.1f} <= {row['valueLeft']:.1f})")
    return {row["label"]: row for row in rows}


def summary_lists(t):
    for width in (390, 360, 320):
        page = t.phone(width=width)
        page.goto("/ui/summary-list")
        rows = labels_never_reach_their_values(t, page, ".tun-specimen-preview",
                                               f"{width}px, the specimen")
        # The check's browser has its own fonts, not a phone's: a word that
        # fits its column in them stays whole, one that does not breaks.
        for label in ("Organisasjonsnummer", "Leveringsbetingelsesdokumentasjon"):
            row = rows[label]
            fits = row["natural"] <= row["column"] + 0.5
            t.check(row["lines"] == 1 if fits else row["lines"] >= 2,
                    f"{width}px: «{label}» {'whole' if fits else 'broken'} "
                    f"({row['natural']:.0f}px in a {row['column']:.0f}px column, {row['lines']} lines)")
        t.check(not page.evaluate(WIDE_PAGE), f"{width}px: the specimen does not scroll sideways")


def set_norwegian(page):
    page.goto("/settings")
    page.locator("#setting-locale-language").select_option(label="Norsk (bokmål)")
    form = page.locator("form").filter(has=page.locator("#setting-locale-language"))
    form.get_by_role("button", name="Save", exact=True).click()
    page.wait_for_url(re.compile(r"/settings\?saved=locale\.language$"))
    page.wait_for_load_state()


def card_page(t):
    admin = t.phone()
    admin.sign_in("admin:jonas")
    set_norwegian(admin)
    admin.goto("/items")
    href = admin.locator(".tun-board-card a[href^='/items/']").first.get_attribute("href")
    for width in (390, 360, 320):
        page = t.phone(width=width)
        page.sign_in("employee:anna")
        page.goto(href)
        t.check(page.evaluate("document.documentElement.lang") == "nb", "the page is Norwegian")
        rows = labels_never_reach_their_values(t, page, "#details", f"{width}px, a card's page")
        row = rows["Registreringsnummer"]
        if width == 390:
            t.check(abs(row["column"] - 160) <= 0.5, f"390px: the label's column is 10rem: {row}")
        fits = row["natural"] <= row["column"] + 0.5
        t.check(row["lines"] == 1 if fits else row["lines"] >= 2,
                f"{width}px: «Registreringsnummer» {'whole' if fits else 'broken'}: {row}")
        m = page.evaluate(META, "#details")
        t.check(m["below"] and m["left"] and not m["inActions"],
                f"{width}px: the section's facts under its heading: {m}")
        t.check(m["colour"] == page.evaluate(MUTED), f"{width}px: in the muted colour: {m}")
        t.check("filer" in m["text"], f"{width}px: its count of files: {m['text']}")
        note = page.locator("#details .tun-note")
        t.check(note.count() == 1, f"{width}px: the note under the facts")
        t.check(page.evaluate("() => getComputedStyle(document.querySelector('#details .tun-note')).color")
                == page.evaluate(MUTED), f"{width}px: the note is muted")
        t.check(not page.evaluate(WIDE_PAGE), f"{width}px: the card's page does not scroll sideways")


def specimen_meta_and_note(t):
    for scheme in ("light", "dark"):
        page = t.phone(scheme=scheme)
        page.goto("/ui/section")
        m = page.evaluate(META, ".tun-specimen-preview .tun-section:has(.tun-section-meta)")
        t.check(m["below"] and m["left"] and not m["inActions"],
                f"{scheme}: the specimen's section has its facts under its heading: {m}")
        page.goto("/ui/note")
        notes = page.evaluate("""() => [...document.querySelectorAll('.tun-specimen-preview .tun-note')]
          .map((note) => getComputedStyle(note).color)""")
        muted = page.evaluate(MUTED)
        t.check(len(notes) == 2 and all(colour == muted for colour in notes),
                f"{scheme}: each note in the muted colour {muted}: {notes}")


def search_marks_the_line(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards")
    page.keyboard.press("Control+k")
    page.wait_for_timeout(300)
    page.keyboard.type("ex")
    page.wait_for_function(
        """() => document.querySelector('dialog#tun-search [data-tun-search-query]')
                   ?.getAttribute('data-tun-search-query') === 'ex'""", timeout=3000)
    rows = page.evaluate("""() => [...document.querySelectorAll('dialog#tun-search [role=option]')]
      .map((row) => ({title: row.querySelector('.tun-search-results-title').textContent,
                      titleMarks: row.querySelectorAll('.tun-search-results-title mark').length,
                      marks: [...row.querySelectorAll('.tun-search-results-meta mark')]
                               .map((mark) => mark.textContent)}))""")
    unmarked = [row for row in rows if row["titleMarks"] == 0]
    t.check(len(unmarked) >= 5, f"«ex» finds the customers by their email: {rows}")
    t.check(all(row["marks"] and all(m.lower() == "ex" for m in row["marks"]) for row in unmarked),
            f"each one found by its line has «ex» marked there: {unmarked}")


def theme_switch_beside_the_toast(t):
    page = t.desktop()
    page.goto("/ui/flash")
    page.wait_for_timeout(400)
    boxes = page.evaluate("""() => {
      const box = (element) => {
        const r = element.getBoundingClientRect();
        return {left: r.left, right: r.right, top: r.top, bottom: r.bottom};
      };
      const toast = [...document.querySelectorAll('.tun-flash')]
        .find((flash) => getComputedStyle(flash).position === 'fixed');
      return {toast: toast && box(toast), themes: box(document.querySelector('.tun-specimen-themes'))};
    }""")
    toast, themes = boxes["toast"], boxes["themes"]
    t.check(toast is not None, "1280px: the specimen shows the toast")
    apart = (toast["left"] >= themes["right"] or toast["right"] <= themes["left"]
             or toast["top"] >= themes["bottom"] or toast["bottom"] <= themes["top"])
    t.check(apart, f"1280px: the toast and the theme switch do not overlap: {boxes}")
    page.locator(".tun-specimen-themes [data-tun-theme='dark']").click()
    t.check(page.evaluate("document.documentElement.dataset.theme") == "dark",
            "«Dark» pressed while the toast shows makes the page dark")
    t.check(not page.evaluate(WIDE_PAGE), "1280px: the specimen does not scroll sideways")


def run(t):
    summary_lists(t)
    specimen_meta_and_note(t)
    search_marks_the_line(t)
    theme_switch_beside_the_toast(t)
    # Last: it sets the tenant's language to Norwegian.
    card_page(t)
