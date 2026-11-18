;;;; tests/pages.lisp -- what the showcase's server answers, as page tests
;;;; over HTTP (spec/testing.md 6): the steps of browser checks that only
;;;; read the server's answer, moved here from checks/ by the rule of
;;;; spec/preview.md 4, «What a browser check is for».  Each test names the
;;;; check it was, or the check that keeps the browser's part.

(in-package #:showcase.tests)

(def-suite showcase :description "The showcase's page tests.")
(in-suite showcase)

(defmacro with-showcase ((&rest options &key (scenario "default") &allow-other-keys) &body body)
  "Run BODY against the showcase holding SCENARIO's records, as
PAGE:WITH-SERVER with OPTIONS."
  `(page:with-server (:class 'showcase:showcase :scenario ,scenario
                             ,@(loop for (key value) on options by #'cddr
                                     unless (eq key :scenario) append (list key value)))
     ,@body))

(defun octets-start (octets)
  "The first five octets of OCTETS as text, as a file's magic reads."
  (map 'string #'code-char (subseq octets 0 (min 5 (length octets)))))

;;; ------------------------------------------------------------------
;;; Downloads and documents (were audited-download, pdf-download and
;;; pdf-document)

(defun export-customer (answer reason)
  "Send «Customer data»'s form of ANSWER for its second customer with
REASON; the answer and the customer's name."
  (let* ((form (page:form answer))
         (option (second (page:elements form "select[name=customer_id] option"))))
    (values (page:submit answer :button "Download the data"
                         :fields `(("customer_id" . ,(page:attribute option "value"))
                                   ("reason" . ,reason)))
            (page:text option))))

(test customer-data-is-downloaded-with-a-reason-and-audited
  (with-showcase (:actor "admin:jonas")
    (let ((page (page:visit "/customer-data")))
      (is (= 200 (page:status page)))
      (let ((refused (export-customer page "")))
        (is (= 422 (page:status refused)) "without a reason, the page again")
        (is (search "Reason" (format nil "~{~a~}" (page:alerts refused)))
            "an alert naming the reason")
        (is (null (page:header refused :content-disposition)) "and no file"))
      (multiple-value-bind (download name) (export-customer page "The customer asked for a copy")
        (let ((data (page:json download)))
          (is (= 200 (page:status download)))
          (is (search (format nil "filename=\"customer-~a.json\"" name)
                      (page:header download :content-disposition))
              "named after the customer")
          (is (equal name (tun:jget (tun:jget data "customer") "name")) "the customer's data")
          (let* ((log (page:element (page:visit "/audit") "[data-audit-log]"))
                 (first (page:text (page:element log "tbody tr")))
                 (customer (tun:jget data "customer")))
            (is (search "customer_data_export" first) "the export is the latest entry")
            (is (search "admin:jonas" first) "by the admin")
            (is (search (tun:jget customer "id") first) "naming the customer")
            (is (search "The customer asked for a copy" first) "with the reason")
            (is (not (search (tun:jget customer "email") (page:text log))))
            (is (not (search name (page:text log)))
                "nothing of the customer's data in the log")))))
    (is (= 403 (page:status (page:visit "/customer-data" :actor "employee:anna")))
        "an employee is refused the page")))

(test the-document-page-makes-its-pdf-and-links-to-it
  (with-showcase (:actor "employee:anna")
    (let* ((document (page:visit "/document"))
           (text (page:text (page:element document ".tun-code-block")))
           (before (length (page:elements document "[data-document-file]")))
           (made (page:submit document :button "Make the PDF")))
      (is (search "The board's estimate" text) "the document's title is in its text")
      (is (and (search "Export to accounting" text) (search " | " text))
          "its lines are the cards, their cells separated by « | »")
      (is (= 303 (page:status made)))
      (let* ((after (page:follow made))
             (links (page:elements after "[data-document-file]"))
             (href (page:attribute (first links) "href"))
             (file (page:visit href)))
        (is (= (1+ before) (length links)) "a link to the PDF made")
        (is (search "/files/fil_" href) "to its file")
        (is (search "board-estimate.pdf" (page:text (first links))) "named by its file")
        (is (= 200 (page:status file)))
        (is (equal "application/pdf" (page:content-type file)))
        (is (eql 0 (search "attachment" (page:header file :content-disposition)))
            "to be downloaded")
        (is (equal "%PDF-" (octets-start (page:body file))))))))

(test the-pdf-is-downloaded-made-on-the-spot-and-kept-nowhere
  (with-showcase (:actor "employee:anna")
    (let* ((document (page:visit "/document"))
           (made (length (page:elements document "[data-document-file]")))
           (link (page:element document "[data-document-download]"))
           (download (page:visit (page:attribute link "href"))))
      (is (not (null link)) "«Download the PDF» is shown")
      (is (= 200 (page:status download)))
      (is (equal "application/pdf" (page:content-type download)))
      (is (eql 0 (search "attachment; filename=\"board-estimate.pdf\""
                         (page:header download :content-disposition)))
          "a download, which leaves the browser on the page")
      (is (equal "nosniff" (page:header download :x-content-type-options)))
      (is (equal "no-store" (page:header download :cache-control)) "kept nowhere")
      (is (equal "%PDF-" (octets-start (page:body download))))
      (is (= made (length (page:elements (page:visit "/document") "[data-document-file]")))
          "no document was stored")
      (let ((refused (page:visit "/document/board-estimate.pdf" :actor "viewer:vera")))
        (is (= 403 (page:status refused)) "a viewer is refused it")
        (is (null (page:header refused :content-disposition)) "and gets no file")
        (is (not (equal "%PDF-" (octets-start (sb-ext:string-to-octets
                                               (let ((body (page:body refused)))
                                                 (if (stringp body) body ""))
                                               :external-format :utf-8)))))))))

;;; ------------------------------------------------------------------
;;; The mail's preview (was part of mail-preview, whose browser check
;;; keeps the text's size and the column's width)

(test the-mail-is-previewed-in-a-frame-that-allows-nothing
  (with-showcase (:actor "employee:anna")
    (let* ((page (page:visit "/mail"))
           (frame (page:element page "iframe[data-mail-preview]")))
      (is (equal "" (page:attribute frame "sandbox")) "the frame's sandbox allows nothing")
      (let* ((html (page:attribute frame "srcdoc"))
             (inside (page:read-html html))
             (links (page:links inside)))
        (is (equal "Summary from the board" (page:text (page:element inside "title")))
            "the subject is the mail's title")
        (is (null (page:elements inside "script, link, style")) "no script, link or style element")
        (is (>= (length links) 5) "each card listed is a link")
        (is (every (lambda (link) (eql 0 (search "/items" (cdr link)))) links)
            "to the cards, by their paths"))
      (let ((text (page:text (page:element page ".tun-code-block"))))
        (is (search "Summary from the board" text))
        (is (search "(/items/crd_" text) "the text part gives each link as «title (link)»")))))

;;; ------------------------------------------------------------------
;;; Signing in and public pages (were login-returns-to-the-page and
;;; public-page-title, whose browser check keeps the quote's widths)

(test signing-in-returns-to-the-page-that-was-opened
  (with-showcase (:actor nil)
    (let ((opened (page:visit "/items?view=list")))
      (is (= 303 (page:status opened)))
      (is (eql 0 (search "/login" (page:location opened))) "the page goes to the login")
      (let ((login (page:follow opened)))
        (is (equal "Sign in" (first (page:headings login))) "the login page itself")
        (is (not (search "not signed in" (page:text login))) "with no notice in between")
        (let* ((link (cdr (assoc "As an administrator" (page:links login) :test #'string=)))
               (signed-in (page:visit link)))
          (is (= 303 (page:status signed-in)))
          (is (equal "/items?view=list" (page:location signed-in))
              "after signing in, the page that was opened, with its query")
          (let ((home (page:visit "/")))
            (is (not (eql 0 (search "/login" (or (page:location home) ""))))
                "signed in, / is not the login")))))))

(defun frame-names (answer)
  "The frame's title, its mark and the document's title on ANSWER."
  (list (page:text (page:element answer ".tun-app-shell-name-text"))
        (page:text (page:element answer ".tun-app-shell-mark"))
        (page:title answer)))

(defun ends-with-p (suffix text)
  (and (>= (length text) (length suffix))
       (string= suffix text :start2 (- (length text) (length suffix)))))

(test a-public-page-shows-the-name-the-client-answers
  (with-showcase (:actor nil)
    (destructuring-bind (title mark tab) (frame-names (page:visit "/quote/q1"))
      (is (equal "Lindenhof Services" title) "the quote's frame is the company's")
      (is (equal "L" mark))
      (is (ends-with-p "– Lindenhof Services" tab) "and so is the tab's title"))
    (destructuring-bind (title mark tab) (frame-names (page:visit "/notice"))
      (is (equal "showcase" title) "a page the client passes on for is the application's")
      (is (equal "s" mark))
      (is (ends-with-p "– showcase" tab)))
    (destructuring-bind (title mark tab) (frame-names (page:visit "/items" :actor "employee:anna"))
      (declare (ignore mark))
      (is (equal "showcase" title) "a staff page keeps the application's title")
      (is (ends-with-p "– showcase" tab)))
    (is (equal "Lindenhof Services"
               (first (frame-names (page:visit "/quote/q1" :actor "employee:anna"))))
        "and the quote, opened signed in, the company's")))

;;; ------------------------------------------------------------------
;;; Posted sets (was posted-sets without JavaScript; its browser check
;;; keeps one round of htmx posting the ticked boxes)

(defun visit-days-shown (answer)
  "What «Visit days» on ANSWER shows as saved, and which boxes are ticked."
  (let ((saved (page:attribute (page:element answer "[data-saved-days]") "data-saved-days")))
    (list (if (stringp saved) (cl-ppcre:split " " saved) '())
          (page:form-values (page:form answer) "days"))))

(test visit-days-saves-every-box-ticked
  (with-showcase (:actor "employee:anna")
    (dolist (days '(("mon" "wed") ("tue" "thu" "fri") () ("mon" "wed")))
      (let ((saved (page:submit (page:visit "/visit-days") :fields `(("days" ,@days)))))
        (is (= 303 (page:status saved)))
        (destructuring-bind (shown ticked) (visit-days-shown (page:follow saved))
          (is (equal days shown) "~d ticked, ~:*~d saved: ~a" (length days) shown)
          (is (equal days ticked) "and ticked again when opened: ~a" ticked))))
    (is (equal "Saved: Monday, Wednesday."
               (page:text (page:element (page:visit "/visit-days") "[data-saved-days]"))))))

;;; ------------------------------------------------------------------
;;; Files without JavaScript (was files-without-javascript)

(defun showcase-path (name)
  (asdf:system-relative-pathname "showcase" (format nil "checks/files/~a" name)))

(test a-file-chosen-without-javascript-is-attached
  (with-showcase (:actor "employee:anna")
    (let* ((board (page:visit "/items"))
           (card (page:visit (cdr (assoc "Item 3" (page:links board) :test #'string=))))
           (form (page:form card "form[enctype='multipart/form-data']")))
      (is (not (null form)) "the card's page has a form that sends files")
      (is (page:attribute (page:element card "[data-tun-file-input-drop]") "hidden")
          "no promise of dragging and pasting without a script")
      (let ((sent (page:submit card :form "form[enctype='multipart/form-data']"
                               :button "Attach"
                               :fields `(("files" . ,(showcase-path "photo.jpg"))))))
        (is (= 303 (page:status sent)))
        (is (equal '("photo.jpg")
                   (mapcar #'page:text
                           (page:elements (page:follow sent) ".tun-attachments-caption")))
            "the file is attached")))))

;;; ------------------------------------------------------------------
;;; In Norwegian (spec/testing.md 6, :language)

(test the-pages-read-norwegian-on-a-norwegian-tenant
  (with-showcase (:actor "employee:anna" :language "nb")
    (let ((page (page:visit "/visit-days")))
      (is (equal "nb" (page:attribute (page:element page "html") "lang")))
      (is (equal "Ingen dager er lagret."
                 (page:text (page:element page "[data-saved-days]")))))))
