;;;; tests/graph-tests.lisp -- things and what depends on what among them:
;;;; GRAPH (spec/ui.md 6.3), its layered layout, its nodes, badges and
;;;; edges, its table, and the graphs it refuses.

(in-package #:tun.tests)

(def-suite graphs :in core)
(in-suite graphs)

(defun layout-of (ids edges)
  "The layout of IDS joined by EDGES, each given as (FROM TO)."
  (tun.ui::graph-layout ids (mapcar (lambda (edge) (cons (first edge) (second edge))) edges)))

(defun place-of (layout id)
  (gethash id (tun.ui::layout-places layout)))

(defun every-place (layout)
  "Every place LAYOUT gives a node or an edge's empty place, each once."
  (remove-duplicates (append (loop for place being the hash-values of (tun.ui::layout-places layout)
                                   collect place)
                             (loop for route in (tun.ui::layout-routes layout)
                                   append (fourth route)))
                     :test #'equal))

(defun shared-places-p (layout)
  "Whether two nodes, or a node and an edge's empty place, share a place in
LAYOUT.  The edges from one node may share their empty places."
  (let ((nodes (loop for place being the hash-values of (tun.ui::layout-places layout)
                     collect place)))
    (or (/= (length nodes) (length (remove-duplicates nodes :test #'equal)))
        (loop for route in (tun.ui::layout-routes layout)
                thereis (intersection (butlast (rest (fourth route))) nodes :test #'equal)))))

(defun ascending-p (layout)
  "Whether every edge of LAYOUT that was not reversed goes to a later layer,
and every reversed one to an earlier layer."
  (loop for (from to reversed) in (tun.ui::layout-routes layout)
        always (if reversed
                   (> (car (place-of layout from)) (car (place-of layout to)))
                   (< (car (place-of layout from)) (car (place-of layout to))))))

(defun random-edges (count edges seed)
  "EDGES distinct edges among COUNT nodes n0, n1, …, each from a node to a
later one, chosen by a fixed walk from SEED."
  (let ((pairs '()))
    (loop while (< (length pairs) edges)
          do (setf seed (mod (+ (* seed 1103515245) 12345) 2147483648))
             (let* ((from (mod (floor seed 16) (1- count)))
                    (to (+ from 1 (mod (floor seed 65536) (- count from 1))))
                    (pair (list (format nil "n~d" from) (format nil "n~d" to))))
               (unless (member pair pairs :test #'equal)
                 (push pair pairs))))
    (nreverse pairs)))

(defun all-matches-group (regex text)
  "The first group of each match of REGEX in TEXT."
  (let ((groups '()))
    (cl-ppcre:do-register-groups (group) (regex text)
      (push group groups))
    (nreverse groups)))

(defun numbered-ids (count)
  (loop for i below count collect (format nil "n~d" i)))

;;; ------------------------------------------------------------------
;;; The layout

(test a-chain-lies-on-one-row-a-layer-a-node
  (let ((layout (layout-of '("a" "b" "c") '(("a" "b") ("b" "c")))))
    (is (equal '((0 . 0) (1 . 0) (2 . 0))
               (mapcar (lambda (id) (place-of layout id)) '("a" "b" "c"))))
    (is (= 3 (tun.ui::layout-columns layout)))
    (is (= 1 (tun.ui::layout-rows layout)))))

(test every-edge-goes-to-a-later-layer
  (let ((layout (layout-of '("a" "b" "c" "d") '(("a" "b") ("a" "c") ("b" "d") ("c" "d")))))
    (is (equal '((0 . 0) (1 . 0) (1 . 1) (2 . 0))
               (mapcar (lambda (id) (place-of layout id)) '("a" "b" "c" "d"))))
    (is (ascending-p layout)))
  (let ((layout (layout-of (numbered-ids 60) (random-edges 60 90 7))))
    (is (ascending-p layout) "sixty nodes and ninety edges")
    (is (not (shared-places-p layout)) "no two share a place")))

(test a-node-with-no-edges-stands-apart
  (let ((layout (layout-of '("a" "lone" "b" "other") '(("a" "b")))))
    (is (equal '("lone" "other") (tun.ui::layout-loose layout)) "in the order given")
    (is (null (place-of layout "lone")) "not in the layers")
    (is (equal '("a" "b") (tun.ui::layout-order layout))))
  (let ((layout (layout-of '("a" "b") '())))
    (is (equal '("a" "b") (tun.ui::layout-loose layout)))
    (is (= 0 (tun.ui::layout-columns layout)))))

(test a-node-with-no-edge-into-it-stands-before-its-earliest-successor
  (let ((layout (layout-of '("s" "a" "b" "c" "d")
                           '(("a" "b") ("b" "c") ("c" "d") ("s" "d")))))
    (is (= 3 (car (place-of layout "d"))))
    (is (= 2 (car (place-of layout "s"))) "not in the first layer, with a long edge")
    (is (= 0 (car (place-of layout "a"))))))

(test a-long-edge-passes-through-places-no-node-takes
  (let* ((layout (layout-of '("a" "b" "c" "d") '(("a" "b") ("b" "c") ("c" "d") ("a" "d"))))
         (long (find-if (lambda (route) (and (equal "a" (first route)) (equal "d" (second route))))
                        (tun.ui::layout-routes layout))))
    (is (= 4 (length (fourth long))) "the nodes and an empty place in each layer between")
    (is (equal '(1 2) (mapcar #'car (butlast (rest (fourth long))))))
    (is (not (shared-places-p layout)))
    (is (equal '(0 0 0 0) (mapcar (lambda (id) (cdr (place-of layout id))) '("a" "b" "c" "d")))
        "the chain stays on its row, the long edge beside it")))

(test the-long-edges-from-one-node-share-their-empty-places
  (let* ((layout (layout-of '("a" "b" "c" "d" "e")
                            '(("a" "b") ("b" "c") ("c" "d") ("a" "d") ("a" "e") ("c" "e"))))
         (routes (tun.ui::layout-routes layout))
         (to-d (fourth (find '("a" "d") routes :key (lambda (route) (subseq route 0 2))
                                                 :test #'equal)))
         (to-e (fourth (find '("a" "e") routes :key (lambda (route) (subseq route 0 2))
                                                 :test #'equal))))
    (is (equal (subseq to-d 1 3) (subseq to-e 1 3)) "one trunk from a, through layers 1 and 2")
    (is (not (shared-places-p layout)))))

(test crossed-edges-come-out-uncrossed
  (let ((layout (layout-of '("a1" "a2" "b1" "b2") '(("a1" "b2") ("a2" "b1")))))
    (is (= (cdr (place-of layout "a1")) (cdr (place-of layout "b2"))))
    (is (= (cdr (place-of layout "a2")) (cdr (place-of layout "b1"))))))

(test a-cycle-is-laid-out-with-the-edge-it-reverses-marked
  (let* ((layout (layout-of '("a" "b" "c") '(("a" "b") ("b" "c") ("c" "a"))))
         (back (remove-if-not #'third (tun.ui::layout-routes layout))))
    (is (equal '(0 1 2) (mapcar (lambda (id) (car (place-of layout id))) '("a" "b" "c"))))
    (is (equal '(("c" "a")) (mapcar (lambda (route) (subseq route 0 2)) back))
        "the edge back to a node still being searched")
    (is (ascending-p layout))
    (is (not (shared-places-p layout))))
  (let ((layout (layout-of '("a" "b") '(("a" "b") ("b" "a")))))
    (is (ascending-p layout) "two nodes each other's dependency")
    (is (= 1 (count-if #'third (tun.ui::layout-routes layout))))))

(test the-same-graph-gets-the-same-layout
  (flet ((picture (layout)
           (list (mapcar (lambda (id) (place-of layout id)) (numbered-ids 40))
                 (tun.ui::layout-routes layout))))
    (is (equal (picture (layout-of (numbered-ids 40) (random-edges 40 70 3)))
               (picture (layout-of (numbered-ids 40) (random-edges 40 70 3)))))))

;;; ------------------------------------------------------------------
;;; The markup

(defun graph-html (&rest options)
  (with-language ("en")
    (tun.html:render-html (tun.ui:graph* options))))

(defun graph-html-nb (&rest options)
  (with-language ("nb")
    (tun.html:render-html (tun.ui:graph* options))))

(defun edge (from to)
  (list :from from :to to))

(defparameter *graph-nodes*
  (list (list :id "a" :title "Brief" :state :done :href "/steps/a")
        (list :id "b" :title "Booking calendar" :meta "Factory 3" :state :active :href "/steps/b"
              :badges (list (list :text "Claude i tun" :kind :agent)
                            (list :text "#12" :kind :ref :href "/items/12")))
        (list :id "c" :title "Card payments" :state :waiting
              :badges (list (list :text "1 question" :kind :ref :tone :warning)))
        (list :id "lone" :title "Docs")))

(test a-node-shows-its-title-state-meta-and-badges
  (let ((html (graph-html :label "Work" :nodes *graph-nodes*
                          :edges (list (edge "a" "b") (edge "b" "c")))))
    (is (search "<figcaption>Work</figcaption>" html))
    (is (search "data-node=\"b\" data-state=\"active\" title=\"Booking calendar\" data-live" html)
        "an agent's badge marks its node live")
    (is (search "<a class=\"tun-graph-link\" href=\"/steps/b\">Booking calendar</a>" html))
    (is (search (concatenate 'string "<span class=\"tun-graph-state\">Active</span>"
                             "<span class=\"tun-graph-meta\">Factory 3</span>")
                html))
    (is (search "data-state=\"planned\" title=\"Docs\"" html) "planned unless given")
    (is (search "class=\"tun-graph-live\" aria-hidden=\"true\"" html))
    (is (search "Claude i tun</span><span class=\"tun-graph-hidden\">, working now</span>"
                html))
    (is (search "data-variant=\"info\" data-kind=\"agent\"" html) "an agent is info unless given")
    (is (search (concatenate 'string "<a class=\"tun-graph-badge-link\" href=\"/items/12\">"
                             "<span class=\"tun-badge\" data-variant=\"outline\""
                             " data-kind=\"ref\" title=\"#12\">"
                             "<span class=\"tun-graph-badge-text\">#12</span></span></a>")
                html)
        "a reference, neutral, as a link")
    (is (search "data-variant=\"warning\" data-kind=\"ref\" title=\"1 question\">" html))
    (is (search "<span class=\"tun-badge\" data-variant=\"outline\" title=\"Plain\">"
                (graph-html :label "x" :nodes (list (list :id "a" :title "a"
                                                          :badges (list (list :text "Plain"))))))
        "a badge without a kind is a plain label")
    (is (= 1 (count-matches "data-live" html)) "only the node an agent works on")))

(test every-state-has-its-word-in-english-and-norwegian
  (let ((nodes (loop for state in '(:planned :active :waiting :done :failed :blocked)
                     collect (list :id (string-downcase state) :title "x" :state state))))
    (is (search "Planned Active Waiting Done Failed Blocked"
                (format nil "~{~a~^ ~}" (all-matches-group "class=\"tun-graph-state\">([^<]*)<"
                                                           (graph-html :label "x" :nodes nodes)))))
    (is (search "Planlagt Aktiv Venter Ferdig Feilet Blokkert"
                (format nil "~{~a~^ ~}"
                        (all-matches-group "class=\"tun-graph-state\">([^<]*)<"
                                           (graph-html-nb :label "x" :nodes nodes)))))
    (let ((html (graph-html-nb :label "x" :nodes *graph-nodes* :edges (list (edge "a" "b")))))
      (is (search ", arbeider nå" html))
      (is (search "Vis som tabell" html))
      (is (search "Avhenger av" html)))))

(test each-edge-is-drawn-once-from-side-to-side-with-its-arrowhead
  (let ((html (graph-html :label "x" :nodes *graph-nodes*
                          :edges (list (edge "a" "b") (edge "a" "b") (edge "b" "b")
                                       (edge "b" "c") (edge "c" "b")))))
    (is (= 3 (count-matches "class=\"tun-graph-edge\"" html))
        "a repeated edge once, one to itself not at all")
    (is (search "0 0 704 88" html) "three layers of one row, in CSS pixels")
    (is (search (concatenate 'string "data-from=\"a\" data-to=\"b\">"
                             "<path d=\"M192,44 L248,44\"></path>"
                             "<polygon points=\"256,44 248,39 248,49\">")
                html)
        "from the source's right side to the arrowhead at the target's left")
    (is (search (concatenate 'string "data-from=\"c\" data-to=\"b\" data-back=\"\">"
                             "<path d=\"M512,44 L456,44\"></path>"
                             "<polygon points=\"448,44 456,39 456,49\">")
                html)
        "a reversed edge from its source's left side, its arrowhead at its target's right")))

(test edges-between-rows-curve-and-pass-through-empty-places
  (let ((html (graph-html :label "x"
                          :nodes (loop for id in '("a" "b" "c" "d") collect (list :id id :title id))
                          :edges (list (edge "a" "b") (edge "b" "c") (edge "c" "d")
                                       (edge "a" "d")))))
    (is (search (concatenate 'string "data-from=\"a\" data-to=\"d\"><path d=\"M192,44"
                             " C224,44 224,148 256,148 L448,148 L512,148 L704,148"
                             " C732,148 732,44 760,44")
                html)
        "a curve down to the empty place, straight through it")
    (is (= 2 (count-matches "class=\"tun-graph-gap\" aria-hidden=\"true\"" html))
        "an empty place in each layer the long edge crosses")))

(test the-table-holds-every-node-in-the-order-of-the-layers
  (let* ((html (graph-html :label "Work" :nodes *graph-nodes*
                           :edges (list (edge "b" "c") (edge "a" "c") (edge "a" "b"))))
         (table (subseq html (search "tun-graph-table" html))))
    (is (search "<details class=\"tun-graph-table\"><summary>Show as a table</summary>" html)
        "closed by default")
    (is (< (search ">Brief<" table) (search ">Booking calendar<" table)
           (search ">Card payments<" table) (search ">Docs<" table))
        "by layer, then the nodes with no edges")
    (is (search "<a href=\"/steps/a\">Brief</a>" table))
    (is (search "Booking calendar, Brief" table) "what a node depends on, in the edges' order")))

(test a-graph-with-no-nodes-says-so
  (let ((html (graph-html :label "Nothing yet" :nodes '())))
    (is (search "No data" html))
    (is (not (search "tun-graph-table" html)))
    (is (not (search "<svg" html)))))

(test nodes-with-no-edges-are-in-a-row-of-their-own
  (let ((html (graph-html :label "x" :nodes *graph-nodes* :edges '())))
    (is (not (search "tun-graph-canvas" html)) "no drawing without an edge")
    (is (= 4 (count-matches "class=\"tun-graph-node\""
                            (subseq html (search "tun-graph-loose" html)
                                    (search "tun-graph-table" html)))))))

(test a-graph-out-of-bounds-or-misnamed-is-an-error
  (flet ((nodes (count) (loop for id in (numbered-ids count) collect (list :id id :title id))))
    (signals error (graph-html :label "x" :nodes (nodes 151)))
    (signals error (graph-html :label "x" :nodes (nodes 30)
                               :edges (mapcar (lambda (pair) (edge (first pair) (second pair)))
                                              (random-edges 30 301 1))))
    (signals error (graph-html :label "x"
                               :nodes (list (list :id "a" :title "a"
                                                  :badges (loop repeat 9
                                                                collect (list :text "b"))))))
    (signals error (graph-html :label "x" :nodes (list (list :id "a" :title "a")
                                                       (list :id "a" :title "again"))))
    (signals error (graph-html :label "x" :nodes (list (list :title "no id"))))
    (signals error (graph-html :label "x" :nodes (list (list :id "a"))))
    (signals error (graph-html :label "x" :nodes (nodes 2) :edges (list (edge "n0" "n9"))))
    (signals error (graph-html :label "x" :nodes (list (list :id "a" :title "a" :state :late))))
    (signals error (graph-html :label "x" :nodes (list (list :id "a" :title "a" :colour :red))))
    (signals error (graph-html :label "x"
                               :nodes (list (list :id "a" :title "a"
                                                  :badges (list (list :text "b" :kind :pill))))))
    (signals error (graph-html :label "x"
                               :nodes (list (list :id "a" :title "a"
                                                  :badges (list (list :text "b" :kind :label))))))
    (signals error (graph-html :label "x"
                               :nodes (list (list :id "a" :title "a"
                                                  :badges (list (list :text "b" :tone :pink))))))))

(test the-largest-graph-allowed-renders-within-a-second
  (let* ((nodes (loop for id in (numbered-ids 150)
                      collect (list :id id :title id :state :active
                                    :badges (list (list :text "agent" :kind :agent)))))
         (edges (mapcar (lambda (pair) (edge (first pair) (second pair)))
                        (random-edges 150 300 11)))
         (start (get-internal-real-time))
         (html (graph-html :label "x" :nodes nodes :edges edges))
         (seconds (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
    (is (= 300 (count-matches "class=\"tun-graph-edge\"" html)))
    (is (< seconds 1) "rendered in ~,2fs" (float seconds))))
