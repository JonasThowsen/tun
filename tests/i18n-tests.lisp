;;;; tests/i18n-tests.lisp -- languages, copy, money and time per tenant
;;;; (spec/i18n.md 2, 3, 5, 6, 7, 9).

(in-package #:tun.tests)

(def-suite i18n :in core)
(in-suite i18n)

(defun nbsp (text)
  "TEXT with each space a no-break space, as Norwegian amounts are written."
  (substitute #\No-break_space #\Space text))

;;; ------------------------------------------------------------------
;;; What a client declares (2.2), and the settings (2.3, 5.3, 9)

(test the-locale-option-is-checked-when-compiled
  (dolist (form '((define-application bad-locale () (:locale :languages ("de")))
                  (define-application bad-locale () (:locale :languages ("en" "en")))
                  (define-application bad-locale () (:locale :languages ("en") :source-language "nb"))
                  (define-application bad-locale () (:locale :currency "XYZ"))
                  (define-application bad-locale () (:locale :time-zone "Mars/Base"))
                  (define-application bad-locale () (:locale :colour "blue"))))
    (signals error (macroexpand-1 form) "~s is refused" form)))

(test without-the-option-a-tenant-is-english-in-euros-and-utc
  (with-test-app ()
    (let ((locale (default-locale *app*)))
      (is (equal "en" (locale-language locale)))
      (is (equal "EUR" (locale-currency locale)))
      (is (equal "UTC" (locale-time-zone locale))))
    (let ((items (jget (call-ok "settings_list" "admin:ada") "items")))
      (is (equal "en" (jget (find-by "key" "locale.language" items) "value")))
      (is (equal "EUR" (jget (find-by "key" "locale.currency" items) "value")))
      (is (equal "UTC" (jget (find-by "key" "locale.time_zone" items) "value"))))))

(test the-locale-settings-take-only-what-tun-knows
  (with-test-app ()
    (dolist (case '(("locale.language" "de") ("locale.currency" "XYZ")
                    ("locale.time_zone" "Mars/Base") ("locale.language" 3)))
      (is (equal "invalid_input"
                 (nth-value 1 (call "settings_set" "admin:ada" "key" (first case) "value" (second case))))
          "~s is refused" case))
    (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "nb")
    (call-ok "settings_set" "admin:ada" "key" "locale.time_zone" "value" "Europe/Helsinki")
    (with-application (*app*)
      (let ((locale (read-tenant-locale)))
        (is (equal "nb" (locale-language locale)))
        (is (equal "Europe/Helsinki" (locale-time-zone locale)))))))

(test the-currency-is-fixed-while-amounts-are-stored
  (with-test-app ()
    (call-ok "settings_set" "admin:ada" "key" "locale.currency" "value" "NOK")
    (call-ok "products_create" "admin:ada" "name" "Telt" "kind" "rental" "unit" "pcs"
             "unit_price_minor" 120000 "stock_tracked" nil "units_owned" 1)
    (is (equal "conflict" (nth-value 1 (call "settings_set" "admin:ada" "key" "locale.currency"
                                             "value" "SEK"))))
    (call-ok "settings_set" "admin:ada" "key" "locale.currency" "value" "NOK")))

;;; ------------------------------------------------------------------
;;; Copy and catalogues (3.1 to 3.3)

(test tr-takes-only-a-literal-text
  (signals error (macroexpand-1 '(tr some-variable)))
  (signals error (macroexpand-1 '(tr ("Open" :kontekst "verb"))))
  (signals error (macroexpand-1 '(deferred-tr (concatenate 'string "a" "b")))))

(test a-broken-translation-fails-when-compiled
  (signals error (macroexpand-1 '(define-translations "nb" ("~d files" "~d fil~q"))))
  (signals error (macroexpand-1 '(define-translations "de" ("Save" "Speichern"))))
  (signals error (macroexpand-1 '(define-translations "nb" ("Save" lagre)))))

(test two-owners-translating-one-text-differently-are-refused
  (register-translations "nb" "tests-a" '(("A text only a test has" nil "Én tekst")))
  (signals error (register-translations "nb" "tests-b" '(("A text only a test has" nil "En annen"))))
  (register-translations "nb" "tests-b" '(("A text only a test has" nil "Én tekst")))
  (is (equal "Én tekst" (with-language ("nb") (translate "A text only a test has")))))

(test a-text-is-shown-in-the-current-language-else-as-written
  (register-translations "nb" "tests" '(("Rows of ~d" nil "Rader av ~d")))
  (is (equal "Rader av 3" (with-language ("nb") (tr "Rows of ~d" 3))))
  (is (equal "Rows of 3" (with-language ("en") (tr "Rows of ~d" 3))))
  (is (equal "Not in any catalogue" (with-language ("nb") (translate "Not in any catalogue"))))
  (is (equal "⟦Rows of 3⟧" (with-language ("qps") (tr "Rows of ~d" 3))))
  (is (equal "nb" (with-language ("nb") (current-language)))))

(test a-refusal-is-written-where-it-is-shown
  (register-translations "nb" "tests" '(("The ~a is ~a and cannot go on" nil "~a er ~a og kan ikke fortsette")
                                        ("Half done" nil "Halvferdig")
                                        ("Half done" "test_widget.state" "Halvveis")))
  (handler-case (fail :invalid-transition "The ~a is ~a and cannot go on" "order"
                      (label "test_widget" "state" "half_done"))
    (operation-error (e)
      (is (equal "The order is Half done and cannot go on"
                 (with-language (:source) (operation-error-message e))))
      (is (equal "order er Halvveis og kan ikke fortsette"
                 (with-language ("nb") (operation-error-message e))))
      (is (equal "The order is Half done and cannot go on"
                 (jget (jget (with-language (:source) (operation-error-json e)) "error") "message")))))
  (is (equal "Halvferdig" (with-language ("nb") (render-text (label "other" "state" "half_done"))))
      "without its context's entry, a label has the plain one"))

;;; An entity whose stored value has no label in any catalogue, which
;;; UNTRANSLATED-AND-UNUSED-TEXTS-ARE-FOUND looks for.
(define-entity i18n-probe (:label "Probe" :id-prefix "ipr" :table "test_i18n_probes")
  ((state :type (enum "unheard_of") :initform "unheard_of" :label "State")))

(test untranslated-and-unused-texts-are-found
  (register-translations "nb" "tests" '(("An entry nothing uses" nil "Ingen bruker denne")))
  (note-text "A text the code writes and no catalogue has" nil "tests" "TESTS:i18n-tests.lisp")
  (with-test-app ()
    (is (find "A text the code writes and no catalogue has" (untranslated-texts "nb" :owner "tests")
              :key #'first :test #'equal))
    (let ((label (find "Unheard of" (untranslated-texts "nb") :key #'first :test #'equal)))
      (is (equal (list "Unheard of" "i18n_probe.state"
                       (entity-module (find-class 'i18n-probe)) "i18n_probe.state")
                 label)
          "an enum value with no label is found in its field's context, with its owner and place: ~s"
          label)
      (is (stringp (third label)) "its owner is named"))
    (is (find "An entry nothing uses" (unused-translations "nb" :owner "tests")
              :key #'first :test #'equal))
    (is (find "Tr writes this text" (untranslated-texts "nb" :owner "core") :key #'first
              :test #'equal)
        "TR notes its text where it is compiled")))

(defun writes-a-text-for-the-check ()
  "A TR with no Norwegian, which UNTRANSLATED-AND-UNUSED-TEXTS-ARE-FOUND looks for."
  (tr "Tr writes this text"))

(test core-and-every-module-have-every-text-in-norwegian
  (with-test-app ()
    (let* ((owners (cons "core" (mapcar #'module-name (all-modules))))
           (missing (remove-if-not (lambda (text) (member (third text) owners :test #'equal))
                                   (untranslated-texts "nb" :exclude-packages '("TUN.TESTS"))))
           (unused (unused-translations "nb" :owners owners)))
      (is (null missing) "~d texts lack Norwegian, such as ~{~s~^, ~}"
          (length missing) (subseq missing 0 (min 10 (length missing))))
      (is (null unused) "~d Norwegian entries are not used, such as ~{~s~^, ~}"
          (length unused) (subseq unused 0 (min 10 (length unused)))))))

;;; ------------------------------------------------------------------
;;; Money (5.2, 5.4)

(test a-money-field-must-be-named-minor
  (signals error (macroexpand-1 '(define-entity bad-money (:id-prefix "bm") ((total :type money)))))
  (signals error (macroexpand-1 '(define-operation bad-money-op ((fee :type money)) (:kind :read)
                                  nil)))
  (finishes (macroexpand-1 '(define-entity good-money (:id-prefix "gm")
                             ((total-minor :type money))))))

(test amounts-are-written-in-the-tenants-language
  (flet ((en (amount currency) (with-language ("en") (money-text amount :currency currency)))
         (nb (amount currency) (with-language ("nb") (money-text amount :currency currency))))
    (is (equal "€12,450.00" (en 1245000 "EUR")))
    (is (equal (nbsp "NOK 12,450.00") (en 1245000 "NOK")))
    (is (equal (nbsp "ISK 12,450") (en 12450 "ISK")))
    (is (equal "-€5.00" (en -500 "EUR")))
    (is (equal "£0.29" (en 29 "GBP")))
    (is (equal "US$1.00" (en 100 "USD")))
    (is (equal (nbsp "12 450,00 kr") (nb 1245000 "NOK")))
    (is (equal (nbsp "12 450,00 €") (nb 1245000 "EUR")))
    (is (equal (nbsp "12 450 ISK") (nb 12450 "ISK")))
    (is (equal (nbsp "−5,00 kr") (nb -500 "NOK")))
    (is (equal (nbsp "1 234 567,89 SEK") (nb 123456789 "SEK")))
    (dolist (currency (mapcar #'first +currencies+))
      (is (stringp (en 1 currency)))
      (is (stringp (nb 1 currency))))))

(test amounts-are-read-as-people-write-them-with-integers
  (flet ((read-in (language text &optional (currency "NOK"))
           (values (read-money-text text :currency currency :language language))))
    (loop for (text expected) in '(("12,450.50" 1245050) ("12450.50" 1245050) ("0.29" 29)
                                   ("12 450.50" 1245050) ("-5.00" -500))
          do (is (eql expected (read-in "en" text)) "en ~s" text))
    (loop for (text expected) in `(("12 450,50" 1245050) ("12450,50" 1245050) ("12450.50" 1245050)
                                   ("0,29" 29) (,(nbsp "12 450,50") 1245050) ("−5,00" -500))
          do (is (eql expected (read-in "nb" text)) "nb ~s" text))
    (dolist (text '("12,50" "1,2345.00" "12.450.50" "1.2.3" "1.234" "12a" "" "1,00.0"))
      (is (null (read-in "en" text)) "en ~s is refused" text))
    (dolist (text '("12 450,505" "1 23,00" "12,450,50" "1.2,3" "12,5,0"))
      (is (null (read-in "nb" text)) "nb ~s is refused" text))
    (is (null (read-in "en" "12.5" "ISK")) "no decimals in ISK")
    (is (eql 12 (read-in "en" "12" "ISK")))
    (is (null (read-in "en" "90071992547409.92")) "beyond 2^53 - 1 minor units")
    (is (eql 9007199254740991 (read-in "en" "90071992547409.91")))))

;;; ------------------------------------------------------------------
;;; Dates, times and numbers (6.1, 6.2)

(test dates-instants-and-numbers-in-both-languages
  (flet ((both (function value)
           (list (with-language ("en") (funcall function value))
                 (with-language ("nb") (funcall function value)))))
    (is (equal '("21 Oct 2026" "21.10.2026") (both #'date-text "2026-10-21")))
    (is (equal '("12.5" "12,5") (both #'number-text 25/2)))
    (is (equal '("Yes" "Ja") (both #'yes-no-text t)))
    (is (equal '("No" "Nei") (both #'yes-no-text nil)))
    (let ((*locale* (make-locale :language "en" :time-zone "Europe/Oslo")))
      (is (equal '("21 Oct 2026, 14:32" "21.10.2026 kl. 14:32")
                 (both #'timestamp-text "2026-10-21T12:32:00Z"))
          "an instant in the tenant's zone"))))

(test every-zone-has-its-offsets-in-winter-and-summer
  (let ((winter (parse-rfc3339 "2026-01-15T12:00:00Z"))
        (summer (parse-rfc3339 "2026-07-15T12:00:00Z")))
    (dolist (zone +time-zones+)
      (destructuring-bind (name standard summer-p) zone
        (is (= standard (zone-offset winter name)) "~a in winter" name)
        (is (= (if summer-p (+ standard 3600) standard) (zone-offset summer name)) "~a in summer" name)))))

(test local-times-in-several-zones
  (flet ((utc (date hour minute zone)
           (multiple-value-bind (instant kind) (local-instant date hour minute zone)
             (if instant (format-rfc3339 instant) kind))))
    ;; core.md 2.2's pinned examples, in Europe/Oslo.
    (is (equal "2026-01-15T08:00:00Z" (utc "2026-01-15" 9 0 "Europe/Oslo")))
    (is (equal "2026-07-15T07:00:00Z" (utc "2026-07-15" 9 0 "Europe/Oslo")))
    (is (eq :nonexistent (utc "2026-03-29" 2 30 "Europe/Oslo")))
    (is (equal "2026-03-29T00:59:00Z" (utc "2026-03-29" 1 59 "Europe/Oslo")))
    (is (equal "2026-03-29T01:00:00Z" (utc "2026-03-29" 3 0 "Europe/Oslo")))
    (is (eq :ambiguous (utc "2026-10-25" 2 30 "Europe/Oslo")))
    (is (equal "2026-10-25T02:00:00Z" (utc "2026-10-25" 3 0 "Europe/Oslo")))
    ;; Their like an hour to each side, and a zone without summer time.
    (is (equal "2026-07-15T08:00:00Z" (utc "2026-07-15" 9 0 "Europe/London")))
    (is (eq :nonexistent (utc "2026-03-29" 1 30 "Europe/London")))
    (is (eq :ambiguous (utc "2026-10-25" 1 30 "Europe/London")))
    (is (equal "2026-07-15T06:00:00Z" (utc "2026-07-15" 9 0 "Europe/Helsinki")))
    (is (eq :nonexistent (utc "2026-03-29" 3 30 "Europe/Helsinki")))
    (is (equal "2026-07-15T09:00:00Z" (utc "2026-07-15" 9 0 "Atlantic/Reykjavik")))
    (is (equal "2026-03-29T02:30:00Z" (utc "2026-03-29" 2 30 "Atlantic/Reykjavik")))
    (let ((*locale* (make-locale :time-zone "Europe/Helsinki")))
      (is (equal "2026-06-30" (local-date-of (parse-rfc3339 "2026-06-29T21:30:00Z")))
          "today is the tenant's local date"))))

;;; ------------------------------------------------------------------
;;; Machines read source text; people read the tenant's language (3.5, 7)

(test machines-get-source-text-and-pages-the-tenants-language
  (with-test-server (port)
    (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "nb")
    (multiple-value-bind (json error) (http-tool-call port "admin:ada" "settings_set"
                                                      (jobj "key" "no.such.setting" "value" 1))
      (is (eq t error))
      (is (equal "The setting no.such.setting is not declared"
                 (jget (jget json "error") "message"))
          "over MCP, source text on a Norwegian tenant"))
    (let ((jar (web-login port "admin:ada")))
      (multiple-value-bind (status body)
          (web-request port "/settings" :method :post :jar jar
                                        :parameters '(("key" . "no.such.setting") ("value" . "1")))
        (declare (ignore status))
        (is (search "Innstillingen no.such.setting er ikke deklarert" body)
            "on a page, the tenant's language")
        (is (search "lang=\"nb\"" body) "the page says its language")))))

(test machines-read-no-translated-text
  ;; On a tenant in the pseudo-language, any text looked up for people is
  ;; written ⟦…⟧: what machines read holds none.
  (with-test-server (port)
    (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "qps")
    (flet ((mcp (method &optional params)
             (nth-value 1 (http-post port "/mcp"
                                     (to-json-string (apply #'jobj "jsonrpc" "2.0" "id" 1
                                                            "method" method
                                                            (and params (list "params" params))))
                                     :actor "admin:ada")))
           (api (tool arguments)
             (multiple-value-list (http-post port (format nil "/api/~a" tool)
                                             (to-json-string arguments) :actor "admin:ada"))))
      (let ((answers
              (list (list "tools/list" (mcp "tools/list"))
                    (list "registry_describe over MCP"
                          (mcp "tools/call" (jobj "name" "registry_describe" "arguments" (jobj))))
                    (list "an error document over MCP"
                          (mcp "tools/call" (jobj "name" "settings_set"
                                                  "arguments" (jobj "key" "no.such.setting"
                                                                    "value" 1))))
                    (list "registry_describe over /api" (api "registry_describe" (jobj)))
                    (list "an error document over /api"
                          (api "settings_set" (jobj "key" "no.such.setting" "value" 1))))))
        (destructuring-bind (status body &rest headers) (second (fourth answers))
          (declare (ignore headers))
          (is (= 200 status) "/api answers: ~a ~a" status body))
        (destructuring-bind (status body &rest headers) (second (fifth answers))
          (declare (ignore headers))
          (is (<= 400 status 499) "/api refuses: ~a" status)
          (is (search "The setting no.such.setting is not declared" body) "in source text"))
        (loop for (what answer) in answers
              for body = (if (stringp answer) answer (second answer))
              do (is (plusp (length body)) "~a answers" what)
                 (is (not (search "⟦" body)) "~a holds no translated text: ~a" what
                     (let ((at (search "⟦" body)))
                       (and at (subseq body (max 0 (- at 60)) (min (length body) (+ at 60)))))))))))

;;; ------------------------------------------------------------------
;;; Pages write nothing they did not look up (3.7, the pseudo-language)

(test the-kernels-pages-look-up-every-text
  (with-test-server (port)
    (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "qps")
    (let ((admin (web-login port "admin:ada"))
          ;; The data the pages show as it is: records, settings and actors.
          (allowed (append (stored-strings) (data-codes)
                           (json-strings (call-ok "settings_list" "admin:ada"))
                           '("admin:ada" "viewer:vera" "/login?actor=role:name"))))
      ;; The specimen at /ui is developer documentation, in English
      ;; (spec/i18n.md 3.6); its examples are checked in ui-tests.
      (dolist (path '("/settings" "/access" "/login" "/offline" "/no-such-page"))
        (let ((problems (pseudo-page-problems port path admin :allowed allowed)))
          (is (null problems) "~a writes ~s without a lookup" path problems)))
      (let ((problems (pseudo-page-problems port "/settings" (web-login port "viewer:vera")
                                            :allowed allowed)))
        (is (null problems) "the 403 page writes ~s without a lookup" problems)))))
