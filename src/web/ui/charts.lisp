;;;; web/ui/charts.lisp -- a value over time (spec/ui.md 6): LINE-CHART, a
;;;; share's price on a page of its own, and SPARKLINE, the same in a line of
;;;; text.  Both are drawn on the server as SVG, so they work without
;;;; JavaScript; the script only adds the crosshair and its tooltip.
;;;;
;;;; Pages carry no style attribute (spec/ui.md 4), so nothing is placed by
;;;; an inline position.  The line is a path in an SVG stretched to the
;;;; plot (preserveAspectRatio none), the dot and the gridlines are in an
;;;; SVG placed by percentage, and the tick labels stand in flex rows and
;;;; columns whose items fall where the evenly spaced ticks do.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +chart-point-limit+ 2000
  "The most points a chart or a sparkline takes, as every input is bounded.")

(defparameter +drawing-size+ 1000
  "The width and height of the stretched drawing's own coordinates.")

;;; ------------------------------------------------------------------
;;; Points

(defun chart-points (points)
  "POINTS, a list of conses of a universal time and a real, checked and
sorted by time.  Signals an error in the caller's code for anything else, or
for more than +CHART-POINT-LIMIT+ of them."
  (unless (listp points)
    (error "A chart's points are a list, not ~s" points))
  (when (> (length points) +chart-point-limit+)
    (error "A chart takes at most ~d points, not ~d" +chart-point-limit+ (length points)))
  (dolist (point points)
    (unless (and (consp point) (typep (car point) '(integer 0)) (realp (cdr point)))
      (error "A chart's point is a cons of a universal time and a real, not ~s" point)))
  (sort (copy-list points) #'< :key #'car))

(defun value-text (value digits)
  "VALUE as the chart writes it: with DIGITS decimals, or as NUMBER-TEXT
writes it without them."
  (if digits (number-text value :digits digits) (number-text value)))

;;; ------------------------------------------------------------------
;;; The specimen's prices

(defun specimen-prices (count interval start)
  "COUNT made-up prices, INTERVAL seconds apart from 1 August 2026, 09:00 in
Oslo, starting at START and moving by a fixed pseudo-random walk, so the
specimen shows the same line every time."
  (let ((seed 20261102) (price start)
        (from (encode-universal-time 0 0 7 1 8 2026 0)))
    (loop for i below count
          collect (cons (+ from (* i interval)) (/ (round price 1/100) 100d0))
          do (setf seed (mod (+ (* seed 1103515245) 12345) 2147483648)
                   price (* price (+ 1 (/ (- (mod seed 1000) 480) 40000d0)))))))

;;; ------------------------------------------------------------------
;;; The y axis

(defparameter +step-multipliers+ '(1 2 5/2 5)
  "A round step is one of these times a power of ten.")

(defun round-step-at-least (least)
  "The least round step at or above LEAST, a positive real."
  (let ((power (expt 10 (floor (log least 10)))))
    ;; LOG of a double can land a hair under an exact power of ten, so the
    ;; search starts one power lower and takes the first step that fits.
    (loop for scale in (list (/ power 10) power (* power 10))
          do (dolist (multiplier +step-multipliers+)
               (let ((step (* multiplier scale)))
                 (when (>= step least)
                   (return-from round-step-at-least step)))))
    (* 10 power)))

(defun next-round-step (step)
  "The round step after STEP."
  (round-step-at-least (* step 101/100)))

(defun axis-ticks (least greatest)
  "The y axis's ticks for values from LEAST to GREATEST, exact rationals:
three to five multiples of a round step, the first at or below LEAST and the
last at or above GREATEST; or, when they are the same value V, V and one
round step either side (spec/ui.md 6).  The second value is the step."
  (let ((least (rational least)) (greatest (rational greatest)))
    (if (= least greatest)
        (let ((step (if (zerop least) 1 (round-step-at-least (/ (abs least) 10)))))
          (values (list (- least step) least (+ least step)) step))
        (loop for step = (round-step-at-least (/ (- greatest least) 4))
                then (next-round-step step)
              for first = (* step (floor least step))
              for last = (* step (ceiling greatest step))
              for count = (1+ (round (- last first) step))
              when (<= count 5)
                return (values (loop for i below count collect (+ first (* i step)))
                               step)))))

(defun step-digits (step)
  "How many decimals STEP, an exact rational, has: 0 for 10, 1 for 5/2."
  (or (loop for digits from 0 to 6
            when (integerp (* step (expt 10 digits)))
              return digits)
      6))

;;; ------------------------------------------------------------------
;;; The x axis

(defun time-kind (points)
  "How the times of POINTS are written: :TIME, the time of day, when there
are two or more and all fall on one day in the tenant's time zone; :DATE,
the full date, when the first and the last fall in different calendar
years; else :DAY, the day without its year."
  (let ((first (local-date-of (car (first points))))
        (last (local-date-of (car (first (last points))))))
    (cond ((and (rest points) (equal first last)) :time)
          ((string/= (subseq first 0 4) (subseq last 0 4)) :date)
          (t :day))))

(defun axis-label (ut kind)
  "The instant UT as the x axis writes a time of KIND."
  (ecase kind
    (:time (local-time-of ut))
    (:date (date-text (local-date-of ut)))
    (:day (day-text (local-date-of ut)))))

(defun axis-times (points)
  "The x axis's labels for POINTS, at evenly spaced times from the first to
the last: the most of four, three and two that read differently, else the
first alone.  A full date is about twice as wide as a day, so there are two
of them at most, which fit at 320px."
  (let* ((start (car (first points)))
         (end (car (first (last points))))
         (kind (time-kind points)))
    (or (loop for count from (if (eq kind :date) 2 4) downto 2
              for labels = (loop for i below count
                                 collect (axis-label (+ start (round (* i (- end start))
                                                                     (1- count)))
                                                     kind))
              when (= count (length (remove-duplicates labels :test #'string=)))
                return labels)
        (list (axis-label start kind)))))

(defun point-time-text (points)
  "The function that writes a point's time in the table and the tooltip:
its date and time of day when the x axis shows times of day, else its date."
  (if (eq (time-kind points) :time)
      #'instant-text
      (lambda (ut) (date-text (local-date-of ut)))))

;;; ------------------------------------------------------------------
;;; The drawing

(defun fraction (value from to)
  "Where VALUE lies from FROM (0) to TO (1), or 1/2 when they are equal."
  (if (= from to) 1/2 (/ (- (rational value) from) (- to from))))

(defun point-fractions (points ticks)
  "Each of POINTS as the fractions of the plot's width and height it is
drawn at, measured from the left and the top; a lone point in the middle."
  (let ((start (car (first points))) (end (car (first (last points))))
        (low (first ticks)) (high (first (last ticks))))
    (mapcar (lambda (point)
              (cons (fraction (car point) start end)
                    (- 1 (fraction (cdr point) low high))))
            points)))

(defun drawing-coordinate (fraction)
  "FRACTION of the drawing's size, to one decimal."
  (format nil "~,1f" (float (* fraction +drawing-size+) 1d0)))

(defun line-path (fractions)
  "The SVG path through FRACTIONS, in the drawing's coordinates."
  (format nil "M~{~a~^ L~}"
          (mapcar (lambda (fraction)
                    (format nil "~a,~a" (drawing-coordinate (car fraction))
                            (drawing-coordinate (cdr fraction))))
                  fractions)))

(defun wash-path (fractions)
  "The SVG path of the area under the line through FRACTIONS."
  (format nil "~a L~a,~d L~a,~d Z" (line-path fractions)
          (drawing-coordinate (car (first (last fractions)))) +drawing-size+
          (drawing-coordinate (car (first fractions))) +drawing-size+))

(defun percent (fraction)
  (format nil "~,2f%" (float (* fraction 100) 1d0)))

(defun stretched-line (fractions)
  "The line and its wash, in an SVG stretched to the plot; nothing for a
single point, which has no line."
  (when (rest fractions)
    `(:svg (:@ :class "tun-line-chart-line" :viewbox ,(format nil "0 0 ~d ~d" +drawing-size+
                                                              +drawing-size+)
               :preserveaspectratio "none" :aria-hidden "true" :focusable "false")
           (:path (:@ :class "tun-line-chart-wash" :d ,(wash-path fractions)))
           (:path (:@ :class "tun-line-chart-stroke" :d ,(line-path fractions))))))

(defun marks (fractions tick-count)
  "The gridlines, one per tick, and the dot on the last point, in an SVG
whose coordinates are the plot's own, so the dot stays round."
  (let ((last (first (last fractions))))
    `(:svg (:@ :class "tun-line-chart-marks" :aria-hidden "true" :focusable "false")
           ,@(loop for i below tick-count
                   for y = (percent (/ i (1- tick-count)))
                   collect `(:line (:@ :class "tun-line-chart-gridline"
                                       :x1 "0" :x2 "100%" :y1 ,y :y2 ,y)))
           (:circle (:@ :class "tun-line-chart-dot" :r "4"
                        :cx ,(percent (car last)) :cy ,(percent (cdr last)))))))

(defun crosshair-points (points fractions digits time-text)
  "The points as the script reads them: for each, its x and y fractions,
its value as the tooltip writes it and its time, as JSON."
  (to-json-string
   (jarr (mapcar (lambda (point fraction)
                   (jarr (list (float (car fraction) 1d0) (float (cdr fraction) 1d0)
                               (value-text (cdr point) digits)
                               (funcall time-text (car point)))))
                 points fractions))))

;;; ------------------------------------------------------------------
;;; Line chart

(define-component line-chart ((&key label points digits id attributes))
  (:group "Data")
  (:doc "A value over time, such as a share's price over three months: a line with round
ticks that need not start at zero, the last value above it, and a table of every value
under it. POINTS are conses of a universal time and a real; DIGITS fixes the decimals the
values are written with.")
  (:source "shadcn/ui charts (look), drawn as plain SVG by Tun")
  (:css "
.tun-line-chart {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 3);
  width: 100%;
  min-width: 0;
  margin: 0;
  & .tun-line-chart-header {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    justify-content: space-between;
    gap: calc(var(--spacing) * 2);
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
  }
  & .tun-line-chart-last {
    color: var(--foreground);
    font-weight: var(--font-weight-semibold);
    font-variant-numeric: tabular-nums;
  }
  & .tun-line-chart-body {
    display: grid;
    grid-template-columns: auto 1fr;
    grid-template-rows: 12rem auto;
    column-gap: calc(var(--spacing) * 2);
    row-gap: calc(var(--spacing) * 2);
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    font-variant-numeric: tabular-nums;
  }
  /* The tick labels: items of no height, spread from the top to the
     bottom, stand where the evenly spaced gridlines are. */
  & .tun-line-chart-y {
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    align-items: flex-end;
    & > span { display: flex; align-items: center; height: 0; white-space: nowrap; }
  }
  & .tun-line-chart-x {
    grid-column: 2;
    display: flex;
    justify-content: space-between;
    & > span { display: flex; justify-content: center; width: 0; white-space: nowrap; }
    & > span:first-child { justify-content: flex-start; }
    & > span:last-child:not(:first-child) { justify-content: flex-end; }
    & > span:only-child { justify-content: center; margin-inline: auto; }
  }
  & .tun-line-chart-plot {
    position: relative;
    min-width: 0;
    border-radius: var(--radius-sm);
    touch-action: pan-y;
    &:focus-visible { outline: none; box-shadow: var(--focus-ring); }
    & svg {
      position: absolute;
      inset: 0;
      width: 100%;
      height: 100%;
      overflow: visible;
    }
  }
  & .tun-line-chart-gridline { stroke: var(--border); stroke-width: 1px; }
  & .tun-line-chart-stroke {
    fill: none;
    stroke: var(--chart-1);
    stroke-width: 2px;
    stroke-linejoin: round;
    stroke-linecap: round;
    vector-effect: non-scaling-stroke;
  }
  & .tun-line-chart-wash { fill: color-mix(in oklab, var(--chart-1) 10%, transparent); }
  & .tun-line-chart-dot {
    fill: var(--chart-1);
    stroke: var(--card);
    stroke-width: 2px;
  }
  & .tun-line-chart-crosshair {
    position: absolute;
    top: 0;
    bottom: 0;
    width: 1px;
    background-color: var(--muted-foreground);
    pointer-events: none;
  }
  & .tun-line-chart-tooltip {
    position: absolute;
    top: 0;
    z-index: var(--z-dropdown);
    display: flex;
    flex-direction: column;
    padding: calc(var(--spacing) * 1.5) calc(var(--spacing) * 2.5);
    border-radius: var(--radius-md);
    background-color: var(--popover);
    color: var(--muted-foreground);
    box-shadow: 0 0 0 1px var(--border), var(--shadow-md);
    white-space: nowrap;
    pointer-events: none;
    &[hidden] { display: none; }
    & strong { color: var(--popover-foreground); font-weight: var(--font-weight-semibold); }
  }
  & .tun-line-chart-live {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  & .tun-line-chart-empty {
    display: grid;
    place-items: center;
    height: 12rem;
    margin: 0;
    border: 1px dashed var(--border);
    border-radius: var(--radius-md);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
  }
  & .tun-line-chart-table > summary {
    width: fit-content;
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    cursor: pointer;
  }
  & .tun-line-chart-table[open] > summary { margin-block-end: calc(var(--spacing) * 2); }
}")
  (:script "
// Line charts (spec/ui.md 6): a plot [data-tun-chart] holds its points in
// data-tun-chart-points, each [x, y, value, time] with x and y fractions of
// the plot.  A pointer over the plot, or the arrow keys, Home and End when
// it has focus, move the crosshair to the nearest point and show its value;
// Escape, leaving the plot or moving focus away hide them.
const chartPoints = new WeakMap();
const pointsOf = (plot) => {
  if (!chartPoints.has(plot)) chartPoints.set(plot, JSON.parse(plot.dataset.tunChartPoints));
  return chartPoints.get(plot);
};
const nearestPoint = (points, x) => {
  let low = 0, high = points.length - 1;
  while (low < high) {
    const middle = (low + high) >> 1;
    if (points[middle][0] < x) low = middle + 1; else high = middle;
  }
  return low > 0 && x - points[low - 1][0] < points[low][0] - x ? low - 1 : low;
};
const hideCrosshair = (plot) => {
  delete plot.dataset.tunChartAt;
  plot.querySelector('.tun-line-chart-crosshair').hidden = true;
  plot.querySelector('.tun-line-chart-tooltip').hidden = true;
};
const showCrosshair = (plot, index) => {
  const points = pointsOf(plot);
  const [x, y, value, time] = points[index];
  plot.dataset.tunChartAt = index;
  const crosshair = plot.querySelector('.tun-line-chart-crosshair');
  crosshair.style.left = `${x * 100}%`;
  crosshair.hidden = false;
  const tooltip = plot.querySelector('.tun-line-chart-tooltip');
  tooltip.querySelector('strong').textContent = value;
  tooltip.querySelector('span').textContent = time;
  tooltip.hidden = false;
  // Beside the crosshair, on the side with room, and above the point when
  // it is low in the plot.
  const onTheLeft = x > 0.5;
  tooltip.style.left = onTheLeft ? '' : `calc(${x * 100}% + 0.75rem)`;
  tooltip.style.right = onTheLeft ? `calc(${(1 - x) * 100}% + 0.75rem)` : '';
  // 'auto', not '': clearing an inline top brings back the stylesheet's
  // top: 0, and pinned to both edges the tooltip stretches down the plot.
  tooltip.style.top = y > 0.5 ? '0' : 'auto';
  tooltip.style.bottom = y > 0.5 ? 'auto' : '0';
  const live = plot.closest('.tun-line-chart').querySelector('.tun-line-chart-live');
  if (live) live.textContent = `${value}, ${time}`;
};
tunOnContent((root) => {
  for (const plot of root.querySelectorAll('[data-tun-chart]:not([tabindex])')) plot.tabIndex = 0;
});
let pointedPlot = null;
const followPointer = (event) => {
  const plot = event.target.closest?.('[data-tun-chart]');
  if (pointedPlot && pointedPlot !== plot) hideCrosshair(pointedPlot);
  pointedPlot = plot;
  if (!plot) return;
  const box = plot.getBoundingClientRect();
  if (box.width === 0) return;
  showCrosshair(plot, nearestPoint(pointsOf(plot), (event.clientX - box.left) / box.width));
};
document.addEventListener('pointermove', followPointer);
document.addEventListener('pointerdown', followPointer);
document.documentElement.addEventListener('pointerleave', () => {
  if (pointedPlot) hideCrosshair(pointedPlot);
  pointedPlot = null;
});
document.addEventListener('keydown', (event) => {
  // Escape hides a tooltip the pointer showed as well as one the keys did.
  if (event.key === 'Escape') {
    const shown = document.querySelectorAll('[data-tun-chart][data-tun-chart-at]');
    for (const plot of shown) hideCrosshair(plot);
    if (shown.length) event.preventDefault();
    return;
  }
  const plot = event.target.closest?.('[data-tun-chart]');
  if (!plot || event.target !== plot) return;
  const last = pointsOf(plot).length - 1;
  const at = plot.dataset.tunChartAt === undefined ? null : Number(plot.dataset.tunChartAt);
  const index = { ArrowRight: at === null ? 0 : Math.min(last, at + 1),
                  ArrowLeft: at === null ? last : Math.max(0, at - 1),
                  Home: 0, End: last }[event.key];
  if (index !== undefined) {
    showCrosshair(plot, index);
    event.preventDefault();
  }
});
document.addEventListener('focusout', (event) => {
  if (event.target.matches?.('[data-tun-chart]')) hideCrosshair(event.target);
});
")
  (:examples
   (("A share over three months, prices to two decimals" :layout :stack)
    (line-chart (:label "EQNR.OL" :points (specimen-prices 63 86400 412.3d0) :digits 2)))
   (("One trading day, by the hour" :layout :stack)
    (line-chart (:label "AAPL today" :points (specimen-prices 7 3600 228.1d0) :digits 2)))
   (("One point, and no points" :layout :stack)
    (line-chart (:label "Listed today" :points (specimen-prices 1 86400 95d0) :digits 2))
    (line-chart (:label "No trades yet" :points '()))))
  (let ((points (chart-points points)))
    (if (null points)
        `(:figure ,(attrs (list :class "tun-line-chart" :id id) attributes)
                  (:figcaption (:@ :class "tun-line-chart-header") (:span ,label))
                  (:p (:@ :class "tun-line-chart-empty") ,(tr "No data")))
        (multiple-value-bind (ticks step)
            (axis-ticks (reduce #'min points :key #'cdr) (reduce #'max points :key #'cdr))
          (let* ((fractions (point-fractions points ticks))
                 (time-text (point-time-text points))
                 (tick-digits (step-digits step)))
            `(:figure ,(attrs (list :class "tun-line-chart" :id id) attributes)
                      (:figcaption (:@ :class "tun-line-chart-header")
                                   (:span ,label)
                                   (:span (:@ :class "tun-line-chart-last")
                                          ,(value-text (cdr (first (last points))) digits)))
                      (:div (:@ :class "tun-line-chart-body")
                            (:div (:@ :class "tun-line-chart-y" :aria-hidden "true")
                                  ,@(mapcar (lambda (tick)
                                              `(:span ,(number-text tick :digits tick-digits)))
                                            (reverse ticks)))
                            (:div (:@ :class "tun-line-chart-plot" :role "img"
                                      :aria-label ,label :data-tun-chart ""
                                      :data-tun-chart-points
                                      ,(crosshair-points points fractions digits time-text))
                                  ,(stretched-line fractions)
                                  ,(marks fractions (length ticks))
                                  (:div (:@ :class "tun-line-chart-crosshair" :hidden t))
                                  (:div (:@ :class "tun-line-chart-tooltip" :hidden t)
                                        (:strong) (:span)))
                            (:div (:@ :class "tun-line-chart-x" :aria-hidden "true")
                                  ,@(mapcar (lambda (text) `(:span ,text))
                                            (axis-times points))))
                      (:span (:@ :class "tun-line-chart-live" :aria-live "polite"))
                      (:details (:@ :class "tun-line-chart-table")
                                (:summary ,(tr "Show as a table"))
                                ,(table (:caption label :caption-hidden t
                                         :columns (list (tr "Time")
                                                        (list (tr "Value") :align :end))
                                         :rows (mapcar (lambda (point)
                                                         (list (funcall time-text (car point))
                                                               (value-text (cdr point) digits)))
                                                       points))))))))))

;;; ------------------------------------------------------------------
;;; Sparkline

(define-component sparkline ((&key label points digits id attributes))
  (:group "Data")
  (:doc "A value over time in a line of text, such as each share's last three months in a
watchlist's table: a small line with no axes, read out as its first and last value.")
  (:source "shadcn/ui charts (look), drawn as plain SVG by Tun")
  (:css "
.tun-sparkline {
  display: inline-block;
  width: 6rem;
  height: 1lh;
  overflow: visible;
  vertical-align: middle;
  & path {
    fill: none;
    stroke: var(--chart-1);
    stroke-width: 1.5px;
    stroke-linejoin: round;
    stroke-linecap: round;
    vector-effect: non-scaling-stroke;
  }
  /* A single point is a path of no length, whose round cap is a dot. */
  & path[data-dot] { stroke-width: 4px; }
}")
  (:examples
   ("In a table's cell"
    (table (:columns (list "Share" (list "Three months" :align :end)
                           (list "Last" :align :end))
            :rows (list (list "EQNR.OL"
                              (sparkline (:label "EQNR.OL"
                                          :points (specimen-prices 63 86400 412.3d0)
                                          :digits 2))
                              "430.00")
                        (list "Listed today"
                              (sparkline (:label "Listed today"
                                          :points (specimen-prices 1 86400 95d0)))
                              "95")
                        (list "No trades yet"
                              (sparkline (:label "No trades yet" :points '()))
                              ""))))))
  (let* ((points (chart-points points))
         (text (if points
                   (tr "~a: ~a to ~a" label (value-text (cdr (first points)) digits)
                       (value-text (cdr (first (last points))) digits))
                   (format nil "~a: ~a" label (tr "No data")))))
    `(:svg ,(attrs (list :class "tun-sparkline" :id id :role "img" :aria-label text
                         :viewbox (format nil "0 0 ~d ~d" +drawing-size+ +drawing-size+)
                         :preserveaspectratio "none" :focusable "false")
                   attributes)
           ,@(cond ((null points) '())
                   ((null (rest points))
                    `((:path (:@ :data-dot "" :d ,(format nil "M~d,~d l0,0"
                                                          (/ +drawing-size+ 2)
                                                          (/ +drawing-size+ 2))))))
                   (t
                    (let ((values (mapcar #'cdr points)))
                      `((:path (:@ :d ,(line-path
                                         (point-fractions
                                          points (list (reduce #'min values)
                                                       (reduce #'max values)))))))))))))
