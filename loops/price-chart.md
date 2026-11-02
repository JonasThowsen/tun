# A line chart and a sparkline for prices over time

- loop: price-chart
- mode: reviewed
- stage: ship
- base: 60e5b44287bce8db630cae50ae1709bfcda72f34
- after: http-json-get
- verified: f64b5fd24e5403593aeac840048a0dc451247bee
- shown: f64b5fd24e5403593aeac840048a0dc451247bee

## Brief

Jonas, in this session (2026-11-02), wants a dashboard for trading stocks
on Oslo Børs and in the US, built as a Tun client: a watchlist with each
stock's last price and a three-month price line, and a page per stock.
«You can start on the Tun work right away, i would like to get somethjng
working quickly, so chart can also be built.» Charts are under «Not yet»
in spec/ui.md §9. The prices come through `http-json-get` (loop
http-json-get, before this one).

## Criteria

1. `(line-chart (:label L :points P :digits D))` draws P, conses of a
   universal time and a real in any order, as a 2px line in `--chart-1`
   over a 10% wash, in an SVG that fills the chart's width at a fixed
   height; the line stays 2px wide at 320 px and at 1280 px.
2. The last point has a round dot, radius 4, with a 2px ring in
   `--card`, at 320 px and at 1280 px.
3. The y axis has three to five ticks spaced by a step of 1, 2, 2.5 or
   5 times a power of ten, each a multiple of the step, the lowest at or
   below the least value and the highest at or above the greatest, each
   a 1px gridline and a label with the step's decimals; when every value
   is V, the ticks are V and one step either side, the least step at or
   above |V|/10 (1 at 0).
4. The x axis has two to four labels at evenly spaced times, no two
   reading the same: `day-text` (en `21 Oct`, nb `21.10.`), the full
   date when the first and last point fall in different calendar years,
   the time of day when they all fall on one day, in the tenant's time
   zone; none overlap at 320 px, full dates across a new year included
   (two at most). One point has its label alone.
5. The caption, the last value, the axis labels and the tooltip are
   `--text-xs` at every width; no text is in `--chart-1`; L and the last
   value stand above the plot.
6. With D, the last value, the table, the tooltip and a sparkline's
   label have D decimals (the tick labels keep the step's): 281.4 with
   D 2 is `281.40`, in nb `281,40`.
7. A `<details>`, closed by default, holds a table of every time and
   value. With JavaScript off, the line, the dot, the ticks and the
   labels are drawn and the `<details>` opens.
8. The plot has `role="img"` and L as its `aria-label`. With
   JavaScript, the plot is focusable; a pointer over it, or the
   arrow keys, Home and End when it has focus, moves a vertical hairline
   to the nearest point and shows a tooltip with the value, then the
   date, in a polite live region; Escape, leaving the plot or moving
   focus away hides them.
9. No points: «No data» and no table. One point: the dot, no line.
   More than 2000 points, or a point that is not a cons of a universal
   time and a real: an error in the caller's code.
10. `(sparkline (:points P :label L :digits D))` draws a 1.5px line in
    `--chart-1`, 6rem wide and `1lh` high, no axes; it has `role="img"`
    and an `aria-label` of L with its first and last value joined by a
    catalogued word (en «to», nb «til»); one point is a dot, none is
    nothing with «No data» in its label.
11. Extension output may carry `preserveAspectRatio`; the renderer still
    refuses `style`, SVG `<text>`, and everything it refused before.
12. The specimen (/ui) shows both, and the showcase's browser checks
    take them in light and dark at 320 px, 390 px and on a desktop.

## Decisions

- **Server-rendered SVG, no chart library.** Every page works without
  JavaScript (§2), and a library would be Tun's first build step. The
  component writes the path; its script only adds the crosshair.
- **Placed without `style`.** Pages carry no `style` attribute (§4) and
  the renderer refuses one. The line is a stretched SVG, which needs
  `preserveAspectRatio="none"`; that attribute is added to the
  allowlist, since it only says how a drawing fits its box and loads or
  runs nothing. The dot is in a second SVG without a viewBox, placed by
  percentage `cx`/`cy`, so it stays round. The tick labels are HTML in
  a grid of equal rows, which works because the ticks are evenly spaced
  and the axis runs exactly from the lowest tick to the highest; the x
  labels likewise at evenly spaced times in equal columns. Only the
  crosshair and the tooltip are placed by the script, which may set a
  style (§4).
- **One series.** The brief is a line per share. Several series bring a
  legend, colours that fail contrast on white, and series whose trading
  days differ (Oslo and New York); they wait for a client that compares
  shares, under «Not yet».
- **The last value above the plot, not at the line's end.** The end of
  the line is at any height, and a label there needs a `style`. Above
  the plot it is the figure a trader reads first.
- **`--chart-1`, blue, Tun's choice of shadcn's token:** 4.4:1 on the
  light card and 4.9:1 on the dark, both above 3:1 for a graphic. Text
  is never in it.
- **`:digits`, and `number-text` takes it too,** since a price is
  written to two decimals and `number-text` drops trailing zeros. The
  ticks use the step's own decimals.
- **`day-text`** beside `date-text`, for the axis, in i18n §6.2.
- **Not from zero.** A price chart from zero flattens every move; a
  line needs no zero baseline.
- **The tooltip only enhances.** The table holds every value.
- **Points are passed in, not fetched**; at most 2000, a bound like every
  other input (`pitfalls.md`).
- **Group:** Data, in a new file `src/web/ui/charts.lisp`.
- Core 2.6.0, after http-json-get's 2.5.0.

## Log

- 2026-11-02 15:41  started, reviewed
- 2026-11-02 15:43  gate A asked of a reviewer
- 2026-11-02 15:48  gate A: changes (reviewer): Placement needs style/preserveAspectRatio the allowlist refuses; series with different times; how values are written (digits); edge inputs; palette provenance and contrast claims; Escape closes the tooltip; wording; the short date belongs in i18n §6.2
- 2026-11-02 15:49  gate A asked of a reviewer
- 2026-11-02 15:53  gate A: changes (reviewer): Tick step and multiples; equal-values rounding; D excludes ticks; different calendar years, no duplicate x labels, one point; 320 px in checks; table text size; sparkline width; day-text's argument; sparkline label language and role
- 2026-11-02 15:53  gate A asked of the person
- 2026-11-02 15:54  gate A: approve (jonas): «Approve (Recommended)»
- 2026-11-02 16:44  rebased: tun ba21133 → 60e5b44
- 2026-11-02 17:07  verify 1: passed build, test, check
- 2026-11-02 17:07  shown (/prices, /ui/line-chart)
- 2026-11-02 17:07  gate B asked of a reviewer
- 2026-11-02 17:10  gate B: changes (reviewer): Full-date x labels across a new year overlap at 320 px (three in 210 px); check a cross-year chart at 320 px and cap :date labels; spec says grid where the code uses flex; refill paragraphs; Watchlist caption shown twice
- 2026-11-02 17:25  verify 2: passed build, test, check
- 2026-11-02 17:26  shown (/prices, /prices/ORK.OL, /ui/line-chart)
- 2026-11-02 17:26  gate B asked of a reviewer
- 2026-11-02 17:28  gate B: approve (reviewer): Earlier findings fixed; every criterion tested or checked; verify round 2 green. Minor notes: refill three spec lines, live region wording, duplicate card title in the showcase, focus-away not checked
