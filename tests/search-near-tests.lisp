;;;; tests/search-near-tests.lisp -- near matches in the one search
;;;; (spec/ui.md 6.4, «Near matches»): the table of cases the server and the
;;;; browser share, the faults, identifiers kept exact, the scores and the
;;;; order, the properties of the rule, the marks, and the search, its page,
;;;; its tool and a choice finding by a misspelled word.  The speed of a
;;;; misspelled word among thousands of records is in search-tests.lisp's
;;;; test of every kind.

(in-package #:tun.tests)

(def-suite search-near :in core)
(in-suite search-near)

;;; ------------------------------------------------------------------
;;; The table of cases (criterion 1)

(defun search-cases ()
  "The cases of tests/search-cases.json, each a list of what was typed, a
text and \"exact\", \"near\" or \"none\"."
  (map 'list (lambda (case) (coerce case 'list))
       (jget (parse-json (uiop:read-file-string
                          (asdf:system-relative-pathname "tun" "tests/search-cases.json")
                          :external-format :utf-8))
             "cases")))

(defun found-as (typed text)
  "How TEXT, as a record's name, is found by TYPED: \"exact\" for a score of
10 or more found exactly, \"near\" for a score below 10 found nearly,
\"none\", or a list of the two values when they disagree with both."
  (multiple-value-bind (score near) (search-match (q typed) :names (list text))
    (cond ((null score) "none")
          ((and (not near) (>= score 10)) "exact")
          ((and near (< score 10)) "near")
          (t (list score near)))))

(test the-rule-answers-the-table-of-cases
  (let ((cases (search-cases)))
    (is (>= (length cases) 40) "~d cases" (length cases))
    (dolist (case cases)
      (destructuring-bind (typed text expected) case
        (is (equal expected (found-as typed text)) "«~a» finds ~s: ~a, not ~s"
            typed text expected (found-as typed text))))))

(test the-faults-a-word-is-forgiven
  (is (equal '(0 0 0 1 1 1 2 2 0 0 0)
             (mapcar #'tun.core::near-faults
                     '("as" "ola" "lunde" "hansen" "minglng" "catering" "caterings"
                       "konfirmasjon" "nordvik1" "ola-nordman" "kari@example")))))

;;; ------------------------------------------------------------------
;;; Identifiers stay exact (criterion 2)

(defun one-fault (word random)
  "WORD with one fault made by RANDOM: a character missing, one extra, one
wrong or two neighbours swapped."
  (let ((at (random (length word) random))
        (other (char "abcdefghijklmnopqrstuvwxyz0123456789" (random 36 random))))
    (case (random 4 random)
      (0 (remove-if (constantly t) word :start at :count 1))
      (1 (concatenate 'string (subseq word 0 at) (string other) (subseq word at)))
      (2 (let ((copy (copy-seq word))) (setf (char copy at) other) copy))
      (t (if (< at (1- (length word)))
             (let ((copy (copy-seq word)))
               (rotatef (char copy at) (char copy (1+ at)))
               copy)
             word)))))

(test identifiers-are-never-found-nearly
  (flet ((finds (typed &rest identifiers)
           (multiple-value-list (search-match (q typed) :identifiers identifiers))))
    (is (equal '(nil) (finds "1043" "1042")))
    (is (equal '(nil) (finds "SO-1043" "SO-1042")))
    (is (equal '(nil) (finds "kari@exampel.no" "kari@example.no")))
    (is (equal '(nil) (finds "abcdefgh" "abcdefgx")) "an identifier of letters alone")
    (is (null (search-match (q "+47 912 34 568") :identifiers (search-phone-forms "+47 912 34 567")))))
  (let ((random (sb-ext:seed-random-state 1404)))
    (dotimes (i 2000)
      (let* ((identifier (coerce (loop repeat (+ 6 (random 7 random))
                                       collect (char "abcdefghijklmnopqrstuvwxyz0123456789-."
                                                     (random 38 random)))
                                 'string))
             (typed (one-fault identifier random))
             (query (q typed)))
        (multiple-value-bind (score near) (search-match query :identifiers (list identifier))
          (is (and (eql score (plain-identifier-score query (list identifier))) (null near))
              "«~a» finds the identifier ~s only as the exact rule does: ~s ~s"
              typed identifier score near)))))
  (is (equal '(1 t) (multiple-value-list
                     (search-match (q "exampel") :names '("Nordvik") :texts '("post@nordvik.example")
                                                 :identifiers '("post@nordvik.example"))))
      "an email given as a text too is found by its words nearly")
  (is (null (search-match (q "post@nordvik.exampel") :names '("Nordvik")
                                                     :texts '("post@nordvik.example")
                                                     :identifiers '("post@nordvik.example")))
      "but the email typed is not"))

;;; ------------------------------------------------------------------
;;; The scores and the order (criterion 3)

(defun match-values (typed &rest keys)
  (multiple-value-list (apply #'search-match (q typed) keys)))

(test a-record-found-nearly-scores-5-by-its-names-and-1-by-its-texts
  (is (equal '(5 t) (match-values "minglng" :names '("Mingling"))))
  (is (equal '(5 t) (match-values "kari nordmnan" :names '("Kari Nordmann"))) "one word exact")
  (is (equal '(1 t) (match-values "minglng" :names '("Party") :texts '("Mingling at seven"))))
  (is (equal '(1 t) (match-values "party minglng" :names '("Party") :texts '("Mingling"))))
  (is (equal '(5 t) (match-values "minglng party" :names '("Party" "Mingling") :texts '("Mingling"))))
  (is (equal '(80 nil) (match-values "mingling" :names '("Mingling"))))
  (is (equal '(10 nil) (match-values "mingling" :names '("Party") :texts '("Mingling")))
      "found exactly in a text: as before")
  (is (equal '(100 nil) (match-values "nordvk" :names '("Nordvik") :identifiers '("nordvk")))
      "an identifier found whole is exact")
  (is (equal '(nil) (match-values "minglng zebra" :names '("Mingling"))) "every word, still"))

(test exact-results-come-before-near-ones-whatever-the-score
  (let ((rows (list (list :id "r1" :name "Mingling Hall" :text "")
                    (list :id "r2" :name "Party" :text "minglng at seven")
                    (list :id "r3" :name "Minglng Bar" :text "")
                    (list :id "r4" :name "Big Minglings Club" :text ""))))
    (dolist (score (list #'identity (lambda (s) (- s 15)) (lambda (s) (- s 200))
                         (lambda (s) (if (< s 10) (+ s 1000) (- s 200)))))
      (let ((results (search-among (q "minglng") rows
                                   :kind "row" :title (lambda (row) (getf row :name))
                                   :texts (lambda (row) (list (getf row :text)))
                                   :href (constantly "/x") :score score)))
        (is (equal '("Minglng Bar" "Party" "Big Minglings Club" "Mingling Hall")
                   (mapcar #'search-result-title results))
            "exact first, then the near ones, newest first among equals: ~s"
            (mapcar (lambda (r) (list (search-result-title r) (search-result-score r))) results))
        (is (equal '(nil nil t t) (mapcar #'search-result-near results))))))
  (let ((results (list (make-search-result :kind "a" :title "near a" :href "/x" :score 1000 :near t)
                       (make-search-result :kind "a" :title "exact a" :href "/x" :score -5)
                       (make-search-result :kind "b" :title "near b" :href "/x" :score 5 :near 'yes)
                       (make-search-result :kind "b" :title "exact b" :href "/x" :score 60))))
    (is (equal '("exact b" "exact a" "near a" "near b")
               (mapcar #'search-result-title (search-order results))))
    (is (eq t (search-result-near (third results))) "NEAR is kept as T"))
  (is (equal '(("2" "Nordvika Marina") ("1" "Nordvik Bakery Ltd"))
             (choice-matches "nordvika" '(("1" "Nordvik Bakery Ltd") ("2" "Nordvika Marina"))
                             :value #'first :text #'second))
      "a choice: the row found exactly first")
  (is (equal '(("1" "Nordvik Bakery Ltd") ("2" "Nordvika Marina"))
             (choice-matches "nordvk" '(("1" "Nordvik Bakery Ltd") ("2" "Nordvika Marina"))
                             :value #'first :text #'second))
      "both found nearly: in the order given"))

;;; ------------------------------------------------------------------
;;; The properties (criterion 4)

(defparameter +near-letters+ "bcdefghijklmnoprstuvy"
  "Letters the near properties build words of: no «a», whose runs fold to one.")

(defun near-word (random &key (from 3) (to 11) (letters +near-letters+))
  (coerce (loop repeat (+ from (random (- to from) random))
                collect (char letters (random (length letters) random)))
          'string))

(defun plain-faults (a b)
  "The optimal string alignment distance between A and B, plainly."
  (let ((d (make-array (list (1+ (length a)) (1+ (length b))))))
    (dotimes (i (1+ (length a))) (setf (aref d i 0) i))
    (dotimes (j (1+ (length b))) (setf (aref d 0 j) j))
    (loop for i from 1 to (length a)
          do (loop for j from 1 to (length b)
                   do (let ((cost (if (char= (char a (1- i)) (char b (1- j))) 0 1)))
                        (setf (aref d i j) (min (1+ (aref d (1- i) j)) (1+ (aref d i (1- j)))
                                                (+ (aref d (1- i) (1- j)) cost)))
                        (when (and (> i 1) (> j 1) (char= (char a (1- i)) (char b (- j 2)))
                                   (char= (char a (- i 2)) (char b (1- j))))
                          (setf (aref d i j) (min (aref d i j) (1+ (aref d (- i 2) (- j 2)))))))))
    (aref d (length a) (length b))))

(test an-exact-hit-never-ranks-below-a-near-one
  (let ((random (sb-ext:seed-random-state 1411)))
    (dotimes (i 400)
      (let* ((rows (loop for n below 10
                         collect (list :id (format nil "r~d" n)
                                       :name (format nil "~{~a~^ ~}"
                                                     (loop repeat (1+ (random 3 random))
                                                           collect (near-word random)))
                                       :text (near-word random))))
             (word (let ((row (nth (random 10 random) rows)))
                     (first (uiop:split-string (getf row :name)))))
             (typed (if (zerop (random 2 random)) word (one-fault word random)))
             (results (search-among (q typed) rows
                                    :kind "row" :title (lambda (row) (getf row :name))
                                    :texts (lambda (row) (list (getf row :text)))
                                    :href (constantly "/x")
                                    :score (lambda (s) (- s (random 30 random)))))
             (nears (mapcar #'search-result-near results)))
        (is (equal nears (sort (copy-list nears) (lambda (a b) (and (not a) b))))
            "«~a»: no near result before an exact one: ~s" typed
            (mapcar (lambda (r) (list (search-result-title r) (search-result-near r))) results))
        (dolist (row rows)
          (multiple-value-bind (score near)
              (search-match (q typed) :names (list (getf row :name)) :texts (list (getf row :text)))
            (when score
              (is (if near (< score 10) (>= score 10))
                  "«~a» in ~s: ~a ~a" typed (getf row :name) score near))))))))

(test a-word-with-a-digit-is-never-found-nearly
  (let ((random (sb-ext:seed-random-state 1412)))
    (dotimes (i 1000)
      (let* ((word (near-word random :from 6 :to 12))
             (at (random (length word) random))
             (typed (one-fault (concatenate 'string (subseq word 0 at)
                                            (string (digit-char (random 10 random)))
                                            (subseq word at))
                               random)))
        (when (find-if #'digit-char-p typed)
          (multiple-value-bind (score near) (search-match (q typed) :names (list word))
            (is (not near) "«~a» is not found nearly in ~s: ~a" typed word score)))))))

(test folding-and-near-matching-commute
  (let ((random (sb-ext:seed-random-state 1413)))
    (dotimes (i 1500)
      (let* ((word (random-word random :from 4 :to 11))
             (text (format nil "~a ~a" (random-word random) (one-fault word random)))
             (typed (dressed word random)))
        (is (equal (multiple-value-list (search-match (q typed) :names (list (dressed text random))))
                   (multiple-value-list (search-match (q (search-fold word))
                                                      :names (list (search-fold text)))))
            "«~a» in ~s found as its fold in the text's" typed text))))
  (is (equal (match-values "soerlie" :names '("Sørlie")) (match-values "soerlie" :names '("sorlie")))
      "a letter folded alike is no fault")
  (is (equal (match-values "SØRLIEE" :names '("Sorlie")) (match-values "sorliee" :names '("sorlie")))))

(test a-near-match-between-whole-words-is-symmetric
  (let ((random (sb-ext:seed-random-state 1414))
        (tried 0))
    (dotimes (i 3000)
      (let* ((w (near-word random :from 6 :to 13))
             (v (one-fault (if (zerop (random 3 random)) (one-fault w random) w) random))
             (band (lambda (word) (cond ((< (length word) 6) nil) ((< (length word) 9) 1) (t 2)))))
        (when (and (plusp (length v))
                   (every (lambda (c) (find c +near-letters+)) v)
                   (eql (funcall band w) (funcall band v))
                   (char= (char w 0) (char v 0))
                   (<= (plain-faults w v) (funcall band w)))
          (incf tried)
          (is (search-match (q w) :names (list v)) "«~a» finds ~s" w v)
          (is (search-match (q v) :names (list w)) "and «~a» finds ~s" v w))))
    (is (> tried 1000) "~d pairs tried" tried))
  (is (search-match (q "bergen") :names '("Bergersen")) "a start: one way")
  (is (null (search-match (q "bergersen") :names '("Bergen"))) "not the other"))

;;; ------------------------------------------------------------------
;;; The marks (criterion 5)

(test the-word-found-nearly-is-marked-whole
  (is (equal '((0 . 8)) (search-mark-ranges (q "minglng") "Mingling" :near t)))
  (is (equal '((0 . 8)) (search-mark-ranges (q "minglni") "Mingling" :near t)) "by its start")
  (is (null (search-mark-ranges (q "minglng") "Mingling")) "no near mark for an exact result")
  (is (equal '((0 . 4) (5 . 13)) (search-mark-ranges (q "kari nordmnan") "Kari Nordmann" :near t))
      "a word found exactly and one nearly")
  (is (equal '((5 . 11)) (search-mark-ranges (q "bjorns") "Herr Bjørnsen" :near t))
      "an exact match is marked as before, near or not")
  (is (equal '((12 . 19)) (search-mark-ranges (q "exampel") "post@nordvk.example" :near t)))
  (let* ((long (format nil "~{~a~^ ~} Mingling in the hall from seven."
                       (loop repeat 20 collect "word")))
         (excerpt (search-excerpt (q "minglng") long :near t)))
    (is (string-prefix-p "…Mingling in the hall" excerpt) "the excerpt starts from it: ~s" excerpt)
    (is (string-prefix-p "word word" (search-excerpt (q "minglng") long)) "not without :near")
    (is (equal excerpt (tun.core::search-matched-text (q "minglng") "Party" '() (list "Party" long)
                                                      :near t))
        "MATCHED holds it")
    (let ((result (first (search-among (q "minglng")
                                       (list (list :id "p1" :title "Party" :text long))
                                       :kind "row" :title (lambda (row) (getf row :title))
                                       :texts (lambda (row) (list (getf row :text)))
                                       :href (constantly "/x")))))
      (is (search-result-near result))
      (is (equal excerpt (search-result-matched result)) "search-among works it out")))
  (flet ((html (query item)
           (tun.html:render-html (tun.ui:search-results (:query query :items (list item))))))
    (is (search "<mark>Mingling</mark> Hall"
                (html "minglng" '(:kind "row" :label "Row" :title "Mingling Hall" :href "/x" :near t))))
    (is (search "Row · <mark>Mingling</mark> at seven"
                (html "minglng" '(:kind "row" :label "Row" :title "Party" :meta ("Mingling at seven")
                                  :href "/x" :near t)))
        "in the line, when the title holds no mark")
    (is (not (search "<mark>" (html "minglng" '(:kind "row" :label "Row" :title "Mingling Hall"
                                                :href "/x"))))
        "a result not found nearly has no near mark")))

;;; ------------------------------------------------------------------
;;; Everywhere (criterion 6)

(test the-modules-the-page-the-tool-and-the-choices-find-by-a-misspelled-word
  (with-test-server (port)
    (let ((nordvik (jget (call-ok "customers_create" "employee:anna" "name" "Nordvik Bakery Ltd"
                                  "email" "post@nordvik.example")
                         "id"))
          (product (jget (call-ok "products_create" "employee:anna" "name" "Telt" "kind" "rental"
                                  "unit" "stk" "unit_price_minor" 1000 "stock_tracked" nil
                                  "units_owned" 2)
                         "id")))
      (call-ok "customers_create" "employee:anna" "name" "Nordvk Sport" "email" "nv@sport.example")
      (call-ok "orders_create" "employee:anna" "customer_id" nordvik
               "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
      (flet ((items (text)
               (mapcar (lambda (item) (list (jget item "title") (jget item "kind") (jget item "near")))
                       (coerce (jget (call-ok "search" "employee:anna" "query" text) "items")
                               'list))))
        (is (equal '(("Nordvik Bakery Ltd" "customer" nil) ("Nordvik Bakery Ltd" "order" nil)
                     ("Nordvk Sport" "customer" t))
                   (items "nordvik"))
            "exact hits, the order among them, before the customer found nearly")
        (is (equal '(("Nordvk Sport" "customer" nil) ("Nordvik Bakery Ltd" "customer" t)
                     ("Nordvik Bakery Ltd" "order" t))
                   (items "nordvk"))
            "found nearly: the customers module and the orders module")
        (is (equal '(("Nordvik Bakery Ltd" "customer" t) ("Nordvik Bakery Ltd" "order" t))
                   (items "bakeyr"))))
      (let* ((jar (web-login port "employee:anna"))
             (page (nth-value 1 (web-request port "/search?q=nordvk" :jar jar)))
             (fragment (nth-value 1 (web-request port "/search?q=nordvk" :jar jar
                                                 :headers +htmx-part+))))
        (dolist (html (list page fragment))
          (is (< (search "<mark>Nordvk</mark> Sport" html)
                 (search "<mark>Nordvik</mark> Bakery Ltd" html))
              "the page and the fragment: the same order, the whole word marked")))
      (let ((jar (web-login port "employee:anna")))
        (multiple-value-bind (status fragment)
            (web-request port "/choices/customer" :parameters '(("q" . "nordvk"))
                                                  :jar jar :headers +htmx-part+)
          (is (= 200 status))
          (is (= 2 (occurrences "role=\"option\"" fragment)))
          (is (< (search "Nordvk Sport" fragment) (search "Nordvik Bakery Ltd" fragment))
              "the generated choice: the exact one first, though the other's name sorts first"))))))
