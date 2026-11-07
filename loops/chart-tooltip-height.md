# Tooltip i grafen blir et høyt, svart felt for punkter i øvre halvdel

- loop: chart-tooltip-height
- mode: reviewed
- stage: build
- base: a47f7486e9f01b9a67e3f9261aecf69ca6be1da9
- client: /home/jonas/coding/kurs
- client-base: aac2713237cb7a3fed43af47396a14bbaf62c292

## Brief

Jonas, 2026-11-07, on kurs's `/shares/AAPL:xnas` with two screenshots:
«there seems to be a visual bug, where sometimes there is this black panel
that shows up when hovering the graph». At 08.09 (316,22, low in the plot)
the tooltip is right; at 11.09 (332,27, high in the plot) a dark panel runs
from the tooltip down to the plot's bottom.

The line chart's script puts the tooltip at the bottom of the plot for a
point in its upper half by setting `bottom: 0` and clearing `top` with
`''`. Clearing an inline style brings back the stylesheet's `top: 0`, so the
tooltip is pinned to both edges and stretches. The showcase's price chart
reproduces it: walking the points with the keys, the tooltip is 44 px at
some and 192 px, pinned top and bottom, at others.

## Criteria

1. Walking every point of the showcase's price chart with the keys, the
   tooltip is equally tall at each, no taller than its two lines (under
   64 px), and is at the top of the plot for some points and at the bottom
   for others, never pinned to both.
2. The rest of the chart's behaviour (pointer, keys, Escape, focus, live
   region, no script) is as before: the existing `price-chart` checks pass.

## Decisions

- The fix sets `top` and `bottom` to `auto` rather than `''`: the smallest
  change, in the line that placed it. Taking `top: 0` out of the stylesheet
  would work as well, since only the script shows the tooltip and it always
  sets both edges.
- The check also holds which side the tooltip takes for each point, from
  the plot's own points, since the spec now says it.
- `spec/ui.md` §6 now says where the tooltip sits and that it is only as
  tall as its two lines, so the check has a contract to hold.
- Core 2.8.2, a fix. kurs takes it with `tun update`; ferdig and
  nixploy-dashboard have no line chart, so they update with their next
  change.

## Log

- 2026-11-07 11:31  started, reviewed
- 2026-11-07 11:33  gate A asked of a reviewer
- 2026-11-07 11:36  gate A: approve (reviewer): Diagnosis matches the code, criteria cover the brief and are decidable, spec agrees. Notes acted on: the check now holds the side per point; the first Decision's reason corrected.
