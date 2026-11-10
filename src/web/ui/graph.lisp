;;;; web/ui/graph.lisp -- things and what depends on what among them
;;;; (spec/ui.md 6.3): GRAPH draws nodes in layers from left to right, and
;;;; the edges between them as arrows, laid out on the server.
;;;;
;;;; Pages carry no style attribute (spec/ui.md 4), so nothing is placed by
;;;; an inline position.  Every node has one size, a layer is a column of
;;;; places of that size, a node or an empty one, and the SVG of the edges
;;;; lies over the columns with a viewBox in the same CSS pixels.  The sizes
;;;; below write both the CSS and the drawing.  GRAPH-LAYOUT, which decides
;;;; every place, is pure.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +graph-node-limit+ 150
  "The most nodes a graph takes, as every input is bounded.")

(defparameter +graph-edge-limit+ 300
  "The most edges a graph takes.")

(defparameter +graph-badge-limit+ 8
  "The most badges a node takes.")

(defparameter +graph-states+ '(:planned :active :waiting :done :failed :blocked)
  "A node's states (spec/ui.md 6.3); the first is the default.")

(defparameter +graph-tones+ '(:neutral :info :success :warning :destructive)
  "A badge's tones; the first is the default.")

(defparameter +graph-badge-kinds+ '(:agent :ref)
  "A badge's kinds: someone working there now, and a count or a reference.
A badge without a kind is a plain label.")

(defparameter +graph-sweeps+ 4
  "How many times the order within the layers is swept down and up.")

;;; The drawing's sizes, in CSS pixels at 16px to the rem.

(defparameter +graph-node-width+ 224 "A node's width in the drawing, 14rem.")
(defparameter +graph-node-height+ 104 "A node's height, 6.5rem.")
(defparameter +graph-column-gap+ 48 "The space between two layers, 3rem.")
(defparameter +graph-row-gap+ 16 "The space between two places in a layer, 1rem.")
(defparameter +graph-arrow-length+ 8 "How far an arrowhead reaches back along its edge.")
(defparameter +graph-arrow-half-width+ 5 "Half an arrowhead's width at its base.")
(defparameter +graph-back-offset+ 8
  "How far below the middle of its nodes' sides an edge a cycle reversed
runs in the drawing, 0.5rem.")

(defun graph-rem (pixels)
  "PIXELS, at 16px to the rem, as a CSS length in rem."
  (format nil "~frem" (/ pixels 16)))

;;; ------------------------------------------------------------------
;;; The layout (spec/ui.md 6.3)

(defclass graph-layout ()
  ((places :initarg :places :reader layout-places
           :documentation "A hash table from each node's id that has an edge to its
place, (LAYER . ROW).")
   (columns :initarg :columns :reader layout-columns
            :documentation "How many layers there are.")
   (rows :initarg :rows :reader layout-rows
         :documentation "How many rows the tallest layer has.")
   (routes :initarg :routes :reader layout-routes
           :documentation "Each edge as (FROM TO REVERSED PLACES): its ids as given,
whether a cycle reversed it, and the places it passes from its left end to its
right end, the nodes' at both ends and the empty ones between.")
   (loose :initarg :loose :reader layout-loose
          :documentation "The ids of the nodes with no edges, in their order.")
   (order :initarg :order :reader layout-order
          :documentation "The ids of the nodes in the layers, by layer and then row."))
  (:documentation "Where GRAPH-LAYOUT puts a graph's nodes and edges."))

(defun reversed-edges (count successors)
  "The edges (U . V) to reverse so the graph of COUNT nodes, whose
SUCCESSORS vector lists each node's successors in their order, has no
cycle: each edge back to a node a depth-first search through the nodes in
their order is still searching from (spec/ui.md 6.3, 1)."
  (let ((state (make-array count :initial-element :new))
        (reversed '()))
    (labels ((visit (u)
               (setf (aref state u) :open)
               (dolist (v (aref successors u))
                 (case (aref state v)
                   (:new (visit v))
                   (:open (push (cons u v) reversed))))
               (setf (aref state u) :done)))
      (dotimes (u count)
        (when (eq (aref state u) :new)
          (visit u))))
    reversed))

(defun node-layers (count edges)
  "The layer of each of COUNT nodes joined by EDGES, (U . V) with no cycle:
the longest path to it from a node with no edge into it, and such a node
then just before its earliest successor (spec/ui.md 6.3, 2)."
  (let ((layers (make-array count :initial-element 0))
        (predecessors (make-array count :initial-element '()))
        (successors (make-array count :initial-element '()))
        (waiting (make-array count :initial-element 0)))
    (loop for (u . v) in edges
          do (push u (aref predecessors v))
             (push v (aref successors u))
             (incf (aref waiting v)))
    ;; Kahn's order: a node once every node before it has its layer.
    (let ((ready (loop for u below count when (zerop (aref waiting u)) collect u)))
      (loop while ready
            do (let ((u (pop ready)))
                 (dolist (v (aref successors u))
                   (setf (aref layers v) (max (aref layers v) (1+ (aref layers u))))
                   (when (zerop (decf (aref waiting v)))
                     (push v ready))))))
    (dotimes (u count layers)
      (when (and (null (aref predecessors u)) (aref successors u))
        (setf (aref layers u)
              (1- (reduce #'min (aref successors u) :key (lambda (v) (aref layers v)))))))))

(defun barycentre-order (vertices neighbours position)
  "VERTICES, one layer's, ordered by the mean POSITION of their NEIGHBOURS
in the layer beside it; a vertex with none keeps its own position."
  (stable-sort (copy-list vertices) #'<
               :key (lambda (vertex)
                      (let ((others (aref neighbours vertex)))
                        (if others
                            (/ (reduce #'+ others :key (lambda (other) (aref position other)))
                               (length others))
                            (aref position vertex))))))

(defun note-positions (order position)
  "Set POSITION of each vertex to its place in its layer of ORDER."
  (loop for layer across order
        do (loop for vertex in layer
                 for i from 0
                 do (setf (aref position vertex) i))))

(defun crossing-count (order downs position)
  "How many pairs of segments between neighbouring layers of ORDER cross."
  (loop for layer across order
        sum (let ((segments (loop for u in layer
                                  append (mapcar (lambda (v) (cons (aref position u)
                                                                   (aref position v)))
                                                 (aref downs u)))))
              (loop for (a . rest) on segments
                    sum (count-if (lambda (b)
                                    (minusp (* (- (car a) (car b)) (- (cdr a) (cdr b)))))
                                  rest)))))

(defun ordered-layers (order ups downs position)
  "ORDER, a vector of each layer's vertices, swept down by UPS and up by
DOWNS +GRAPH-SWEEPS+ times each way; the order with the fewest crossings,
the earliest of equals (spec/ui.md 6.3, 4)."
  (note-positions order position)
  (let ((best (copy-seq order))
        (fewest (crossing-count order downs position))
        (last-layer (1- (length order))))
    (flet ((keep-if-fewer ()
             (let ((crossings (crossing-count order downs position)))
               (when (< crossings fewest)
                 (setf fewest crossings best (copy-seq order))))))
      (dotimes (sweep +graph-sweeps+)
        (loop for layer from 1 to last-layer
              do (setf (aref order layer) (barycentre-order (aref order layer) ups position))
                 (note-positions order position))
        (keep-if-fewer)
        (loop for layer from (1- last-layer) downto 0
              do (setf (aref order layer) (barycentre-order (aref order layer) downs position))
                 (note-positions order position))
        (keep-if-fewer)))
    (note-positions best position)
    best))

(defun increasing-rows (targets weights)
  "The rows, strictly increasing from 0 down, nearest TARGETS in the least
squares weighted by WEIGHTS: with S the row less its index, which must not
decrease, pool-adjacent-violators gives each run of S its weighted mean."
  (let ((blocks '()))                   ; each (WEIGHT SUM COUNT), the last first
    (loop for target in targets
          for weight in weights
          for i from 0
          do (push (list weight (* weight (- target i)) 1) blocks)
             (loop while (and (rest blocks)
                              (destructuring-bind ((w1 s1 c1) (w0 s0 c0) &rest more) blocks
                                (declare (ignore c1 c0 more))
                                (> (/ s0 w0) (/ s1 w1))))
                   do (destructuring-bind ((w1 s1 c1) (w0 s0 c0) &rest more) blocks
                        (setf blocks (cons (list (+ w0 w1) (+ s0 s1) (+ c0 c1)) more)))))
    (let ((i -1))
      (loop for (weight sum count) in (reverse blocks)
            append (loop repeat count
                         collect (+ (incf i) (max 0 (round sum weight))))))))

(defun dense-rows (rows)
  "ROWS, a vector of rows, with every row no vertex is in taken out: each
row becomes its rank among the rows in use, so the first is 0."
  (let ((used (sort (remove-duplicates (coerce rows 'list)) #'<)))
    (map 'vector (lambda (row) (position row used)) rows)))

(defun vertex-rows (order ups downs count)
  "The row of each of COUNT vertices in ORDER: each layer in turn takes the
rows, strictly increasing down it, nearest the topmost row of its vertices'
neighbours in the layer before, then after, as many times as the order is
swept, and once more down; a vertex with no such neighbour keeps its row as
far as the others let it.  Then the rows no vertex is in are taken out
(spec/ui.md 6.3, 5)."
  (let ((rows (make-array count :initial-element 0)))
    (note-positions order rows)
    (flet ((settle (layer neighbours)
             (let ((targets '()) (weights '()))
               (dolist (vertex layer)
                 (let ((others (aref neighbours vertex)))
                   (push (if others
                             (reduce #'min others :key (lambda (other) (aref rows other)))
                             (aref rows vertex))
                         targets)
                   (push (if others 1 1/100) weights)))
               (loop for vertex in layer
                     for row in (increasing-rows (nreverse targets) (nreverse weights))
                     do (setf (aref rows vertex) row)))))
      (let ((last-layer (1- (length order))))
        (dotimes (sweep +graph-sweeps+)
          (loop for layer from 1 to last-layer do (settle (aref order layer) ups))
          (loop for layer from (1- last-layer) downto 0 do (settle (aref order layer) downs)))
        (loop for layer from 1 to last-layer do (settle (aref order layer) ups))))
    (dense-rows rows)))

(defun edge-chain (edge reversed layer-of trunks)
  "The vertices EDGE, (LEFT . RIGHT), passes from left to right: LEFT, a
vertex in each layer between, and RIGHT (spec/ui.md 6.3, 3).  The edges
with one LEFT share their vertex in a layer, those a cycle REVERSED apart
from the others, so a dashed edge never shares a solid one's line.  TRUNKS
keeps them; a new one is added to LAYER-OF."
  (destructuring-bind (left . right) edge
    (append (list left)
            (loop for layer from (1+ (aref layer-of left)) below (aref layer-of right)
                  collect (let ((key (list left reversed layer)))
                            (or (gethash key trunks)
                                (setf (gethash key trunks)
                                      (vector-push-extend layer layer-of)))))
            (list right))))

(defun vertex-places (layer-of chains)
  "The row of each vertex in LAYER-OF, whose edges are CHAINS, once each
layer is ordered; the second value is how many layers there are."
  (let* ((total (length layer-of))
         (columns (if (zerop total) 0 (1+ (reduce #'max layer-of))))
         (order (make-array columns :initial-element '()))
         (ups (make-array total :initial-element '()))
         (downs (make-array total :initial-element '())))
    (loop for vertex from (1- total) downto 0
          do (push vertex (aref order (aref layer-of vertex))))
    (dolist (chain (reverse chains))
      (loop for (u v) on chain while v
            do (pushnew u (aref ups v))
               (pushnew v (aref downs u))))
    (values (vertex-rows (ordered-layers order ups downs (make-array total :initial-element 0))
                         ups downs total)
            columns)))

(defun place-before-p (a b)
  "Whether the place A, (LAYER . ROW), comes before B: by layer, then row."
  (or (< (car a) (car b))
      (and (= (car a) (car b)) (< (cdr a) (cdr b)))))

(defun graph-layout (ids edges)
  "Lay out the nodes IDS, strings in their order, joined by EDGES, conses
(FROM . TO) of those ids, distinct and none from a node to itself, in layers
from left to right (spec/ui.md 6.3).  Returns a GRAPH-LAYOUT."
  (let* ((index (make-hash-table :test #'equal))
         (linked (remove-if-not (lambda (id)
                                  (find-if (lambda (edge) (or (equal id (car edge))
                                                              (equal id (cdr edge))))
                                           edges))
                                ids))
         (count (length linked)))
    (loop for id in linked for i from 0 do (setf (gethash id index) i))
    (let* ((pairs (mapcar (lambda (edge)
                            (cons (gethash (car edge) index) (gethash (cdr edge) index)))
                          edges))
           (successors (make-array count :initial-element '())))
      (dolist (pair (reverse pairs))
        (push (cdr pair) (aref successors (car pair))))
      (let* ((reversed (reversed-edges count successors))
             (oriented (mapcar (lambda (pair)
                                 (if (member pair reversed :test #'equal)
                                     (cons (cdr pair) (car pair))
                                     pair))
                               pairs))
             (layer-of (make-array count :adjustable t :fill-pointer t
                                         :initial-contents (node-layers count oriented)))
             (trunks (make-hash-table :test #'equal))
             (reversed-p (lambda (pair) (and (member pair reversed :test #'equal) t)))
             (chains (mapcar (lambda (edge pair)
                               (edge-chain edge (funcall reversed-p pair) layer-of trunks))
                             oriented pairs)))
        (multiple-value-bind (rows columns) (vertex-places layer-of chains)
          (let ((places (make-hash-table :test #'equal)))
            (flet ((place (vertex) (cons (aref layer-of vertex) (aref rows vertex))))
              (loop for id in linked for i from 0 do (setf (gethash id places) (place i)))
              (make-instance 'graph-layout
                             :places places
                             :columns columns
                             :rows (if (zerop (length rows)) 0 (1+ (reduce #'max rows)))
                             :routes (loop for (from . to) in edges
                                           for pair in pairs
                                           for chain in chains
                                           collect (list from to (funcall reversed-p pair)
                                                         (mapcar #'place chain)))
                             :loose (remove-if (lambda (id) (gethash id index)) ids)
                             :order (stable-sort (copy-list linked) #'place-before-p
                                                 :key (lambda (id) (gethash id places)))))))))))

;;; ------------------------------------------------------------------
;;; What a caller gives

(defun check-graph-badge (badge)
  "BADGE, (:text T [:kind K] [:tone TONE] [:href H]), checked."
  (destructuring-bind (&key text kind tone href) badge
    (declare (ignore href))
    (unless (stringp text)
      (error "A graph's badge has a :text, a string, not ~s" text))
    (unless (or (null kind) (member kind +graph-badge-kinds+))
      (error "A graph's badge has a :kind of ~{~s~^, ~}, not ~s" +graph-badge-kinds+ kind))
    (unless (or (null tone) (member tone +graph-tones+))
      (error "A graph's badge has a :tone of ~{~s~^, ~}, not ~s" +graph-tones+ tone))))

(defun check-graph-node (node)
  "NODE, (:id :title [:meta] [:state] [:href] [:badges]), checked."
  (destructuring-bind (&key id title meta state href badges) node
    (declare (ignore href))
    (unless (and (stringp id) (stringp title))
      (error "A graph's node has an :id and a :title, strings: ~s" node))
    (unless (or (null meta) (stringp meta))
      (error "A graph's node has a :meta that is a string, not ~s" meta))
    (unless (or (null state) (member state +graph-states+))
      (error "A graph's node has a :state of ~{~s~^, ~}, not ~s" +graph-states+ state))
    (unless (and (listp badges) (<= (length badges) +graph-badge-limit+))
      (error "A graph's node takes at most ~d badges in a list: ~s" +graph-badge-limit+ badges))
    (mapc #'check-graph-badge badges)))

(defun graph-edges (nodes edges)
  "EDGES, (:from A :to B) each, as conses (A . B) of ids of NODES: checked,
in their order, a repeated one and one from a node to itself left out."
  (let ((ids (make-hash-table :test #'equal))
        (pairs '()))
    (dolist (node nodes)
      (setf (gethash (getf node :id) ids) t))
    (dolist (edge edges (nreverse pairs))
      (destructuring-bind (&key from to) edge
        (unless (and (gethash from ids) (gethash to ids))
          (error "A graph's edge goes :from a node :to a node of the graph: ~s" edge))
        (unless (or (equal from to) (member (cons from to) pairs :test #'equal))
          (push (cons from to) pairs))))))

(defun check-graph (nodes edges)
  "Signal an error in the caller's code unless NODES and EDGES are a graph
GRAPH takes (spec/ui.md 6.3)."
  (unless (and (listp nodes) (<= (length nodes) +graph-node-limit+))
    (error "A graph takes at most ~d nodes in a list, not ~s" +graph-node-limit+
           (if (listp nodes) (length nodes) nodes)))
  (unless (and (listp edges) (<= (length edges) +graph-edge-limit+))
    (error "A graph takes at most ~d edges in a list, not ~s" +graph-edge-limit+
           (if (listp edges) (length edges) edges)))
  (mapc #'check-graph-node nodes)
  (let ((ids (mapcar (lambda (node) (getf node :id)) nodes)))
    (unless (= (length ids) (length (remove-duplicates ids :test #'equal)))
      (error "A graph's nodes each have an id of their own: ~s" ids))))

;;; ------------------------------------------------------------------
;;; The nodes

(defun graph-state-text (state)
  "The word for a node's STATE, in the page's language."
  (ecase state
    (:planned (tr "Planned"))
    (:active (tr "Active"))
    (:waiting (tr "Waiting"))
    (:done (tr "Done"))
    (:failed (tr "Failed"))
    (:blocked (tr "Blocked"))))

(defun graph-badge-markup (badge)
  "BADGE as a `badge', in a link when it has one."
  (destructuring-bind (&key text kind tone href) badge
    (let* ((tone (or tone (if (eq kind :agent) :info :neutral)))
           (shown `(:span (:@ :class "tun-graph-badge-text") ,text))
           (markup (apply #'badge*
                          (list :variant (if (eq tone :neutral) :outline tone)
                                :attributes (list :data-kind (option-string kind) :title text))
                          (if (eq kind :agent)
                              (list '(:span (:@ :class "tun-graph-live" :aria-hidden "true"))
                                    shown
                                    `(:span (:@ :class "tun-graph-hidden")
                                            ,(format nil ", ~a" (tr "working now"))))
                              (list shown)))))
      (if href
          `(:a (:@ :class "tun-graph-badge-link" :href ,href) ,markup)
          markup))))

(defun graph-badges (badges)
  (mapcar #'graph-badge-markup badges))

;;; A node shows the badges that fit the narrowest node's line, reckoned on
;;; the server, since CSS cannot count what wrapped out of sight (spec/ui.md
;;; 6.3, «The badges a node shows»).  Widths are in rem.

(defparameter +graph-badge-room+ 41/4
  "The width of the badge line of the narrowest node, a list's at 12rem,
less its padding and stripe.")

(defun badge-reckoned-width (text &optional agent)
  "The width a badge of TEXT is reckoned to take: its padding and border,
0.45rem a character, and an agent's dot."
  (+ 11/10 (* 9/20 (length text)) (if agent 3/5 0)))

(defun more-text (count)
  (format nil "+~d" count))

(defun shown-badge-count (badges)
  "How many of BADGES, from the first, a node shows: the first always, then
each in turn while it fits the line and leaves room for the «+N» of those
still left after it."
  (let ((used (badge-reckoned-width (getf (first badges) :text)
                                    (eq :agent (getf (first badges) :kind))))
        (count (length badges)))
    (loop for shown from 1 below count
          for badge in (rest badges)
          for width = (+ used 1/4 (badge-reckoned-width (getf badge :text)
                                                        (eq :agent (getf badge :kind))))
          for left = (- count shown 1)
          while (<= (+ width (if (plusp left)
                                 (+ 1/4 (badge-reckoned-width (more-text left)))
                                 0))
                    +graph-badge-room+)
          do (setf used width)
          finally (return shown))))

(defun node-badges (badges)
  "The badge line of a node: the BADGES that fit, and «+N» for the rest,
whose title, and a screen reader, name them."
  (when badges
    (let* ((shown (shown-badge-count badges))
           (left (nthcdr shown badges))
           (names (tr "~d more: ~{~a~^, ~}" (length left)
                      (mapcar (lambda (badge) (getf badge :text)) left))))
      (append (graph-badges (subseq badges 0 shown))
              (when left
                (list (badge* (list :variant :outline
                                    :attributes (list :data-kind "more" :title names))
                              `(:span (:@ :aria-hidden "true") ,(more-text (length left)))
                              `(:span (:@ :class "tun-graph-hidden") ,names))))))))

(defun graph-node-markup (node)
  "NODE as the box the drawing shows."
  (destructuring-bind (&key id title meta state href badges) node
    (let ((state (or state :planned)))
      `(:div (:@ :class "tun-graph-node" :data-node ,id :data-state ,(option-string state)
                 :title ,title
                 :data-live ,(and (find :agent badges :key (lambda (badge) (getf badge :kind)))
                                  ""))
             (:span (:@ :class "tun-graph-title")
                    ,(if href `(:a (:@ :class "tun-graph-link" :href ,href) ,title) title))
             (:span (:@ :class "tun-graph-line")
                    (:span (:@ :class "tun-graph-state") ,(graph-state-text state))
                    ,@(when meta `((:span (:@ :class "tun-graph-meta" :title ,meta) ,meta))))
             (:span (:@ :class "tun-graph-badges") ,@(node-badges badges))))))

;;; ------------------------------------------------------------------
;;; The drawing

(defun place-left (place)
  "The x of the left side of the nodes in PLACE's layer."
  (* (car place) (+ +graph-node-width+ +graph-column-gap+)))

(defun place-right (place)
  (+ (place-left place) +graph-node-width+))

(defun place-middle (place)
  "The y of the middle of a node at PLACE's row."
  (+ (* (cdr place) (+ +graph-node-height+ +graph-row-gap+)) (/ +graph-node-height+ 2)))

(defun edge-y (place reversed)
  "The y an edge meets the node or empty place at PLACE: the middle, or
+GRAPH-BACK-OFFSET+ below it for an edge a cycle REVERSED, so that edge and
one forward between the same nodes are two lines."
  (+ (place-middle place) (if reversed +graph-back-offset+ 0)))

(defun route-points (places reversed)
  "The points (X . Y) an edge through PLACES, from left to right, is drawn
along, from its source to where its arrowhead starts: from the right side of
the first to the left side of the last, or back from the last when the edge
was REVERSED."
  (flet ((point (x place) (cons x (edge-y place reversed))))
    (let ((points (append (list (point (place-right (first places)) (first places)))
                          (loop for place in (butlast (rest places))
                                collect (point (place-left place) place)
                                collect (point (place-right place) place))
                          (let ((last (first (last places))))
                            (list (point (place-left last) last))))))
      (if reversed
          (progn (incf (car (first points)) +graph-arrow-length+)
                 (reverse points))
          (progn (decf (car (first (last points))) +graph-arrow-length+)
                 points)))))

(defun route-path (points)
  "The SVG path along POINTS: straight where two are on one row, else a
curve leaving and arriving level."
  (format nil "M~{~a~^ ~}"
          (cons (format nil "~d,~d" (car (first points)) (cdr (first points)))
                (loop for (from to) on points while to
                      collect (if (= (cdr from) (cdr to))
                                  (format nil "L~d,~d" (car to) (cdr to))
                                  (let ((middle (/ (+ (car from) (car to)) 2)))
                                    (format nil "C~d,~d ~d,~d ~d,~d" middle (cdr from)
                                            middle (cdr to) (car to) (cdr to))))))))

(defun arrowhead (places reversed)
  "The polygon of an edge's arrowhead, its tip on its target's side: the
left of the last of PLACES, or the right of the first when REVERSED."
  (let* ((target (if reversed (first places) (first (last places))))
         (tip (if reversed (place-right target) (place-left target)))
         (base (if reversed (+ tip +graph-arrow-length+) (- tip +graph-arrow-length+)))
         (y (edge-y target reversed)))
    (format nil "~d,~d ~d,~d ~d,~d" tip y base (- y +graph-arrow-half-width+)
            base (+ y +graph-arrow-half-width+))))

(defun graph-size (layout)
  "The width and height of LAYOUT's drawing, in CSS pixels."
  (let ((columns (layout-columns layout)) (rows (layout-rows layout)))
    (values (- (* columns (+ +graph-node-width+ +graph-column-gap+)) +graph-column-gap+)
            (- (* rows (+ +graph-node-height+ +graph-row-gap+)) +graph-row-gap+))))

(defun graph-edges-markup (layout)
  "The SVG of LAYOUT's edges."
  (multiple-value-bind (width height) (graph-size layout)
    `(:svg (:@ :class "tun-graph-edges" :viewbox ,(format nil "0 0 ~d ~d" width height)
               :aria-hidden "true" :focusable "false")
           ,@(loop for (from to reversed places) in (layout-routes layout)
                   collect `(:g (:@ :class "tun-graph-edge" :data-from ,from :data-to ,to
                                    :data-back ,(and reversed ""))
                                (:path (:@ :d ,(route-path (route-points places reversed))))
                                (:polygon (:@ :points ,(arrowhead places reversed))))))))

(defun graph-columns (layout nodes)
  "Each layer of LAYOUT as a column of places, the boxes of NODES and the
empty places as far down as a node or an edge reaches in it."
  (let ((columns (make-array (layout-columns layout) :initial-element '()))
        (heights (make-array (layout-columns layout) :initial-element 0)))
    (flet ((reach (place)
             (setf (aref heights (car place)) (max (aref heights (car place)) (1+ (cdr place))))))
      (dolist (route (layout-routes layout))
        (mapc #'reach (fourth route)))
      (loop for node in nodes
            for place = (gethash (getf node :id) (layout-places layout))
            when place
              do (reach place)
                 (push (cons (cdr place) node) (aref columns (car place)))))
    (loop for layer below (layout-columns layout)
          collect `(:div (:@ :class "tun-graph-layer")
                         ,@(loop for row below (aref heights layer)
                                 for node = (cdr (assoc row (aref columns layer)))
                                 collect (if node
                                             (graph-node-markup node)
                                             '(:div (:@ :class "tun-graph-gap"
                                                        :aria-hidden "true"))))))))

(defun graph-table (label nodes edges layout)
  "Every node as a row of a table: its title, its state, what it depends on
and its badges, in the order of the layers, then the nodes with no edges."
  (let ((by-id (make-hash-table :test #'equal)))
    (dolist (node nodes)
      (setf (gethash (getf node :id) by-id) node))
    (table (:caption label :caption-hidden t
            :columns (list (tr "Name") (tr "State") (tr "Depends on") (tr "Details"))
            :rows (loop for id in (append (layout-order layout) (layout-loose layout))
                        for node = (gethash id by-id)
                        collect (destructuring-bind (&key title state href badges
                                                     &allow-other-keys)
                                    node
                                  (list (if href `(:a (:@ :href ,href) ,title) title)
                                        (graph-state-text (or state :planned))
                                        (format nil "~{~a~^, ~}"
                                                (loop for (from . to) in edges
                                                      when (equal to id)
                                                        collect (getf (gethash from by-id)
                                                                      :title)))
                                        `(:span (:@ :class "tun-graph-badges-cell")
                                                ,@(graph-badges badges)))))))))

;;; ------------------------------------------------------------------
;;; The list (spec/ui.md 6.3, «The list»): the nodes in one column, in the
;;; order of the layers, and the edges as rails in a gutter left of them.
;;; Sizes are CSS pixels at 16px to the rem, as in the drawing.

(defparameter +graph-list-gap+ 8 "The space between two nodes of the list, 0.5rem.")
(defparameter +graph-lane-width+ 6 "The space between two lanes of the gutter.")
(defparameter +graph-gutter-margin+ 12
  "The space between the nearest lane and the nodes, where arrowheads stand.")
(defparameter +graph-list-arrow-length+ 6 "An arrowhead's length in the list.")
(defparameter +graph-list-arrow-half-width+ 4 "Half its width at its base.")

(defun list-top (row)
  (* row (+ +graph-node-height+ +graph-list-gap+)))

(defun list-upper (row)
  "The y where edges come into the node at ROW: the upper part of its side."
  (+ (list-top row) (round +graph-node-height+ 3)))

(defun list-lower (row)
  "The y where edges leave the node at ROW: the lower part of its side."
  (- (+ (list-top row) +graph-node-height+) (round +graph-node-height+ 3)))

(defun graph-rails (layout)
  "LAYOUT's edges as rails, each (NODE REVERSED OTHERS): a NODE's edges to
the nodes below it, or, REVERSED, those a cycle reversed from the nodes
below it into it; OTHERS are those nodes' ids, in the edges' order."
  (let ((rails '()))
    (loop for (from to reversed) in (layout-routes layout)
          for top = (if reversed to from)
          for other = (if reversed from to)
          for rail = (find-if (lambda (rail) (and (equal (first rail) top)
                                                  (eq (second rail) reversed)))
                              rails)
          do (if rail
                 (setf (third rail) (append (third rail) (list other)))
                 (push (list top reversed (list other)) rails)))
    (nreverse rails)))

(defun rail-extent (rail row-of)
  "The ys, (TOP . BOTTOM), RAIL's vertical line runs between: from where it
meets the node at its top to where it meets the lowest node it joins."
  (destructuring-bind (top reversed others) rail
    (let ((last-row (reduce #'max others :key row-of)))
      (if reversed
          (cons (list-upper (funcall row-of top)) (list-lower last-row))
          (cons (list-lower (funcall row-of top)) (list-upper last-row))))))

(defun rail-lanes (spans)
  "The lane of each of SPANS, (TOP . BOTTOM) ys: from the shortest, each
takes the lane nearest the nodes, 0, that no span meeting it holds
(spec/ui.md 6.3)."
  (let ((lanes (make-array (length spans) :initial-element nil))
        (by-length (stable-sort (loop for span in spans for i from 0 collect (cons i span))
                                #'< :key (lambda (entry) (- (cddr entry) (cadr entry))))))
    (loop for (i first . last) in by-length
          do (setf (aref lanes i)
                   (loop for lane from 0
                         unless (loop for j below (length spans)
                                      for other = (nth j spans)
                                        thereis (and (eql (aref lanes j) lane)
                                                     (<= (car other) last)
                                                     (<= first (cdr other))))
                           return lane)))
    (coerce lanes 'list)))

(defun rail-markup (rail lane gutter row-of)
  "The SVG of RAIL in LANE of a gutter GUTTER wide, ROW-OF giving each
node's row in the list: its line down the lane, a line from each node at
its tail to the lane, and a line from the lane to each node at its head,
ending in an arrowhead; a dot on the lane where each line meets it."
  (destructuring-bind (top reversed others) rail
    (let* ((x (- gutter +graph-gutter-margin+ (* lane +graph-lane-width+)))
           (base (- gutter +graph-list-arrow-length+))
           (extent (rail-extent rail row-of))
           (heads (if reversed (list top) others))
           (tails (if reversed others (list top))))
      (labels ((y-of (id)
                 (if (member id heads :test #'equal)
                     (list-upper (funcall row-of id))
                     (list-lower (funcall row-of id))))
               (line (from-x to-x id)
                 (format nil "M~d,~d L~d,~d" from-x (y-of id) to-x (y-of id)))
               (dot (id)
                 `(:circle (:@ :data-node ,id :cx ,(princ-to-string x)
                               :cy ,(princ-to-string (y-of id)) :r "2.5")))
               (arrowhead (id)
                 (let ((y (y-of id)) (half +graph-list-arrow-half-width+))
                   `(:polygon (:@ :data-node ,id
                                  :points ,(format nil "~d,~d ~d,~d ~d,~d" gutter y
                                                   base (- y half) base (+ y half)))))))
        `(:g (:@ :class "tun-graph-rail" :data-node ,top :data-back ,(and reversed ""))
             (:path (:@ :d ,(format nil "M~d,~d L~d,~d~{ ~a~}" x (car extent) x (cdr extent)
                                    (append (mapcar (lambda (id) (line gutter x id)) tails)
                                            (mapcar (lambda (id) (line x base id)) heads)))))
             ,@(mapcar #'dot (append tails heads))
             ,@(mapcar #'arrowhead heads))))))

(defun graph-list (layout nodes)
  "The list of LAYOUT's NODES: the gutter of rails and the nodes' column."
  (let* ((order (layout-order layout))
         (rows (make-hash-table :test #'equal))
         (by-id (make-hash-table :test #'equal)))
    (loop for id in order for row from 0 do (setf (gethash id rows) row))
    (dolist (node nodes) (setf (gethash (getf node :id) by-id) node))
    (flet ((row-of (id) (gethash id rows)))
      (let* ((rails (graph-rails layout))
             (spans (mapcar (lambda (rail) (rail-extent rail #'row-of)) rails))
             (lanes (rail-lanes spans))
             (gutter (+ +graph-gutter-margin+ (* (1+ (reduce #'max lanes :initial-value 0))
                                                 +graph-lane-width+)))
             (height (- (list-top (length order)) +graph-list-gap+)))
        `(:div (:@ :class "tun-graph-list")
               (:svg (:@ :class "tun-graph-rails" :width ,(princ-to-string gutter)
                         :viewbox ,(format nil "0 0 ~d ~d" gutter height)
                         :preserveaspectratio "none" :aria-hidden "true" :focusable "false")
                     ,@(loop for rail in rails
                             for lane in lanes
                             collect (rail-markup rail lane gutter #'row-of)))
               (:div (:@ :class "tun-graph-list-nodes")
                     ,@(mapcar (lambda (id) (graph-node-markup (gethash id by-id))) order)))))))

;;; ------------------------------------------------------------------
;;; Graph

(define-component graph ((&key label nodes edges id attributes))
  (:group "Data")
  (:doc "Things and what depends on what among them, such as a project's steps with where
agents work and the items tied to each, or modules and what each requires: nodes in layers
from left to right, laid out on the server, each with its state, a link and badges, and an
arrow for each edge (:from A :to B), B depending on A. In a box narrower than 40rem, such as
a phone's, it is a list of the nodes with the edges as rails beside it. A table under it holds
the same.")
  (:source "Tun, in the look of shadcn/ui's cards and badges; a layered (Sugiyama) layout")
  (:css (format nil "
.tun-graph {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 3);
  width: 100%;
  min-width: 0;
  margin: 0;
  container-type: inline-size;
  & > figcaption {
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
  }
  /* The drawing scrolls in its own box; the padding keeps a ring or a
     focus outline inside it. */
  & .tun-graph-scroll {
    display: none;
    max-width: 100%;
    overflow-x: auto;
    padding: calc(var(--spacing) * 1.5);
  }
  /* The list: the gutter of rails beside a column of nodes 12rem to 40rem
     wide; below 12rem the list scrolls in its own box. */
  & .tun-graph-list {
    display: grid;
    grid-template-columns: auto minmax(12rem, 40rem);
    justify-content: start;
    max-width: 100%;
    overflow-x: auto;
    padding-block: calc(var(--spacing) * 1.5);
    padding-inline-end: calc(var(--spacing) * 1.5);
  }
  & .tun-graph-rails {
    height: 100%;
    overflow: visible;
    & path {
      fill: none;
      stroke: var(--muted-foreground);
      stroke-width: 1.5px;
      vector-effect: non-scaling-stroke;
    }
    & :is(circle, polygon) { fill: var(--muted-foreground); }
    & [data-back] path { stroke-dasharray: 4 3; }
  }
  & .tun-graph-list-nodes {
    display: flex;
    flex-direction: column;
    gap: ~a;
    min-width: 0;
    & .tun-graph-node { width: auto; }
  }
  /* The columns' sizes are those the edges are drawn to (+GRAPH-NODE-WIDTH+
     and the others), so they are written from the same numbers. */
  & .tun-graph-canvas {
    position: relative;
    display: flex;
    align-items: flex-start;
    gap: ~a;
    width: max-content;
  }
  & .tun-graph-edges {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
    pointer-events: none;
    & path {
      fill: none;
      stroke: var(--muted-foreground);
      stroke-width: 1.5px;
      vector-effect: non-scaling-stroke;
    }
    & polygon { fill: var(--muted-foreground); }
    & [data-back] path { stroke-dasharray: 4 3; }
  }
  & .tun-graph-layer {
    display: flex;
    flex: none;
    flex-direction: column;
    gap: ~a;
    width: ~a;
  }
  & .tun-graph-gap { flex: none; height: ~a; }
  & .tun-graph-loose {
    display: flex;
    flex-wrap: wrap;
    gap: ~a;
  }
  & .tun-graph-node {
    --tun-graph-tone: var(--muted-foreground);
    position: relative;
    box-sizing: border-box;
    display: flex;
    flex: none;
    flex-direction: column;
    justify-content: flex-start;
    gap: var(--spacing);
    width: ~a;
    height: ~a;
    padding: calc(var(--spacing) * 2) calc(var(--spacing) * 3);
    border: 1px solid var(--border);
    border-inline-start: 3px solid var(--tun-graph-tone);
    border-radius: var(--radius-md);
    background-color: var(--card);
    color: var(--card-foreground);
    box-shadow: var(--shadow-xs);
    &[data-state='active'] { --tun-graph-tone: var(--info); }
    &[data-state='done'] { --tun-graph-tone: var(--success); }
    &[data-state='waiting'] {
      --tun-graph-tone: var(--warning);
      background-color: var(--warning-soft);
    }
    &:is([data-state='failed'], [data-state='blocked']) {
      --tun-graph-tone: var(--destructive);
      background-color: var(--destructive-soft);
    }
    /* On a tinted box the second line takes the full text colour, for
       contrast. */
    &:is([data-state='waiting'], [data-state='failed'], [data-state='blocked'])
      .tun-graph-line { color: var(--foreground); }
    &[data-live] { box-shadow: 0 0 0 2px var(--info), var(--shadow-sm); }
    &:has(.tun-graph-link:focus-visible) { outline: 2px solid var(--ring); outline-offset: 2px; }
    & a:not(.tun-graph-link) { position: relative; z-index: 1; }
  }
  /* Up to two lines of title, cut with an ellipsis after the second. */
  & .tun-graph-title {
    display: -webkit-box;
    flex: none;
    overflow: hidden;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    overflow-wrap: anywhere;
  }
  /* The title's link covers the box, as a card's does. */
  & .tun-graph-link {
    color: inherit;
    text-decoration: none;
    outline: none;
    &::after { content: ''; position: absolute; inset: 0; }
  }
  & .tun-graph-line {
    display: flex;
    align-items: center;
    gap: var(--spacing);
    min-width: 0;
    overflow: hidden;
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    white-space: nowrap;
  }
  & .tun-graph-state {
    display: inline-flex;
    flex: none;
    align-items: center;
    gap: calc(var(--spacing) * 1.5);
    &::before {
      content: '';
      width: calc(var(--spacing) * 2);
      height: calc(var(--spacing) * 2);
      border-radius: var(--radius-full);
      background-color: var(--tun-graph-tone);
    }
  }
  & .tun-graph-meta {
    overflow: hidden;
    text-overflow: ellipsis;
    &::before { content: '·'; margin-inline-end: var(--spacing); }
  }
  /* One line of badges: those that wrap to a second are out of sight
     whole, and a badge alone wider than the line ends in an ellipsis.
     Clipped, not hidden, so focus on a hidden badge's link cannot scroll
     the line half into view. */
  & .tun-graph-badges {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing);
    height: calc(var(--spacing) * 5);
    overflow: clip;
    & > .tun-graph-badge-link { min-width: 0; max-width: 100%; }
    & .tun-badge { flex-shrink: 1; min-width: 0; max-width: 100%; }
  }
  & .tun-graph-badge-text {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  & .tun-graph-badges-cell { display: flex; flex-wrap: wrap; gap: var(--spacing); }
  & .tun-graph-badge-link {
    display: inline-flex;
    border-radius: var(--radius-full);
    text-decoration: none;
    &:focus-visible { outline: 2px solid var(--ring); outline-offset: 1px; }
  }
  & .tun-badge[data-kind='ref'] { font-variant-numeric: tabular-nums; }
  /* Someone working there now.  The pulse is slow enough to read as a
     light, not an alarm, and stops when motion is reduced. */
  & .tun-graph-live {
    flex: none;
    width: calc(var(--spacing) * 1.5);
    height: calc(var(--spacing) * 1.5);
    border-radius: var(--radius-full);
    background-color: currentColor;
    animation: tun-graph-pulse 1.6s var(--ease) infinite;
  }
  & .tun-graph-hidden {~a
  }
  & .tun-graph-empty {
    display: grid;
    place-items: center;
    height: 8rem;
    margin: 0;
    border: 1px dashed var(--border);
    border-radius: var(--radius-md);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
  }
  & .tun-graph-table > summary {
    width: fit-content;
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    cursor: pointer;
  }
  & .tun-graph-table[open] > summary { margin-block-end: calc(var(--spacing) * 2); }
  /* The figure's own width chooses the form: the list in a narrow box,
     the drawing from 40rem (spec/ui.md 6.3, «Two forms»).  Last, so it
     overrides the forms' own display. */
  @container (min-width: 40rem) {
    & .tun-graph-scroll { display: block; }
    & .tun-graph-list { display: none; }
  }
}
@keyframes tun-graph-pulse {
  50% { opacity: 0.35; }
}"
                (graph-rem +graph-list-gap+)
                (graph-rem +graph-column-gap+) (graph-rem +graph-row-gap+)
                (graph-rem +graph-node-width+) (graph-rem +graph-node-height+)
                (graph-rem +graph-row-gap+)
                (graph-rem +graph-node-width+) (graph-rem +graph-node-height+)
                +visually-hidden-css+))
  (:examples
   (("A project's work, with an agent and its items" :layout :stack)
    (graph (:label "Event rental"
            :nodes (list (list :id "brief" :title "Brief and estimate" :meta "8 Nov"
                               :state :done :href "/ui/graph")
                         (list :id "model" :title "Bookings and stock" :state :done)
                         (list :id "calendar" :title "Booking calendar" :meta "Factory 3"
                               :state :active :href "/ui/graph"
                               :badges (list (list :text "Claude i tun" :kind :agent)
                                             (list :text "#12" :kind :ref :href "/ui/graph")))
                         (list :id "payments" :title "Card payments" :state :waiting
                               :badges (list (list :text "1 question" :kind :ref
                                                   :tone :warning)))
                         (list :id "mail" :title "Order confirmations by mail")
                         (list :id "staging" :title "Deploy to staging" :state :blocked
                               :badges (list (list :text "#14" :kind :ref :tone :destructive)))
                         (list :id "launch" :title "Launch on moatless.store"))
            :edges (list (list :from "brief" :to "model") (list :from "model" :to "calendar")
                         (list :from "model" :to "payments")
                         (list :from "calendar" :to "staging")
                         (list :from "payments" :to "staging") (list :from "mail" :to "staging")
                         (list :from "staging" :to "launch")))))
   (("Tun's modules and what each requires" :layout :stack)
    (graph (:label "Modules"
            :nodes (mapcar (lambda (module) (list :id module :title module :meta "module"))
                           '("catalog" "customers" "reviews" "dashboard" "inventory" "orders"
                             "staffing" "invoicing" "calendar" "warehouse" "notifications"
                             "inbox" "messaging"))
            :edges (mapcar (lambda (pair) (list :from (first pair) :to (second pair)))
                           '(("catalog" "inventory") ("customers" "orders") ("catalog" "orders")
                             ("inventory" "orders") ("reviews" "orders") ("orders" "staffing")
                             ("orders" "invoicing") ("orders" "calendar") ("staffing" "calendar")
                             ("staffing" "warehouse") ("customers" "notifications")
                             ("orders" "notifications") ("staffing" "notifications")
                             ("customers" "inbox") ("orders" "inbox") ("notifications" "inbox")
                             ("orders" "messaging") ("customers" "messaging")
                             ("notifications" "messaging") ("inbox" "messaging"))))))
   (("A plan of 30 components, the shape of a real one" :layout :stack)
    (graph (:label "Plan"
            :nodes (mapcar (lambda (component)
                             (destructuring-bind (id title state &rest badges) component
                               (list :id id :title title :state state :meta "Module"
                                     :badges badges)))
                           '(("layout" "Module layout and build path" :done)
                             ("update" "Updating customers in Tun" :done)
                             ("company" "Company profile and settings" :done)
                             ("pricing" "Prices, discounts and VAT rules" :done)
                             ("customers" "Customers and their contacts" :done)
                             ("catalogue" "Product and rental catalogue" :done)
                             ("staff" "Staff, roles and working hours" :active
                              (:text "Builder 1" :kind :agent))
                             ("messages" "Messages to customers by mail and SMS" :done)
                             ("accounting" "Port to the accounting system" :waiting
                              (:text "1 question" :kind :ref :tone :warning)
                              (:text "Planner" :kind :agent) (:text "#40" :kind :ref))
                             ("orders" "Orders from quote to delivery" :active
                              (:text "Builder 2" :kind :agent) (:text "#41" :kind :ref))
                             ("lifecycle" "Order states and their transitions" :active)
                             ("stock" "Stock ledger per warehouse" :done)
                             ("quotes" "Quotes the customer can accept online" :planned)
                             ("timers" "Reminders on quotes about to expire" :planned)
                             ("inquiries" "Inquiries from the website form" :failed)
                             ("reservations" "Stock reserved for confirmed orders" :planned)
                             ("work-orders" "Work orders for the field crew" :planned)
                             ("calendar" "Crew calendar by week and day" :planned)
                             ("invoices" "Invoices from delivered orders" :blocked)
                             ("invoice-status" "Invoice status from the accounting system"
                              :planned)
                             ("work-time" "Hours worked against work orders" :planned)
                             ("payments" "Payments by card and invoice" :planned)
                             ("front-page" "Front page with today's work" :planned)
                             ("reports" "Monthly sales and margin reports" :planned)
                             ("setup" "First-run setup for a new company" :active)
                             ("bookings" "Rental bookings by date range" :planned)
                             ("packing" "Packing lists for rental pickups" :planned)
                             ("handover" "Handover and return of rented items" :planned)
                             ("demo" "Demo companies with realistic data" :planned)
                             ("parity" "Parity map against the old system" :planned)))
            :edges (loop for (to . froms)
                           in '(("company" "layout") ("pricing" "company")
                                ("customers" "company" "update") ("catalogue" "company")
                                ("staff" "company") ("messages" "customers")
                                ("accounting" "company")
                                ("orders" "customers" "catalogue" "pricing")
                                ("lifecycle" "orders") ("stock" "catalogue")
                                ("quotes" "lifecycle" "messages") ("timers" "quotes")
                                ("inquiries" "orders" "messages")
                                ("reservations" "stock" "lifecycle")
                                ("work-orders" "lifecycle" "staff") ("calendar" "work-orders")
                                ("invoices" "lifecycle" "accounting" "messages")
                                ("invoice-status" "invoices")
                                ("work-time" "work-orders" "stock" "invoices")
                                ("payments" "lifecycle" "messages" "accounting")
                                ("front-page" "timers" "invoice-status" "reservations"
                                 "work-orders" "inquiries")
                                ("reports" "invoice-status")
                                ("setup" "company" "catalogue" "messages")
                                ("bookings" "lifecycle" "catalogue")
                                ("packing" "bookings" "reservations")
                                ("handover" "bookings" "invoices")
                                ("demo" "front-page" "reports" "setup" "payments" "calendar"
                                 "work-time" "packing" "handover")
                                ("parity" "demo"))
                         append (mapcar (lambda (from) (list :from from :to to)) froms)))))
   (("A cycle, and nodes with no edges" :layout :stack)
    (graph (:label "Review"
            :nodes (list (list :id "write" :title "Write" :state :done)
                         (list :id "review" :title "Review" :state :active
                               :badges (list (list :text "Reviewer" :kind :agent)))
                         (list :id "fix" :title "Fix" :state :failed)
                         (list :id "docs" :title "Docs" :meta "No edges")
                         (list :id "notes" :title "Release notes" :meta "No edges"))
            :edges (list (list :from "write" :to "review") (list :from "review" :to "fix")
                         (list :from "fix" :to "review"))))
    (graph (:label "Nothing yet" :nodes '()))))
  (check-graph nodes edges)
  (let ((edges (graph-edges nodes edges)))
    (if (null nodes)
        `(:figure ,(attrs (list :class "tun-graph" :id id) attributes)
                  (:figcaption ,label)
                  (:p (:@ :class "tun-graph-empty") ,(tr "No data")))
        (let* ((layout (graph-layout (mapcar (lambda (node) (getf node :id)) nodes) edges))
               (loose (remove-if-not (lambda (node) (member (getf node :id) (layout-loose layout)
                                                            :test #'equal))
                                     nodes)))
          `(:figure ,(attrs (list :class "tun-graph" :id id) attributes)
                    (:figcaption ,label)
                    ,@(when (plusp (layout-columns layout))
                        `((:div (:@ :class "tun-graph-scroll")
                                (:div (:@ :class "tun-graph-canvas")
                                      ,(graph-edges-markup layout)
                                      ,@(graph-columns layout nodes)))
                          ,(graph-list layout nodes)))
                    ,@(when loose
                        `((:div (:@ :class "tun-graph-loose")
                                ,@(mapcar #'graph-node-markup loose))))
                    (:details (:@ :class "tun-graph-table")
                              (:summary ,(tr "Show as a table"))
                              ,(graph-table label nodes edges layout)))))))
