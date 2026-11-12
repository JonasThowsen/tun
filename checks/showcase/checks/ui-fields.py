"""The date, time and money fields in a browser: each form typed and posted
read by the server, in English and Norwegian; the calendar's roles, keys,
days, motion and place at 1280, 390, 360 and 320 px; a list's period
applied once per choice with Back stepping through; and the fields and the
period without JavaScript (spec/ui.md 6, date-input, time-input,
money-input, list-toolbar; spec/i18n.md 6.2)."""

import datetime
import re

WIDE_PAGE = "() => document.scrollingElement.scrollWidth > innerWidth + 1"
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

CALENDAR = """(id) => {
  const c = document.getElementById(id);
  const r = c.getBoundingClientRect();
  const s = getComputedStyle(c);
  let open = false;
  try { open = c.matches(':popover-open'); } catch (e) {}
  const cells = [...c.querySelectorAll('td[data-date]')];
  const weight = (e) => e && getComputedStyle(e).fontWeight;
  const size = (e) => e && getComputedStyle(e).fontSize;
  const plain = cells.find((e) => !e.hasAttribute('aria-current') && !e.hasAttribute('aria-selected'));
  const chosen = c.querySelector('[aria-selected=true]');
  const today = c.querySelector('[aria-current=date]');
  const day = cells[10];
  return {open, top: r.top, bottom: r.bottom, left: r.left, right: r.right, width: r.width,
          rects: c.getClientRects().length, opacity: s.opacity,
          radius: s.borderTopLeftRadius, radiusEnd: s.borderBottomRightRadius,
          property: s.transitionProperty, duration: s.transitionDuration,
          dim: getComputedStyle(c, '::backdrop').backgroundColor,
          role: c.getAttribute('role'), modal: c.getAttribute('aria-modal'),
          name: document.getElementById(c.getAttribute('aria-labelledby'))?.textContent,
          heads: [...c.querySelectorAll('th')].map((e) => e.textContent),
          abbr: c.querySelector('th')?.getAttribute('abbr'),
          cells: cells.length, today: today?.dataset.date, chosen: chosen?.dataset.date,
          weights: [weight(plain), weight(chosen), weight(today)].filter(Boolean),
          sizes: [size(plain), size(chosen), size(today)].filter(Boolean),
          dayHeight: day ? day.getBoundingClientRect().height : 0,
          tabbable: cells.filter((e) => e.tabIndex === 0).map((e) => e.dataset.date),
          focus: document.activeElement?.dataset?.date || document.activeElement?.className || ''};
}"""

FOCUS = "() => document.activeElement && (document.activeElement.dataset.date || document.activeElement.className)"


def iso(day):
    return day.isoformat()


def written_en(day):
    return f"{day.day} {MONTHS[day.month - 1]} {day.year}"


def add_months(day, count):
    month = day.month - 1 + count
    year = day.year + month // 12
    month = month % 12 + 1
    last = (datetime.date(year + (month == 12), month % 12 + 1, 1) - datetime.timedelta(days=1)).day
    return datetime.date(year, month, min(day.day, last))


def today_of(page):
    return datetime.date.fromisoformat(
        page.evaluate("() => document.querySelector('[data-tun-date-calendar]').dataset.today"))


def post_fields(page, date="", ret="", time="", price=""):
    """Fill /fields and send it; values what the server read, by name, and
    the errors shown."""
    page.goto("/fields")
    page.locator("#field-date").fill(date)
    page.locator("#field-return").fill(ret)
    page.locator("#field-time").fill(time)
    page.locator("#field-price").fill(price)
    page.locator("form[action='/fields'] button[type=submit]").click()
    page.wait_for_selector("output[data-read], .tun-field-error", timeout=10000)
    return (page.evaluate("() => Object.fromEntries([...document.querySelectorAll('output[data-read]')].map((e) => [e.dataset.read, e.textContent]))"),
            page.evaluate("() => [...document.querySelectorAll('.tun-field-error')].map((e) => e.textContent)"))


def typing(t, page, language):
    today = today_of(page)
    year = today.year
    if language == "en":
        dates = {"21.10.2026": "2026-10-21", "21/10/26": "2026-10-21", "21-10-2026": "2026-10-21",
                 "21 10 2026": "2026-10-21", "21102026": "2026-10-21", "211026": "2026-10-21",
                 "2026-10-21": "2026-10-21", "21 Oct 2026": "2026-10-21",
                 "Oct 21, 2026": "2026-10-21", "21 october 2026": "2026-10-21",
                 "1.2.": f"{year}-02-01", "0102": f"{year}-02-01", "1 Feb": f"{year}-02-01"}
        times = {"9": "09:00", "930": "09:30", "9.30": "09:30", "09:30": "09:30", "1330": "13:30"}
        prices = {"1,250.50": "125050", "1250.5": "125050", "0.29": "29"}
    else:
        dates = {"21.10.2026": "2026-10-21", "21. okt. 2026": "2026-10-21",
                 "21. oktober 2026": "2026-10-21", "21102026": "2026-10-21", "1.2": f"{year}-02-01"}
        times = {"9,30": "09:30", "9.30": "09:30"}
        prices = {"1 250,50": "125050", "1250.5": "125050", "1250,5": "125050"}
    wrong = []
    for (date, want), (time, want_time), (price, want_price) in zip(
            dates.items(), list(times.items()) * 4, list(prices.items()) * 5):
        read, errors = post_fields(page, date=date, time=time, price=price)
        if (read.get("date"), read.get("time"), read.get("price")) != (want, want_time, want_price) or errors:
            wrong.append((date, time, price, read, errors))
    t.check(not wrong, f"{language}: each form typed and posted is read as its value: {wrong}")
    read, errors = post_fields(page, date="31.11.2026", time="25:00", price="12.505")
    shown = page.locator("#field-date").input_value()
    t.check(shown == "31.11.2026" and len(errors) == 3 and not read,
            f"{language}: what cannot be read comes back as typed, with its error: {shown!r} {errors}")


def calendar(t, page, label, width, height):
    """Open #field-date's calendar and measure it; values its measures."""
    page.locator(".tun-date-input:has(#field-date) .tun-date-input-open").click()
    page.wait_for_timeout(400)
    return page.evaluate(CALENDAR, "field-date-calendar")


def desktop(t):
    for scheme in ("dark", "light"):
        page = t.desktop(scheme=scheme)
        page.sign_in("employee:anna")
        page.goto("/fields")
        today = today_of(page)
        field = page.evaluate("() => document.querySelector('.tun-date-input:has(#field-date)').getBoundingClientRect().toJSON()")
        c = calendar(t, page, scheme, 1280, 800)
        t.check(c["open"] and c["role"] == "dialog" and c["modal"] == "true"
                and c["name"] == f"{['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][today.month - 1]} {today.year}",
                f"1280px {scheme}: the button opens a dialog named by its month: {c['name']}")
        t.check(c["heads"] == ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] and c["abbr"] == "Monday"
                and c["cells"] == 42,
                f"1280px {scheme}: six weeks from Monday: {c['heads']} {c['cells']}")
        t.check(c["today"] == iso(today) and c["focus"] == iso(today) and c["tabbable"] == [iso(today)],
                f"1280px {scheme}: today marked, focused, the one day Tab reaches: {c['today']} {c['focus']}")
        t.check(c["top"] >= field["bottom"] - 0.5 and c["top"] - field["bottom"] <= 12
                and abs(c["left"] - field["left"]) <= 1 and c["right"] <= 1280 and c["bottom"] <= 800,
                f"1280px {scheme}: under the field, inside the window: {c['top']} {c['left']} {field}")
        t.check("opacity" in c["property"] and "translate" in c["property"]
                and "transform" not in c["property"] and c["duration"].startswith("0.15s"),
                f"1280px {scheme}: it fades and rises in over --duration-fast: {c['property']} {c['duration']}")
        page.screenshot(path=str(t.out / f"ui-fields-calendar-1280-{scheme}.png"))
        if scheme == "dark":
            continue

        # The keys of the WAI-ARIA date picker.
        walk = [("ArrowRight", today + datetime.timedelta(days=1)),
                ("ArrowDown", today + datetime.timedelta(days=8)),
                ("ArrowLeft", today + datetime.timedelta(days=7)),
                ("ArrowUp", today),
                ("PageDown", add_months(today, 1)),
                ("Shift+PageDown", add_months(today, 13)),
                ("Shift+PageUp", add_months(today, 1)),
                ("PageUp", today),
                ("Home", today - datetime.timedelta(days=today.weekday())),
                ("End", today - datetime.timedelta(days=today.weekday()) + datetime.timedelta(days=6))]
        wrong = []
        for key, want in walk:
            page.keyboard.press(key)
            got = page.evaluate(FOCUS)
            if got != iso(want):
                wrong.append((key, got, iso(want)))
        t.check(not wrong, f"1280px: the arrows, PageUp/PageDown, Shift, Home and End move the focus: {wrong}")
        page.keyboard.press("Tab")
        t.check(page.evaluate(FOCUS) != "" and page.evaluate("() => !!document.activeElement.closest('[data-tun-date-calendar]')"),
                "1280px: Tab stays inside the calendar")
        page.keyboard.press("Shift+Tab")
        sunday = today - datetime.timedelta(days=today.weekday()) + datetime.timedelta(days=6)
        page.keyboard.press("Enter")
        page.wait_for_timeout(300)
        c = page.evaluate(CALENDAR, "field-date-calendar")
        t.check(not c["open"] and page.locator("#field-date").input_value() == written_en(sunday)
                and "tun-date-input-open" in page.evaluate(FOCUS),
                f"1280px: Enter chooses, writes the day, closes, the focus on its button: "
                f"{page.locator('#field-date').input_value()!r} {page.evaluate(FOCUS)}")
        c = calendar(t, page, "light", 1280, 800)
        t.check(c["chosen"] == iso(sunday) and c["focus"] == iso(sunday)
                and len(set(c["weights"])) == 1 and len(set(c["sizes"])) == 1,
                f"1280px: it opens on the chosen day, chosen and today at the others' weight and size: "
                f"{c['chosen']} {c['weights']} {c['sizes']}")
        page.keyboard.press("Escape")
        page.wait_for_timeout(60)
        midway = page.evaluate(CALENDAR, "field-date-calendar")
        page.wait_for_timeout(300)
        gone = page.evaluate(CALENDAR, "field-date-calendar")
        t.check(not midway["open"] and midway["rects"] > 0 and float(midway["opacity"]) < 1
                and midway["duration"].startswith("0.16s") and gone["rects"] == 0,
                f"1280px: Escape closes it, still leaving midway over --duration-close, then gone: "
                f"{midway['rects']} {midway['opacity']} {midway['duration']} {gone['rects']}")
        t.check("tun-date-input-open" in page.evaluate(FOCUS), "1280px: Escape gives the focus back")
        calendar(t, page, "light", 1280, 800)
        page.mouse.click(1200, 700)
        page.wait_for_timeout(300)
        t.check(not page.evaluate(CALENDAR, "field-date-calendar")["open"]
                and "tun-date-input-open" in page.evaluate(FOCUS),
                f"1280px: a press outside closes it, the focus back: {page.evaluate(FOCUS)}")

        # A quick choice, and the days outside MIN and MAX.
        page.locator("#field-date").fill("")
        calendar(t, page, "light", 1280, 800)
        page.locator("#field-date-calendar [data-tun-date-quick]", has_text="Tomorrow").click()
        page.wait_for_timeout(300)
        t.check(page.locator("#field-date").input_value() == written_en(today + datetime.timedelta(days=1)),
                f"1280px: «Tomorrow» chooses its day: {page.locator('#field-date').input_value()!r}")
        page.locator(".tun-date-input:has(#field-return) .tun-date-input-open").click()
        page.wait_for_timeout(400)
        disabled = page.evaluate("() => [...document.querySelectorAll('#field-return-calendar td[aria-disabled=true]')].map((e) => e.dataset.date)")
        t.check(disabled and all(d < "2026-11-01" or d > "2026-12-31" for d in disabled),
                f"1280px: the days outside MIN and MAX are disabled: {disabled[:3]}…")
        page.locator(f"#field-return-calendar td[data-date='{disabled[0]}']").click(force=True)
        page.wait_for_timeout(200)
        t.check(page.locator("#field-return").input_value() == ""
                and page.evaluate(CALENDAR, "field-return-calendar")["open"],
                "1280px: a disabled day cannot be chosen")
        page.keyboard.press("Escape")

        # The amount: right-aligned in tabular figures.
        style = page.evaluate("() => { const s = getComputedStyle(document.querySelector('#field-price')); return [s.textAlign, s.fontVariantNumeric]; }")
        t.check(style[0] in ("end", "right") and "tabular-nums" in style[1],
                f"1280px: the amount right-aligned in tabular figures: {style}")
        t.check(not page.evaluate(WIDE_PAGE), "1280px: the page does not scroll sideways")
        typing(t, page, "en")


def phone(t):
    for width in (390, 360, 320):
        for scheme in (("light", "dark") if width == 390 else ("light",)):
            page = t.phone(width=width, scheme=scheme)
            page.sign_in("employee:anna")
            page.goto("/fields")
            t.check(not page.evaluate(WIDE_PAGE), f"{width}px {scheme}: the page does not scroll sideways")
            c = calendar(t, page, scheme, width, 844)
            t.check(c["open"] and c["left"] >= 11.5 and c["right"] <= width - 11.5
                    and c["bottom"] <= 844 - 11.5 and c["top"] >= 0 and c["radius"] == "12px"
                    and c["radiusEnd"] == "12px",
                    f"{width}px {scheme}: a floating sheet inside the window: {c['left']} {c['right']} {c['top']} {c['bottom']} {c['radius']}")
            t.check(c["dayHeight"] >= 40 and c["duration"].startswith("0.2s")
                    and c["dim"] == ("rgba(0, 0, 0, 0.4)" if scheme == "light" else "rgba(0, 0, 0, 0.54)"),
                    f"{width}px {scheme}: its days at least 2.5rem, rising over --duration over the dim: "
                    f"{c['dayHeight']} {c['duration']} {c['dim']}")
            close = page.locator("#field-date-calendar .tun-date-input-calendar-close button")
            t.check(close.is_visible(), f"{width}px: the sheet has its close button")
            if width == 390:
                page.screenshot(path=str(t.out / f"ui-fields-calendar-390-{scheme}.png"))
            close.click()
            page.wait_for_timeout(300)
            t.check(not page.evaluate(CALENDAR, "field-date-calendar")["open"]
                    and "tun-date-input-open" in page.evaluate(FOCUS),
                    f"{width}px: the close button closes it, the focus back")


# The cards of the scenario, by the day each was reported on.
REPORTED = {"2026-10-21": 26, "2026-11-03": 1, "2026-11-10": 1, "2026-12-02": 1, "2026-09-15": 1}


def within(start, end):
    return sum(n for day, n in REPORTED.items() if start <= day <= end)


def rows(page):
    return page.evaluate("() => document.querySelectorAll('.tun-table tbody tr').length")


def period(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/graph")
    page.goto("/days")
    today = datetime.date.fromisoformat(page.evaluate(
        "() => document.querySelector('#days-toolbar [data-tun-date-calendar]').dataset.today"))
    page.evaluate("() => { window.tunFieldsMark = 1; }")
    requests = []
    page.on("request", lambda r: requests.append(r.url) if "/days" in r.url else None)
    history = page.evaluate("() => history.length")

    page.locator("#days-toolbar-from-button").click()
    page.wait_for_timeout(300)
    t.check(page.evaluate("() => document.activeElement.textContent") == "Today",
            "the period opens on its quick choices, not a field a phone would type in")
    page.locator("#days-toolbar-from-choices a", has_text="This month").click()
    start = today.replace(day=1)
    end = add_months(start, 1) - datetime.timedelta(days=1)
    page.wait_for_function("(from) => decodeURIComponent(location.search.replace(/\\+/g, ' ')).includes(from)",
                           arg=f"from={written_en(start)}", timeout=10000)
    page.wait_for_timeout(300)
    t.check(rows(page) == within(iso(start), iso(end)) and len(requests) == 1
            and page.evaluate("() => history.length") == history + 1,
            f"«This month» applies once: {rows(page)} rows, {len(requests)} requests")
    t.check(page.evaluate("() => window.tunFieldsMark") == 1
            and not page.evaluate("() => document.getElementById('days-toolbar-from-choices').matches(':popover-open')")
            and page.evaluate("() => document.activeElement.id") == "days-toolbar-from-button",
            "the page is not loaded again; the popover closes, the focus on its button")
    t.check(page.locator("#days-toolbar-from-button").inner_text().startswith("Reported: "),
            f"its button says the period: {page.locator('#days-toolbar-from-button').inner_text()!r}")

    # A day chosen in the calendar applies once, the popover staying open.
    page.locator("#days-toolbar-from-button").click()
    page.wait_for_timeout(300)
    page.locator(".tun-date-input:has(#days-toolbar-from-start) .tun-date-input-open").click()
    page.wait_for_timeout(300)
    page.locator("#days-toolbar-from-start-calendar td[data-date]:not([data-outside])").nth(4).click()
    page.wait_for_timeout(800)
    t.check(len(requests) == 2 and page.evaluate("() => history.length") == history + 2
            and page.evaluate("() => document.getElementById('days-toolbar-from-choices').matches(':popover-open')"),
            f"a day chosen in the calendar applies once, the period still open: {len(requests)} requests")

    # A date typed applies on Enter, once, and leaving the field sends nothing more.
    to = page.locator("#days-toolbar-from-end")
    to.fill("")
    to.type("15.11.2026", delay=20)
    page.wait_for_timeout(300)
    t.check(len(requests) == 2, f"nothing is sent while a date is typed: {len(requests)}")
    to.press("Enter")
    page.wait_for_function("() => location.search.includes('to=15.11.2026')", timeout=10000)
    page.wait_for_timeout(300)
    page.keyboard.press("Tab")
    page.wait_for_timeout(500)
    t.check(len(requests) == 3 and page.evaluate("() => history.length") == history + 3,
            f"Enter applies it once, and leaving the field sends no more: {len(requests)} requests")
    page.screenshot(path=str(t.out / "ui-fields-period-1280-light.png"))

    page.keyboard.press("Escape")
    page.go_back()
    page.wait_for_function("() => !location.search.includes('15.11.2026')", timeout=10000)
    page.go_back()
    page.wait_for_function("(from) => decodeURIComponent(location.search.replace(/\\+/g, ' ')).includes(from)",
                           arg=f"from={written_en(start)}", timeout=10000)
    page.wait_for_function("(count) => document.querySelectorAll('.tun-table tbody tr').length === count",
                           arg=within(iso(start), iso(end)), timeout=10000)
    t.check(rows(page) == within(iso(start), iso(end)), "Back steps through each period chosen")
    page.locator("#days-toolbar-from a.tun-list-toolbar-filter-clear").first.click()
    page.wait_for_function("() => location.search.includes('from=&to=')", timeout=10000)
    t.check(rows(page) == sum(REPORTED.values()), "× clears the period")
    t.check(not page.evaluate(WIDE_PAGE), "the page does not scroll sideways")


def sheet(t):
    page = t.phone()
    page.sign_in("employee:anna")
    page.goto("/days")
    page.locator("#days-toolbar [data-tun-list-toolbar-fold]").click()
    page.wait_for_timeout(500)
    row = page.evaluate("""() => { const d = document.querySelector('#days-toolbar-sheet');
      const heading = d.querySelector('#days-toolbar-from .tun-list-toolbar-filter-heading');
      return {open: d.open, heading: heading.getBoundingClientRect().width > 0,
              quick: d.querySelectorAll('#days-toolbar-from [data-tun-list-toolbar-quick]').length,
              fields: [...d.querySelectorAll('#days-toolbar-from .tun-date-input-control')]
                .filter((e) => e.getBoundingClientRect().width > 0).length}; }""")
    t.check(row["open"] and row["heading"] and row["quick"] == 4 and row["fields"] == 2,
            f"390px: the period is a row of the «Filters» sheet, its choices and fields under it: {row}")
    page.screenshot(path=str(t.out / "ui-fields-period-sheet-390-light.png"))
    page.locator("#days-toolbar-sheet a", has_text="Last month").tap()
    page.wait_for_function("() => location.search.includes('from=')", timeout=10000)
    page.wait_for_timeout(300)
    t.check(page.evaluate("() => document.getElementById('days-toolbar-sheet').open"),
            "390px: a quick choice applies with the sheet open")
    t.check(not page.evaluate(WIDE_PAGE), "390px: the page does not scroll sideways")


def without_javascript(t):
    page = t.phone(javascript=False)
    page.sign_in("employee:anna")
    page.goto("/fields")
    t.check(not page.locator(".tun-date-input-open").first.is_visible(),
            "without JavaScript there is no calendar button")
    page.locator("#field-date").fill("21.10.2026")
    page.locator("form[action='/fields'] button[type=submit]").click()
    page.wait_for_selector("output[data-read=date]")
    t.check(page.locator("output[data-read=date]").inner_text() == "2026-10-21",
            "without JavaScript the field posts and the server reads it")
    page.goto("/days")
    page.locator("#days-toolbar-from-button").click()
    page.locator("#days-toolbar-from-start").fill("1.11.2026")
    page.locator("#days-toolbar-from-end").fill("30.11.2026")
    page.locator("#days-toolbar [data-tun-list-toolbar-apply]").click()
    page.wait_for_url(re.compile(r"from=1\.11\.2026"))
    t.check(rows(page) == within("2026-11-01", "2026-11-30"), "without JavaScript «Apply» applies the period")
    page.locator("#days-toolbar-from-button").click()
    page.locator("#days-toolbar-from-choices a", has_text="Today").click()
    page.wait_for_url(re.compile(r"from=\d{4}-\d{2}-\d{2}&to=\d{4}-\d{2}-\d{2}"))
    t.check(True, "and a quick choice is a link to its period")


def norwegian(t):
    page = t.desktop()
    page.sign_in("admin:jonas")
    page.goto("/settings")
    page.locator("#setting-locale-language").select_option(label="Norsk (bokmål)")
    form = page.locator("form").filter(has=page.locator("#setting-locale-language"))
    form.locator("button[type=submit]").first.click()
    page.wait_for_url(re.compile(r"saved=locale\.language"))
    page.goto("/fields")
    c = calendar(t, page, "light", 1280, 800)
    today = today_of(page)
    months = ["januar", "februar", "mars", "april", "mai", "juni", "juli", "august", "september",
              "oktober", "november", "desember"]
    t.check(c["name"] == f"{months[today.month - 1]} {today.year}" and c["heads"][0] == "ma"
            and c["abbr"] == "mandag",
            f"nb: the calendar's names are Norwegian: {c['name']} {c['heads']}")
    page.keyboard.press("Enter")
    page.wait_for_timeout(300)
    t.check(page.locator("#field-date").input_value() == today.strftime("%d.%m.%Y"),
            f"nb: a chosen day is written as Norwegian writes a date: {page.locator('#field-date').input_value()!r}")
    typing(t, page, "nb")


def run(t):
    desktop(t)
    phone(t)
    period(t)
    sheet(t)
    without_javascript(t)
    norwegian(t)
