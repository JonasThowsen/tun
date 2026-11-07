# Tooltip i grafen blir et høyt, svart felt for punkter i øvre halvdel

- loop: chart-tooltip-height
- mode: reviewed
- stage: ship
- base: d101e5832f8742f8bd76afb7bbd250c46cddf99c
- client: /home/jonas/coding/kurs
- client-base: e95e10419d03b8267d0750aa7496022b62b08ec8
- verified: 6f1c98175fb417cc5557365fb6ef27043dcb93f5 61037d83a04b7d7c9204335df3f21142fcc2d0df
- shown: 6f1c98175fb417cc5557365fb6ef27043dcb93f5 61037d83a04b7d7c9204335df3f21142fcc2d0df

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
- 2026-11-07 11:43  verify 1: passed build, test, check, client-check
- 2026-11-07 11:44  shown (/shares/AAPL:xnas, /watchlist)
- 2026-11-07 11:44  gate B asked of a reviewer
- 2026-11-07 11:47  gate B: changes (reviewer): The client tree verified and shown held the uncommitted watchlist-currency work; rebase onto it once committed and verify and show again.
- 2026-11-07 11:58  verify 2: failed test
- 2026-11-07 12:20  rebased: tun a47f748 → d101e58, kurs aac2713 → f9f15da
- 2026-11-07 12:27  verify 3: failed test
- 2026-11-07 12:36  verify 4: failed test
- 2026-11-07 13:04  verify 5: passed build, test, check, client-check
- 2026-11-07 13:05  shown (/shares/AAPL:xnas)
- 2026-11-07 13:05  gate B asked of a reviewer
- 2026-11-07 13:09  gate B: approve (reviewer): Client tree holds only this loop's work; criterion 1 met by a walk that fails without the fix; criterion 2 by the existing checks; spec and version agree.
- 2026-11-07 13:10  rebased: tun d101e58 → d101e58, kurs f9f15da → e95e104
- 2026-11-07 13:18  verify 6: passed build, test, check, client-check
- 2026-11-07 13:18  shown (/shares/AAPL:xnas)
- 2026-11-07 13:18  gate B asked of a reviewer
- 2026-11-07 13:19  gate B: approve (reviewer): Tun diff byte-identical to the approved one; client diff empty on e95e104; verify round 6 passed.
