;;;; tests/mail-html-tests.lisp -- a mail's HTML built from nodes
;;;; (spec/mail.md 2.1): the allow-list, which refuses; links, images and
;;;; style; the frame; the text part made from the tree; render-mail; and
;;;; Resend receiving both parts.  The helpers of mail-tests.lisp are used.

(in-package #:tun.tests)

(def-suite mail-html :in core)
(in-suite mail-html)

(defvar *mail-tree* nil
  "The node tree MAIL-TEST-SEND-TREE sends: a tree cannot travel as JSON.")

(define-operation mail-test-send-tree ((text :type string) (subject :type string))
    (:kind :update :policy :employee :title "Send a mail of nodes (test)")
  (jobj "id" (entity-id (tun:send-mail :to "ola@example.no" :subject (or subject "Sammendrag")
                                       :text text :html *mail-tree*))))

(defun send-tree (tree &rest arguments)
  "Values the JSON and the error code of Kari sending TREE with ARGUMENTS."
  (let ((*mail-tree* tree))
    (apply #'call "mail_test_send_tree" "employee:kari" arguments)))

(defun error-fields (json)
  "The fields of the error document JSON, each as (FIELD MESSAGE)."
  (map 'list (lambda (field) (list (jget field "field") (jget field "message")))
       (jget (jget json "error") "fields")))

(defun mail-refusal (tree &rest arguments)
  "The message SEND-MAIL refuses TREE with, when it fails invalid_input on
html alone and stores no mail; else NIL."
  (multiple-value-bind (json code) (apply #'send-tree tree arguments)
    (let ((fields (and code (error-fields json))))
      (and (equal code "invalid_input")
           (= 1 (length fields))
           (equal "html" (first (first fields)))
           (zerop (length (jget (call-ok "mail_list" "admin:ada") "items")))
           (second (first fields))))))

(defun sends-p (tree &rest arguments)
  "True when Kari's sending TREE with ARGUMENTS succeeds."
  (null (nth-value 1 (apply #'send-tree tree arguments))))

(defun refused-because (tree)
  "True when RENDER-MAIL refuses TREE on html; NIL when it renders it."
  (with-application (*app*)
    (handler-case (progn (tun:render-mail tree) nil)
      (operation-error (e)
        (equal '("html") (mapcar #'first (error-fields (operation-error-json e))))))))

(defun render-refusal-fields (tree &rest keys)
  "The fields RENDER-MAIL refuses TREE with KEYS on, or NIL when it renders it."
  (with-application (*app*)
    (handler-case (progn (apply #'tun:render-mail tree keys) nil)
      (operation-error (e)
        (mapcar #'first (error-fields (operation-error-json e)))))))

(defun rendered (tree &rest keys)
  "Values the HTML and text RENDER-MAIL makes of TREE in *APP*."
  (with-application (*app*)
    (apply #'tun:render-mail tree keys)))

(defun rendered-html (tree)
  (nth-value 0 (rendered tree)))

(defun rendered-text (tree)
  (nth-value 1 (rendered tree)))

(defun stored-mail (tree &rest arguments)
  "The JSON of the mail stored for TREE, sent with ARGUMENTS."
  (mail-of (jget (let ((*mail-tree* tree))
                   (apply #'call-ok "mail_test_send_tree" "employee:kari" arguments))
                 "id")))

;;; ------------------------------------------------------------------
;;; Escaping and the allow-list

(test strings-in-a-tree-are-escaped
  (with-mail (provider)
    (let* ((tree '(:p "<script>alert(1)</script> Tom & \"Jerry\" og 'Kari'"))
           (html (jget (stored-mail tree) "html")))
      (is (search (concatenate 'string "<p>&lt;script&gt;alert(1)&lt;/script&gt; "
                               "Tom &amp; &quot;Jerry&quot; og &#39;Kari&#39;</p>")
                  html))
      (is (not (search "<script" html)))
      (is (equal html (rendered tree :subject "Sammendrag"))
          "render-mail renders what send-mail stores"))))

(test elements-outside-the-allow-list-are-refused
  (with-mail (provider)
    (dolist (tag '(:script :style :form :iframe :input :b :object :svg :link :meta))
      (is (search (format nil "<~(~a~)>" tag) (or (mail-refusal `(:div (,tag "x"))) ""))
          "<~(~a~)> is refused, by name" tag))
    (is (sends-p '((:h1 "a") (:h2 "b") (:h3 "c") (:p (:strong "d") (:em "e") (:br) (:span "f"))
                         (:hr) (:ul (:li "g")) (:ol (:li "h")) (:div "i")
                         (:table (:caption "j") (:thead (:tr (:th "k"))) (:tbody (:tr (:td "l")))
                                 (:tfoot (:tr (:td "m"))))
                         (:img (:@ :src "https://example.no/a.png" :alt "n"))))
        "every element of the list is sent")))

(test attributes-outside-the-allow-list-are-refused
  (with-mail (provider)
    (flet ((refused-p (tree name)
             (search name (or (mail-refusal tree) ""))))
      (is (refused-p '(:a (:@ :href "https://example.no" :onclick "alert(1)") "x") "onclick"))
      (is (refused-p '(:p (:@ :class "big") "x") "class"))
      (is (refused-p '(:p (:@ :id "x") "x") "id"))
      (is (refused-p '(:p (:@ :data-x "1") "x") "data-x"))
      (is (refused-p '(:div (:@ :srcdoc "<script></script>") "x") "srcdoc"))
      (is (refused-p '(:p (:@ :href "https://example.no") "x") "href") "href only on a")
      (is (refused-p '(:a (:@ :src "https://example.no/a.png") "x") "src") "src only on img")
      (is (refused-p '(:p (:@ :colspan 2) "x") "colspan")))
    (is (sends-p '(:table (:tr (:td (:@ :colspan 2 :rowspan "1" :scope "row" :title "t"
                                        :lang "no" :dir "ltr" :style "color: red")
                                     "x")))))
    (is (search " colspan=\"2\"" (rendered-html '(:table (:tr (:td (:@ :colspan 2) "x")))))
        "a number is written as text")
    (is (not (search " title=" (rendered-html '(:p (:@ :title nil) "x"))))
        "an attribute whose value is NIL is left out")))

(test what-is-outside-the-node-grammar-is-refused-not-an-internal-error
  (with-mail (provider)
    (is (search "a text or a number" (mail-refusal '(:a (:@ :href t) "x"))) "a value T")
    (is (mail-refusal '(:p (:@ :title #\x) "x")) "a character as a value")
    (is (search "keyword" (mail-refusal '(:p (:@ "title" "x") "x"))) "a name that is a string")
    (is (mail-refusal '(:p (:@ title "x") "x")) "a name that is a symbol")
    (is (mail-refusal '(:p (:@ :title) "x")) "an odd (:@ ...)")
    (is (search "right after the tag" (mail-refusal '(:p "x" (:@ :title "y"))))
        "(:@ ...) after a child")
    (is (mail-refusal '(:p sym)) "a symbol")
    (is (mail-refusal '(:p :strong)) "a keyword not at the head of an element")
    (is (mail-refusal '(:p #\x)) "a character")
    (is (mail-refusal (list :p #(1 2))) "a vector")
    (is (mail-refusal '(:p "a" . "b")) "an improper element")
    (is (mail-refusal '((:p "a") . "b")) "an improper list of nodes")
    (is (mail-refusal (list :p (tun.html:trusted "<script>alert(1)</script>")))
        "core's trusted markup")
    (is (mail-refusal (list :p (tun.html:untrusted '(:script "x")))) "an untrusted wrapper")))

(defun nested (depth)
  "A tree of DEPTH divs, one in another, around a word."
  (let ((tree "x"))
    (dotimes (i depth tree)
      (setf tree (list :div tree)))))

(test a-circular-or-too-deep-tree-is-refused
  (with-mail (provider)
    (let ((circular (list :p "a" "b")))
      (setf (cdr (last circular)) (cdr circular))
      (is (mail-refusal circular) "an element whose children go round"))
    (let ((circular (list "a" "b")))
      (setf (cdr (last circular)) circular)
      (is (mail-refusal (list :p circular)) "a list of nodes that goes round"))
    (let ((inside (list :div "a")))
      (setf (cdr (last inside)) (list inside))
      (is (search "deeper than 200" (or (mail-refusal inside) "")) "an element inside itself"))
    (let ((attributes (list :title "a")))
      (setf (cdr (last attributes)) attributes)
      (is (mail-refusal (list :p (cons :@ attributes) "x")) "attributes that go round"))
    (is (search "deeper than 200" (or (mail-refusal (nested 300)) "")))
    (is (sends-p (nested 150)) "150 levels are sent")))

(test a-string-as-the-whole-html-is-refused
  (with-mail (provider)
    (is (search "not text with HTML" (mail-refusal "<p>Hei</p>" "text" "Hei")))
    (is (search "not text with HTML" (mail-refusal "Hei" "text" "Hei")))
    (is (sends-p '("Hei")) "a list holding a string is a tree")))

;;; ------------------------------------------------------------------
;;; Links and images

(test links-must-be-whole-or-a-path
  (with-mail (provider)
    (dolist (href '("javascript:alert(1)" "JavaScript:alert(1)" "data:text/html,x" "//evil.example"
                    "/\\evil.example" "saker/1" "#del" "" "ftp://example.no" "vbscript:x"))
      (is (mail-refusal `(:a (:@ :href ,href) "x")) "~s is refused" href))
    (dolist (href '(" javascript:alert(1)" " https://example.no" "https://example.no/a b"
                    "https://example.no/	" "https://exa\\mple.no" "/sak
er"))
      (is (search "spaces, control characters" (or (mail-refusal `(:a (:@ :href ,href) "x")) ""))
          "~s is refused for its spaces or controls" href))
    (is (mail-refusal `(:a (:@ :href ,(format nil "java~cscript:alert(1)" (code-char 0))) "x")))
    (is (mail-refusal `(:a (:@ :href ,(format nil "~chttps://example.no" (code-char 160))) "x"))))
  (with-test-app ()
    (dolist (href '("https://example.no/a?b=1&c=2" "HTTPS://EXAMPLE.NO" "http://example.no"
                    "mailto:kari@example.no" "MAILTO:kari@example.no"))
      (is (search (format nil "href=\"~a\"" (tun.html:escape-html href))
                  (rendered-html `(:a (:@ :href ,href) "x")))
          "~s is written as given" href))
    (is (search "href=\"/saker/1\"" (rendered-html '(:a (:@ :href "/saker/1") "x")))
        "a path stays a path without a public URL")
    ;; Schemes are compared as ASCII: ſ, whose capital is S, is not an s.
    (is (refused-because `(:a (:@ :href ,(format nil "http~c://example.no" (code-char #x17F)))
                              "x"))))
  (with-test-app (:public-url "https://saker.example.no")
    (is (search "href=\"https://saker.example.no/saker/1\""
                (rendered-html '(:a (:@ :href "/saker/1") "x")))
        "a path is made whole with the public URL")
    (is (search "(https://saker.example.no/saker/1)"
                (rendered-text '(:p (:a (:@ :href "/saker/1") "Sak 1"))))
        "and so in the text")))

(test images-take-https-only
  (with-test-app ()
    (dolist (src '("http://example.no/a.png" "/icons/a.png" "data:image/png;base64,AAAA"
                   "//example.no/a.png" " https://example.no/a.png" "javascript:x"))
      (is (refused-because `(:img (:@ :src ,src))) "~s is refused" src))
    (is (search "src=\"HTTPS://example.no/a.png\""
                (rendered-html
                 '(:p "x" (:img (:@ :src "HTTPS://example.no/a.png" :alt "logo"))))))))

;;; ------------------------------------------------------------------
;;; Style

(test style-takes-safe-properties-and-values-only
  (with-test-app ()
    (dolist (style '("position: fixed" "background: url(https://example.no/x.png)"
                     "color: expression(alert(1))" "color: red !important"
                     "font-family: \"Comic Sans\"" "color: \\72 ed" "color: rød"
                     "color" "width: calc(100% - 2px)" "behavior: url(x.htc)"
                     "color: red; position: absolute" "-moz-binding: url(x)" "color:"))
      (is (refused-because `(:p (:@ :style ,style) "x")) "~s is refused" style))
    (is (refused-because `(:p (:@ :style ,(format nil "bac~cground-color: red" (code-char #x212A)))
                              "x"))
        "a property name folds no non-ASCII letter")
    (is (search "<p style=\"color: #333; font-weight: bold; background-color: rgba(0, 0, 0, 0.1)\">"
                (rendered-html '(:p (:@ :style " COLOR:#333 ;; Font-Weight : bold;
background-color: rgba(0, 0, 0, 0.1);") "x")))
        "written again as checked, the names in lower case")
    (is (search (concatenate 'string "<h1 style=\"font-size: 24px; line-height: 1.25; "
                             "margin: 0 0 16px; font-size: 30px\">")
                (rendered-html '(:h1 (:@ :style "font-size: 30px") "x")))
        "after the element's default, so it wins")))

;;; ------------------------------------------------------------------
;;; The frame

(test the-frame-is-a-whole-document-without-anything-external
  (with-test-app ()
    (let ((html (nth-value 0 (rendered '(:p "Hei") :subject "Sammendrag for i dag"))))
      (is (eql 0 (search "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" html)))
      (is (search "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" html))
      (is (search "<title>Sammendrag for i dag</title>" html))
      (is (search "max-width: 600px" html))
      (is (search "font-size: 16px" html))
      (dolist (absent '("<link" "<style" "<script" "url(" "http://" "https://" "@import"))
        (is (not (search absent html)) "no ~a" absent))
      (is (search "<p>Hei</p>" html) "a paragraph has no default style"))
    (let ((html (nth-value 0 (rendered '(:p "Hei")
                                       :subject "</title><img src=x onerror=alert(1)>"))))
      (is (search "<title>&lt;/title&gt;&lt;img src=x onerror=alert(1)&gt;</title>" html)
          "the subject is escaped in the title")
      (is (not (search "<img" html))))))

;; spec/i18n.md 8: the frame carries the code of the language the mail is
;; written in, the tenant's.
(test the-frames-lang-is-the-tenants-language
  (with-test-app ()
    (let ((*mail-tree* '(:p "Hei")))
      (call-ok "mail_test_send_tree" "employee:kari")
      (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "nb")
      (call-ok "mail_test_send_tree" "employee:kari"))
    (destructuring-bind (norwegian english)
        (mapcar (lambda (mail) (jget (call-ok "mail_get" "admin:ada" "id" (jget mail "id")) "html"))
                (coerce (jget (call-ok "mail_list" "admin:ada") "items") 'list))
      (is (search "<html lang=\"nb\">" norwegian) "the newest, on a Norwegian tenant")
      (is (search "<html lang=\"en\">" english) "the first, on an English one"))))

;;; ------------------------------------------------------------------
;;; The text part

(test the-text-part-is-made-from-the-tree
  (with-test-app (:public-url "https://saker.example.no")
    (is (equal (format nil "Sammendrag~%~%To nye saker:~%~%- Eksport til regnskap ~
                            (https://saker.example.no/saker/1)~%- https://example.no/x~%~
                            - Kari (kari@example.no)~%  - under~%  - og under~%~%~
                            1. første~%2. andre~%~%En linje~%og en til~%~%---~%~%~
                            Sak | Status~%Eksport | Ny~%~%Ferdig.")
               (rendered-text
                '((:h1 "Sammendrag")
                  (:p "To   nye
                       " "saker:")
                  (:ul (:li (:a (:@ :href "/saker/1") "Eksport til " (:strong "regnskap")))
                       (:li (:a (:@ :href "https://example.no/x") "https://example.no/x"))
                       (:li (:a (:@ :href "mailto:kari@example.no") "Kari")
                            (:ul (:li "under") (:li "og under"))))
                  (:ol (:li "første") (:li "andre"))
                  (:p "En linje" (:br) "og en til")
                  (:hr)
                  (:table (:tr (:th "Sak") (:th "Status")) (:tr (:td "Eksport") (:td "Ny")))
                  (:p (:img (:@ :src "https://example.no/a.png")) "Ferdig.")))))
    (is (equal "kari@example.no" (rendered-text '(:a (:@ :href "mailto:kari@example.no")
                                                 "kari@example.no")))
        "a mailto link whose text is its address is the address")
    (is (equal "logo" (rendered-text '(:img (:@ :src "https://example.no/a.png" :alt "logo")))))
    (is (equal "Min egen tekst." (nth-value 1 (rendered '(:p "Hei") :text "Min egen tekst.")))
        "a text given is kept")))

(test the-text-part-is-checked-as-its-field
  (with-mail (provider)
    (flet ((fields (tree &rest arguments)
             (multiple-value-bind (json code) (apply #'send-tree tree arguments)
               (and (equal code "invalid_input") (mapcar #'first (error-fields json))))))
      (is (equal '("text") (fields '(:img (:@ :src "https://example.no/a.png"))))
          "an empty text made from the tree")
      (is (equal '("text") (fields (list :p (make-string 100001 :initial-element #\x)))))
      ;; Through render-mail: the test operation's own input would take a
      ;; blank text for none.
      (is (equal '("text")
                 (with-application (*app*)
                   (handler-case (progn (tun:render-mail '(:p "Hei") :text "   ") nil)
                     (operation-error (e)
                       (mapcar #'first (error-fields (operation-error-json e)))))))
          "a blank text is refused, not replaced")
      (is (equal '("html") (fields (list :p (make-string 100000 :initial-element #\&))
                                   "text" "kort"))
          "an HTML part over 500 000 characters")
      (is (equal '("html") (fields '(:script "x"))) "a refused tree is the one error"))))

;;; ------------------------------------------------------------------
;;; Sending

(test a-mail-from-a-tree-stores-both-parts
  (with-mail (provider)
    (let ((mail (stored-mail '((:h1 "Sammendrag") (:p "Hei, Ola.")) "subject" "Sammendrag")))
      (multiple-value-bind (html text) (rendered '((:h1 "Sammendrag") (:p "Hei, Ola."))
                                                 :subject "Sammendrag")
        (is (equal html (jget mail "html")))
        (is (equal text (jget mail "text")))
        (is (equal (format nil "Sammendrag~%~%Hei, Ola.") text))))))

(test render-mail-checks-its-subject-as-send-mail-does
  (with-test-app ()
    (is (equal '("subject") (render-refusal-fields '(:p "x")
                                                   :subject '((:title) (:script "alert(1)")))))
    (is (equal '("subject") (render-refusal-fields '(:p "x") :subject 42)))
    (flet ((subject (length) (make-string length :initial-element #\x)))
      (is (equal '("subject") (render-refusal-fields '(:p "x") :subject (subject 999))))
      (is (null (render-refusal-fields '(:p "x") :subject (subject 998)))))))

(test attribute-names-match-in-any-case
  (with-test-app ()
    (multiple-value-bind (html text)
        (rendered '((:a (:@ :|href| "https://example.no/x") "lenke")
                    (:p (:img (:@ :|src| "https://example.no/a.png" :|alt| "logo")))))
      (is (search "href=\"https://example.no/x\"" html))
      (is (search "alt=\"logo\"" html))
      (is (equal (format nil "lenke (https://example.no/x)~%~%logo") text)))))

(test render-mail-stores-nothing
  (with-mail (provider)
    (rendered '(:p "Hei"))
    (is (zerop (length (jget (call-ok "mail_list" "admin:ada") "items"))))
    (is (eq (find-symbol "RENDER-MAIL" "TUN") 'tun.mail:render-mail) "exported from TUN")
    (is (refused-because nil) "a tree is required")))

(test resend-receives-both-parts-of-a-mail-from-a-tree
  (with-fake-resend (resend)
    (let ((*mail-tree* '((:p "Hei, " (:a (:@ :href "https://example.no/saker/1") "sak 1")))))
      (call-ok "mail_test_send_tree" "employee:kari"))
    (is (= 1 (deliver)))
    (let ((body (getf (first (resend-requests resend)) :body)))
      (is (equal "Hei, sak 1 (https://example.no/saker/1)" (jget body "text")))
      (is (eql 0 (search "<!doctype html>" (jget body "html"))))
      (is (search (concatenate 'string "<a style=\"color: #1d4ed8; text-decoration: underline\" "
                               "href=\"https://example.no/saker/1\">sak 1</a>")
                  (jget body "html"))))))
