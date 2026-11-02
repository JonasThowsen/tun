"""A share's price as a line chart and a watchlist of sparklines, at 320px,
390px and on a desktop, light and dark: the line fills the plot at 2px, the
dot on the last price is round, the axis labels keep their size and do not
overlap, nothing scrolls sideways; a pointer or the keys show a tooltip that
Escape hides; without the script the chart is drawn and its table opens
(spec/ui.md 3, 6)."""

CHART = "#price"

# What a check needs to know of the chart's geometry and text, measured in
# the page.
MEASURE = """(selector) => {
  const chart = document.querySelector(selector);
  const plot = chart.querySelector('.tun-line-chart-plot');
  const line = chart.querySelector('.tun-line-chart-line');
  const stroke = chart.querySelector('.tun-line-chart-stroke');
  const dot = chart.querySelector('.tun-line-chart-dot').getBoundingClientRect();
  const labels = [...chart.querySelectorAll('.tun-line-chart-x > span')].map((span) => {
    const range = document.createRange();
    range.selectNodeContents(span);
    const box = range.getBoundingClientRect();
    return {left: box.left, right: box.right};
  });
  const xs = getComputedStyle(document.documentElement).getPropertyValue('--text-xs').trim();
  const probe = document.createElement('span');
  probe.style.fontSize = xs;
  document.body.append(probe);
  const xsPixels = getComputedStyle(probe).fontSize;
  probe.remove();
  return {
    plotWidth: plot.getBoundingClientRect().width,
    lineWidth: line.getBoundingClientRect().width,
    strokeWidth: getComputedStyle(stroke).strokeWidth,
    strokeColour: getComputedStyle(stroke).stroke,
    dotWidth: dot.width, dotHeight: dot.height,
    labels,
    tickSize: getComputedStyle(chart.querySelector('.tun-line-chart-y > span')).fontSize,
    labelSize: getComputedStyle(chart.querySelector('.tun-line-chart-x > span')).fontSize,
    lastColour: getComputedStyle(chart.querySelector('.tun-line-chart-last')).color,
    xsPixels,
    pageScrolls: document.documentElement.scrollWidth > innerWidth,
  };
}"""


def overlaps(labels):
    return any(a["right"] > b["left"] for a, b in zip(labels, labels[1:]))


def tooltip(page):
    return page.locator(f"{CHART} .tun-line-chart-tooltip")


def look(t, page, name, blue):
    """The checks that hold at every width and in each scheme."""
    m = page.evaluate(MEASURE, CHART)
    t.check(abs(m["lineWidth"] - m["plotWidth"]) < 1,
            f"{name}: the line fills the plot ({m['lineWidth']} of {m['plotWidth']})")
    t.check(m["strokeWidth"] == "2px", f"{name}: the line is 2px wide: {m['strokeWidth']}")
    t.check(m["strokeColour"] == blue, f"{name}: in --chart-1: {m['strokeColour']}")
    t.check(abs(m["dotWidth"] - m["dotHeight"]) < 0.5 and m["dotWidth"] >= 8,
            f"{name}: the dot is round: {m['dotWidth']}×{m['dotHeight']}")
    t.check(2 <= len(m["labels"]) <= 4 and not overlaps(m["labels"]),
            f"{name}: 2 to 4 x labels, none overlapping: {m['labels']}")
    t.check(m["tickSize"] == m["xsPixels"] and m["labelSize"] == m["xsPixels"],
            f"{name}: labels in --text-xs ({m['xsPixels']}): {m['tickSize']}, {m['labelSize']}")
    t.check(m["lastColour"] != blue, f"{name}: the last value is not in the line's colour")
    t.check(not m["pageScrolls"], f"{name}: the page does not scroll sideways")


def run(t):
    light, dark = "rgb(42, 120, 214)", "rgb(57, 135, 229)"
    for width in (320, 390):
        for scheme, blue in (("light", light), ("dark", dark)):
            phone = t.phone(width=width, scheme=scheme)
            phone.sign_in("employee:anna")
            phone.goto("/prices")
            look(t, phone, f"{width}px {scheme}", blue)
            spark = phone.locator(".tun-sparkline").first
            t.check(spark.get_attribute("role") == "img"
                    and spark.get_attribute("aria-label").startswith("EQNR.OL: "),
                    f"{width}px {scheme}: a sparkline reads out its first and last value")
            box = spark.bounding_box()
            t.check(box and abs(box["width"] - 96) < 1,
                    f"{width}px {scheme}: a sparkline is 6rem wide: {box}")
            phone.goto("/prices/ORK.OL")
            labels = phone.evaluate(MEASURE, CHART)["labels"]
            t.check(len(labels) == 2 and not overlaps(labels)
                    and all(0 <= l["left"] and l["right"] <= width for l in labels),
                    f"{width}px {scheme}: full dates across a new year fit: {labels}")

    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/prices")
    look(t, page, "desktop light", light)
    dark_page = t.desktop(scheme="dark")
    dark_page.sign_in("employee:anna")
    dark_page.goto("/prices")
    look(t, dark_page, "desktop dark", dark)

    plot = page.locator(f"{CHART} .tun-line-chart-plot")
    box = plot.bounding_box()
    page.mouse.move(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
    t.check(tooltip(page).is_visible(), "a pointer over the plot shows the tooltip")
    t.check(page.locator(f"{CHART} .tun-line-chart-crosshair").is_visible(),
            "and the crosshair")
    page.keyboard.press("Escape")
    t.check(not tooltip(page).is_visible(), "Escape hides a tooltip the pointer showed")
    page.mouse.move(box["x"] + box["width"] / 2, box["y"] - 40)
    page.mouse.move(box["x"] + 10, box["y"] + 10)
    t.check(tooltip(page).is_visible(), "it comes back with the pointer")
    page.mouse.move(0, 0)
    t.check(not tooltip(page).is_visible(), "leaving the plot hides it")

    plot.focus()
    t.check(page.evaluate("document.activeElement?.classList.contains('tun-line-chart-plot')"),
            "the script makes the plot focusable")
    page.keyboard.press("End")
    last = page.locator(f"{CHART} .tun-line-chart-last").inner_text()
    t.check(tooltip(page).locator("strong").inner_text() == last,
            f"End shows the last point's value, {last}")
    page.keyboard.press("Home")
    page.keyboard.press("ArrowRight")
    second = tooltip(page).locator("strong").inner_text()
    t.check(second != last and page.locator(f"{CHART} .tun-line-chart-live").inner_text()
            .startswith(second), f"the arrow keys move it, and the live region says {second}")
    page.keyboard.press("Escape")
    t.check(not tooltip(page).is_visible(), "Escape hides it")

    off = t.desktop(javascript=False)
    off.sign_in("employee:anna")
    off.goto("/prices")
    t.check(off.locator(f"{CHART} .tun-line-chart-stroke").count() == 1
            and off.locator(f"{CHART} .tun-line-chart-dot").is_visible(),
            "without the script: the line and the dot are drawn")
    t.check(off.locator(f"{CHART} .tun-line-chart-plot").get_attribute("tabindex") is None,
            "and the plot is not focusable, since its keys would do nothing")
    t.check(not off.locator(f"{CHART} table").is_visible(), "the table starts closed")
    off.locator(f"{CHART} summary").click()
    t.check(off.locator(f"{CHART} table").is_visible(), "and opens")
    t.check(off.locator(f"{CHART} tbody tr").count() == 63, "with every point")
