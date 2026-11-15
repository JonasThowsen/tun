;;;; tests/case-tests.lisp -- case analysis over a closed set (spec/core.md
;;;; 2.7): what ECASE-OF, CASE-OF and ETYPECASE-OF warn about when compiled
;;;; and when loaded, how they run over every set of Tun's registry, a build
;;;; that stops when a set grows, and the cases guard (spec/testing.md 1,
;;;; test 11) on planted text and on Tun's own sources.

(in-package #:tun.tests)

(def-suite cases :in core)
(in-suite cases)

(defstruct case-test-pickup place)
(defstruct case-test-shipment address)
(defstruct case-test-courier name)
(deftype case-test-delivery () '(or case-test-pickup case-test-shipment))

(defparameter +order-statuses+
  '("draft" "quote_sent" "accepted" "confirmed" "picked_up" "returned" "ready_for_invoice"
    "completed" "cancelled")
  "The orders module's statuses, as modules/orders/orders.lisp declares them.")

(defun compile-collecting-warnings (form)
  "Compile FORM as the body of a function of one argument, VALUE: the
function and the warnings compiling it gave."
  (let ((warnings '()))
    (let ((function (handler-bind ((warning (lambda (w) (push w warnings) (muffle-warning w))))
                      (compile nil `(lambda (value) (declare (ignorable value)) ,form)))))
      (values function (nreverse warnings)))))

(defun case-warning-texts (form)
  "The text of each CASE-SET-WARNING compiling FORM gives; fails a check on any
other warning."
  (multiple-value-bind (function warnings) (compile-collecting-warnings form)
    (declare (ignore function))
    (dolist (warning warnings)
      (is (typep warning 'case-set-warning) "another warning: ~a" warning)
      (is (not (typep warning 'style-warning)) "a full warning, which fails the build"))
    (mapcar #'princ-to-string warnings)))

(defun order-status-branches (&key (without '()) (with '()))
  "A branch for each order status but those in WITHOUT, then one for each of
WITH, each returning its key."
  (append (loop for status in +order-statuses+
                unless (member status without :test #'string=)
                  collect `(,status ,status))
          (loop for key in with collect `(,key ,key))))

(defun contains-all-p (text &rest parts)
  (every (lambda (part) (search part text)) parts))

;;; ------------------------------------------------------------------
;;; What compiling a form warns about

(test a-missing-value-warns-naming-the-set-and-where-it-is-declared
  (let ((texts (case-warning-texts
                `(ecase-of (tun.orders:order status) value
                   ,@(order-status-branches :without '("cancelled" "returned"))))))
    (is (= 1 (length texts)) "~{~a~^~%~}" texts)
    (is (contains-all-p (first texts) "ecase-of (order status)" "has no branch for"
                        "\"returned\", \"cancelled\""
                        "declared at modules/orders/orders.lisp:" "(orders)"
                        "draft, quote_sent, accepted")
        "~a" (first texts))))

(test a-value-outside-the-set-warns-in-ecase-of-and-in-case-of
  (let ((texts (case-warning-texts
                `(ecase-of (tun.orders:order status) value
                   ,@(order-status-branches :with '("shipped"))))))
    (is (= 1 (length texts)) "~{~a~^~%~}" texts)
    (is (contains-all-p (first texts) "names \"shipped\", not in the set"
                        "modules/orders/orders.lisp:")))
  (let ((texts (case-warning-texts
                '(case-of (tun.orders:order status) value
                   ("confirmd" 1)
                   (otherwise 2)))))
    (is (= 1 (length texts)) "~{~a~^~%~}" texts)
    (is (contains-all-p (first texts) "case-of (order status)" "names \"confirmd\""))))

(test case-of-needs-otherwise-and-a-value-is-named-once
  (let ((texts (case-warning-texts '(case-of (tun.orders:order status) value ("draft" 1)))))
    (is (= 1 (length texts)))
    (is (search "has no final otherwise" (first texts))))
  (let ((texts (case-warning-texts
                `(ecase-of (tun.orders:order status) value
                   ("draft" :first)
                   ,@(order-status-branches)))))
    (is (= 1 (length texts)))
    (is (contains-all-p (first texts) "names \"draft\" in more than one branch"))))

(test a-member-type-is-a-set-of-values
  (let ((texts (case-warning-texts '(ecase-of error-code value
                                     (:forbidden 403) (:not-found 404) (:gone 410)))))
    (is (= 2 (length texts)) "~{~a~^~%~}" texts)
    (is (find-if (lambda (text)
                   (contains-all-p text "ecase-of error-code" "names :gone, not in the set"
                                   "deftype error-code in src/core/conditions.lisp"))
                 texts))
    (is (find-if (lambda (text)
                   (contains-all-p text "has no branch for" ":conflict" ":read-only"))
                 texts))))

(test etypecase-of-checks-the-types-of-an-or-type
  (is (null (case-warning-texts '(etypecase-of case-test-delivery value
                                  (case-test-pickup 1) (case-test-shipment 2)))))
  (let ((texts (case-warning-texts '(etypecase-of case-test-delivery value
                                     (case-test-pickup 1) (case-test-courier 3)))))
    (is (= 2 (length texts)) "~{~a~^~%~}" texts)
    (is (find-if (lambda (text) (contains-all-p text "names case-test-courier, not in the set"
                                                "deftype case-test-delivery"))
                 texts))
    (is (find-if (lambda (text) (contains-all-p text "has no branch for case-test-shipment"))
                 texts))))

(test a-set-that-is-not-there-warns-saying-why
  (flet ((says (form &rest parts)
           (let ((texts (case-warning-texts form)))
             (is (= 1 (length texts)) "~s: ~{~a~^~%~}" form texts)
             (is (apply #'contains-all-p (first texts) parts) "~a" (first texts)))))
    (says '(ecase-of (case-test-nothing status) value ("a" 1))
          "case-test-nothing names no entity known when this is compiled"
          "define it before this form, or add the system that defines it to the dependencies")
    (says '(ecase-of (tun.orders:order colour) value ("red" 1))
          "order has no field colour")
    (says '(ecase-of (tun.orders:order department) value ("sales" 1))
          "the field department of order is (string :max 100), not an enum")
    (says '(ecase-of integer value (1 1)) "integer is integer, not a (member ...) type")
    (says '(ecase-of case-test-no-type value (:a 1)) "case-test-no-type names no type known")
    (says '(etypecase-of error-code value (keyword 1)) "error-code is not an (or ...) type")
    (says '(ecase-of "order" value ("a" 1)) "names no set")))

;;; ------------------------------------------------------------------
;;; What a form does when it runs

(test a-value-no-branch-holds-is-case-not-handled
  (let ((function (compile-collecting-warnings
                   `(ecase-of (tun.orders:order status) value ,@(order-status-branches)))))
    (is (equal "returned" (funcall function "returned")))
    (let ((condition (handler-case (progn (funcall function "shipped") nil)
                       (case-not-handled (c) c))))
      (is (typep condition 'case-not-handled))
      (is (equal "shipped" (case-not-handled-value condition)))
      (is (equal "(order status)" (case-not-handled-set condition))))
    (signals case-not-handled (funcall function nil))
    (signals case-not-handled (funcall function 12)))
  (let ((function (compile-collecting-warnings
                   '(etypecase-of case-test-delivery value
                     (case-test-pickup :pickup) (case-test-shipment :shipment)))))
    (is (eq :pickup (funcall function (make-case-test-pickup))))
    (signals case-not-handled (funcall function (make-case-test-courier)))))

(defun every-enum-set ()
  "Every field set of the registry as it stands: (DESIGNATOR VALUES) each."
  (loop for field in (declared-fields)
        collect (list (list (declared-field-entity field) (declared-field-name field))
                      (declared-field-values field))))

(defparameter +kernel-member-types+ '(error-code tun.core::role tun.core::policy
                                      tun.core::operation-kind)
  "The member types the kernel's own code switches over.")

(defun check-set-runs-right (designator values)
  "A form over DESIGNATOR with a branch per value of VALUES compiles silently
and runs each value's branch; outside values and NIL go to case-not-handled,
or to otherwise; case-of sends what it does not name to otherwise."
  (let ((branches (loop for value in values for index from 0 collect `((,value) ,index)))
        (outside (if (stringp (first values)) "not-a-value-of-any-set" :not-a-value)))
    (multiple-value-bind (exact warnings)
        (compile-collecting-warnings `(ecase-of ,designator value ,@branches))
      (is (null warnings) "~a: ~{~a~^~%~}" designator warnings)
      (loop for value in values for index from 0
            do (is (eql index (funcall exact value)) "~a ~s" designator value))
      (signals case-not-handled (funcall exact outside)))
    (let ((fallback (compile-collecting-warnings
                     `(ecase-of ,designator value ,@branches (otherwise :outside)))))
      (is (eq :outside (funcall fallback outside)))
      (unless (member nil values)
        (is (eq :outside (funcall fallback nil)))))
    (multiple-value-bind (partial warnings)
        (compile-collecting-warnings
         `(case-of ,designator value ((,(first values)) :first) (otherwise :rest)))
      (is (null warnings) "~a: ~{~a~^~%~}" designator warnings)
      (is (eq :first (funcall partial (first values))))
      (dolist (value (rest values))
        (is (eq :rest (funcall partial value)) "~a ~s" designator value)))))

(test every-declared-set-runs-the-branch-of-each-value
  (let ((sets (every-enum-set)))
    (is (< 40 (length sets)) "every module's enum fields are noted: ~d" (length sets))
    (is (find '(tun.orders:order "STATUS") sets
              :test (lambda (wanted set)
                      (and (eq (first wanted) (first (first set)))
                           (string= (second wanted) (second (first set)))))))
    (loop for (designator values) in sets
          do (check-set-runs-right designator values))
    (dolist (type +kernel-member-types+)
      (check-set-runs-right type (rest (sb-ext:typexpand-all type))))))

;;; ------------------------------------------------------------------
;;; When the set changes

(test defining-a-set-again-warns-for-the-forms-compiled-against-the-old-one
  (flet ((note (values)
           (let ((warnings '()))
             (handler-bind ((warning (lambda (w) (push (princ-to-string w) warnings)
                                       (muffle-warning w))))
               (tun.core::note-declared-fields
                'case-test-parcel `((status (enum ,@values) case-test-parcel-status))
                "tests/case-tests.lisp:1" "core"))
             warnings)))
    (note '("packed" "sent"))
    (is (null (case-warning-texts '(ecase-of (case-test-parcel status) value
                                    ("packed" 1) ("sent" 2)))))
    (let ((warnings (note '("packed" "sent" "lost"))))
      (is (= 1 (length warnings)) "~{~a~^~%~}" warnings)
      (is (contains-all-p (first warnings) "The set (case-test-parcel status) is now"
                          "packed, sent, lost" "compile them again" "ecase-of at")))
    (is (null (note '("packed" "sent" "lost"))) "the same set again warns about nothing")))

(defparameter +case-build-files+
  '(("case-sets.asd" "(defsystem \"case-sets\" :depends-on (\"tun\") :serial t
  :components ((:file \"package\") (:file \"parcel\") (:file \"labels\")))
(defsystem \"case-sets/users\" :depends-on (\"case-sets\") :serial t
  :components ((:file \"users\")))
(defsystem \"case-sets/loose\" :depends-on (\"case-sets\")
  :components ((:file \"kinds\") (:file \"kind-labels\")))
(defsystem \"case-sets/all\" :depends-on (\"case-sets/users\" \"case-sets/loose\"))
")
    ("package.lisp" "(defpackage #:case-sets (:use #:cl #:tun.core))
")
    ("parcel.lisp" "(in-package #:case-sets)
(define-entity parcel (:embedded t)
  ((status :type (enum \"packed\" \"sent\"))))
(extend-entity parcel (:name parcel-size)
  ((size :type (enum \"small\" \"large\"))))
(define-computed-field parcel speed (p) (:type (enum \"slow\" \"fast\"))
  (if (equal (parcel-status p) \"sent\") \"fast\" \"slow\"))
(defun parcel-step (status)
  (ecase-of (parcel status) status (\"packed\" 1) (\"sent\" 2)))
(defun parcel-size-word (size)
  (ecase-of (parcel size) size (\"small\" \"S\") (\"large\" \"L\")))
(defun parcel-speed-word (speed)
  (ecase-of (parcel speed) speed (\"slow\" \"Slow\") (\"fast\" \"Fast\")))
")
    ("labels.lisp" "(in-package #:case-sets)
(defun parcel-label (status)
  (ecase-of (parcel status) status (\"packed\" \"Packed\") (\"sent\" \"Sent\")))
")
    ("users.lisp" "(in-package #:case-sets)
(defun parcel-tone (status)
  (ecase-of (parcel status) status (\"packed\" :info) (\"sent\" :success)))
")
    ("kinds.lisp" "(in-package #:case-sets)
(define-entity crate (:embedded t)
  ((kind :type (enum \"small\" \"large\"))))
")
    ("kind-labels.lisp" "(in-package #:case-sets)
(defun crate-label (kind)
  (ecase-of (crate kind) kind (\"small\" \"Small\") (\"large\" \"Large\")))
"))
  "Three systems over two sets: a set and forms over it in the same file, in a
later file and in a system depending on it (each with :serial t), and a
system without :serial t whose second file uses the first file's set.")

(defun write-case-build-file (directory name text)
  (with-open-file (out (merge-pathnames name directory) :direction :output
                                                        :if-exists :supersede :external-format :utf-8)
    (write-string text out)))

(defun change-case-build-file (directory name old new)
  "Replace OLD with NEW in DIRECTORY's file NAME, dated at least a second
after its fasl, so ASDF sees it changed however soon after the last build
it is written."
  (let* ((path (merge-pathnames name directory))
         (fasl (asdf:apply-output-translations (make-pathname :type "fasl" :defaults path)))
         (text (file-text path)))
    (let ((at (search old text)))
      (assert at () "~a holds no ~s" name old)
      (write-case-build-file directory name (concatenate 'string (subseq text 0 at) new
                                                         (subseq text (+ at (length old))))))
    (let ((unix (- (max (file-write-date path) (1+ (file-write-date fasl)))
                   (encode-universal-time 0 0 0 1 1 1970 0))))
      (sb-posix:utimes (namestring path) unix unix))))

(defun run-case-build (directory)
  "Build DIRECTORY's three systems in a process of their own, as bin/build
does: its exit code and the warnings it printed."
  (multiple-value-bind (output error-output code)
      (uiop:run-program (list "sbcl" "--noinform" "--non-interactive" "--no-userinit" "--no-sysinit"
                              "--load" (namestring (asdf:system-relative-pathname
                                                    "tun" "tests/fixtures/case-build.lisp"))
                              (namestring directory) "case-sets/all")
                        :output :string :error-output :string :ignore-error-status t)
    (values code
            (remove-if-not (lambda (line) (string-prefix-p "warning: " line))
                           (uiop:split-string output :separator '(#\Newline)))
            error-output)))

(defun warning-about-p (warnings &rest parts)
  (find-if (lambda (warning) (apply #'contains-all-p warning parts)) warnings))

(test a-set-that-grows-stops-the-incremental-build-where-it-is-not-handled
  (let ((directory (merge-pathnames (format nil ".build/case-build/~a/" (new-id "cb"))
                                    (asdf:system-source-directory "tun"))))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn
           (loop for (name text) in +case-build-files+
                 do (write-case-build-file directory name text))
           (multiple-value-bind (code warnings error-output) (run-case-build directory)
             (is (eql 0 code) "the first build is clean: ~{~a~^~%~}~%~a" warnings
                 (subseq error-output (max 0 (- (length error-output) 2000)))))
           ;; A status added to parcel's set: the forms over it in its own file,
           ;; in a later file of its system and in another system are compiled
           ;; again, and each warns; the forms over the other sets do not.
           (change-case-build-file directory "parcel.lisp" "\"packed\" \"sent\"))))"
                                   "\"packed\" \"sent\" \"lost\"))))")
           (multiple-value-bind (code warnings) (run-case-build directory)
             (is (eql 2 code))
             (is (= 3 (length warnings)) "~{~a~^~%~}" warnings)
             (is (warning-about-p warnings "parcel.lisp:" "has no branch for \"lost\"")
                 "the same file: ~{~a~^~%~}" warnings)
             (is (warning-about-p warnings "labels.lisp:" "has no branch for \"lost\"")
                 "a later file of the same system")
             (is (warning-about-p warnings "users.lisp:" "has no branch for \"lost\"")
                 "another system"))
           ;; A kind added to crate's set in a system without :serial t: ASDF
           ;; does not compile its second file again, and loading it warns.
           (change-case-build-file directory "kinds.lisp" "\"small\" \"large\"))))"
                                   "\"small\" \"large\" \"huge\"))))")
           (multiple-value-bind (code warnings) (run-case-build directory)
             (is (eql 2 code))
             (is (= 1 (length warnings)) "~{~a~^~%~}" warnings)
             (is (warning-about-p warnings "ecase-of (crate kind) at" "kind-labels.lisp:"
                                  "was compiled against another set; compile it again"
                                  "now small, large, huge")
                 "~{~a~^~%~}" warnings)))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

;;; ------------------------------------------------------------------
;;; The cases guard

(defparameter +planted-cases+
  ";;;; planted.lisp -- forms over the orders module's statuses.
(in-package #:tun.orders)

(defun planted-ecase (order)
  (ecase (order-status order) (:draft 1)))

(defun planted-case (order)
  (case (order-status order) (t 1)))

(defun planted-cond (status)
  (cond ((string= status \"draft\") 1)
        ((equal \"cancelled\" status) 2)
        (t 3)))

(defun left-alone (order status)
  (list (ecase-of (order status) status
          (\"draft\" 1) ((\"quote_sent\" \"accepted\" \"confirmed\" \"picked_up\" \"returned\"
                        \"ready_for_invoice\" \"completed\" \"cancelled\") 2))
        (case-of (order status) status (\"draft\" 1) (otherwise 2))
        (when (string= (order-status order) \"draft\") 1)
        (member status '(\"draft\" \"cancelled\") :test #'string=)
        (cond ((string= status \"draft\") 1) (t 2))
        (cond ((string= status \"apple\") 1) ((string= status \"pear\") 2))))
")

(test the-guard-finds-a-plain-case-analysis-over-a-declared-set
  (let ((findings (plain-case-findings-in-text +planted-cases+ :source "planted.lisp")))
    (is (= 3 (length findings)) "~{~a~^~%~}" findings)
    (is (warning-about-p findings "planted.lisp:4 (defun planted-ecase)"
                         "ecase on (order-status order), the field (order status)"
                         "write it with ecase-of or case-of"))
    (is (warning-about-p findings "planted.lisp:7 (defun planted-case)" "case on"))
    (is (warning-about-p findings "planted.lisp:10 (defun planted-cond)"
                         "a cond comparing status with \"draft\", \"cancelled\""
                         "(order status)"))))

(defun tun-source-files ()
  "Every Lisp source of Tun's kernel and modules, but tests and the
templates `tun new' writes."
  (let ((root (asdf:system-source-directory "tun")))
    (remove-if (lambda (file)
                 (let ((name (enough-namestring file root)))
                   (or (search "/tests/" name)
                       (string-prefix-p "src/cli/template/" name))))
               (append (directory (merge-pathnames "src/**/*.lisp" root))
                       (directory (merge-pathnames "modules/**/*.lisp" root))))))

(test tuns-own-code-switches-over-declared-sets-with-ecase-of
  (let ((findings (plain-case-findings (tun-source-files)
                                       :root (asdf:system-source-directory "tun"))))
    (is (null findings) "~{~a~^~%~}" findings)))
