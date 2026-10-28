;;;; tests/ui-forms-tests.lisp -- the forms group of the design system: every
;;;; control is labelled, and its label, hint and error are tied to it
;;;; (spec/ui.md 5, GOV.UK's form behaviour).

(in-package #:tun.tests)

(def-suite ui-forms :in core)
(in-suite ui-forms)

(defun forms-html (markup)
  (tun.html:render-html markup))

(defun forms-attribute (html element attribute)
  "The value of ATTRIBUTE on the first ELEMENT (a tag name) in HTML that has it."
  (cl-ppcre:register-groups-bind (value)
      ((format nil "<~a\\b[^>]*\\s~a=\"([^\"]*)\"" element attribute) html)
    value))

(defun forms-in-order-p (html &rest needles)
  "True when every one of NEEDLES occurs in HTML, in this order."
  (let ((positions (mapcar (lambda (needle) (search needle html)) needles)))
    (and (every #'identity positions) (apply #'< positions))))

;;; ------------------------------------------------------------------
;;; Labels, hints and errors

(test a-label-names-its-control-by-id
  (let ((page (forms-html (tun.ui:text-input (:label "E-post" :name "epost")))))
    (let ((for (forms-attribute page "label" "for")))
      (is (stringp for) "the label has for=")
      (is (equal for (forms-attribute page "input" "id")) "for= is the input's own id")))
  (let ((page (forms-html (tun.ui:text-input (:label "E-post" :id "kunde-epost")))))
    (is (equal "kunde-epost" (forms-attribute page "label" "for")) "an :id given is used")
    (is (equal "kunde-epost" (forms-attribute page "input" "id"))))
  (flet ((fresh-id () (forms-attribute (forms-html (tun.ui:textarea (:label "Notat")))
                                       "textarea" "id")))
    (is (not (equal (fresh-id) (fresh-id))) "two controls made without :id get different ids")))

(test a-hint-and-an-error-describe-the-control
  (let ((page (forms-html (tun.ui:text-input (:label "E-post" :id "epost"
                                                     :hint "Fakturaen sendes hit."
                                                     :error "Skriv inn en e-postadresse")))))
    (is (equal "epost-hint epost-error" (forms-attribute page "input" "aria-describedby")))
    (is (equal "true" (forms-attribute page "input" "aria-invalid")))
    (is (search "id=\"epost-hint\"" page))
    (is (search "id=\"epost-error\"" page))
    (is (forms-in-order-p page "<label" "id=\"epost-hint\"" "id=\"epost-error\"" "<input")
        "GOV.UK's order: label, hint, error, then the control")
    (is (cl-ppcre:scan "<span class=\"tun-field-error-prefix\">Error:</span> Skriv inn" page)
        "the error starts with Error: for screen readers")))

(test a-control-without-an-error-is-not-invalid
  (let ((page (forms-html (tun.ui:select (:label "Mva-sats" :id "mva"
                                                 :hint "Gjelder alle linjene."
                                                 :options '((25 "25 %") (15 "15 %")))))))
    (is (equal "mva-hint" (forms-attribute page "select" "aria-describedby")))
    (is (null (search "aria-invalid" page))))
  (let ((page (forms-html (tun.ui:textarea (:label "Notat")))))
    (is (null (search "aria-describedby" page)) "nothing to describe it with")))

(test every-text-control-is-tied-the-same-way
  (dolist (page (mapcar #'forms-html
                        (list (tun.ui:textarea (:label "Notat" :id "c" :hint "h" :error "e"))
                              (tun.ui:select (:label "Lager" :id "c" :hint "h" :error "e"
                                                     :options '(("a" "A"))))
                              (tun.ui:input-group (:label "Timepris" :id "c" :hint "h"
                                                          :error "e" :suffix "kr"))
                              (tun.ui:checkbox (:label "Jeg godtar vilkårene" :id "c" :hint "h"
                                                       :error "e")))))
    (is (equal "c" (forms-attribute page "label" "for")))
    (is (search "aria-describedby=\"c-hint c-error\"" page))
    (is (search "aria-invalid=\"true\"" page))
    (is (search "id=\"c-hint\"" page))
    (is (search "id=\"c-error\"" page))))

(test the-field-ties-a-control-of-ones-own
  (let ((page (forms-html (tun.ui:field (:label "Vedlegg" :for "v" :error "For stor")
                            `(:input ,(tun.ui:attrs (list :type "file")
                                                    (tun.ui:control-attributes "v" :error t)))))))
    (is (equal "v" (forms-attribute page "label" "for")))
    (is (equal "v-error" (forms-attribute page "input" "aria-describedby")))
    (is (equal "true" (forms-attribute page "input" "aria-invalid")))))

(test an-optional-field-says-so-in-its-label
  (let ((page (forms-html (tun.ui:text-input (:label "Referanse" :optional t)))))
    (is (search "Referanse<span class=\"tun-field-optional\"> (optional)</span></label>"
                page))))

;;; ------------------------------------------------------------------
;;; Groups of choices

(test a-group-of-choices-is-described-on-its-fieldset
  (let* ((choices '(("bedrift" "Bedrift" :hint "Med org.nr.") ("privat" "Privatperson")))
         (page (forms-html (tun.ui:radios (:legend "Kundetype" :name "kundetype" :id "kt"
                                                   :hint "Velg én." :error "Velg kundetype"
                                                   :selected "privat" :choices choices))))
         (described-by (forms-attribute page "fieldset" "aria-describedby")))
    (is (stringp described-by))
    (dolist (id (cl-ppcre:split " " described-by))
      (is (search (format nil "id=\"~a\"" id) page) "~a names nothing on the page" id))
    (is (search "<legend class=\"tun-fieldset-legend\">Kundetype" page))
    (is (search "id=\"kt\"" page) "the first choice has the group's id, for the error summary")
    (is (search "for=\"kt-2\"" page) "the next one id-2, as GOV.UK")
    (is (search "aria-describedby=\"kt-hint\"" page) "a choice's own hint describes it")
    (is (cl-ppcre:scan "value=\"privat\" checked" page))
    (is (= 1 (length (cl-ppcre:all-matches-as-strings " checked" page))))))

(test checkboxes-check-every-selected-value
  (let* ((choices '(("man" "Man") ("tir" "Tir") ("ons" "Ons")))
         (page (forms-html (tun.ui:checkboxes (:legend "Dager" :name "dager" :choices choices
                                                       :selected '("man" "ons"))))))
    (is (= 2 (length (cl-ppcre:all-matches-as-strings " checked" page))))
    (is (null (search "checked=" page)) "checked is a bare attribute")))

(test a-switch-is-a-checkbox-with-the-switch-role
  (let ((page (forms-html (tun.ui:switch (:label "Send påminnelser" :id "p"
                                                 :description "Tre dager etter forfall.")))))
    (is (equal "switch" (forms-attribute page "input" "role")))
    (is (equal "checkbox" (forms-attribute page "input" "type")))
    (is (equal "p" (forms-attribute page "label" "for")))
    (is (equal "p-hint" (forms-attribute page "input" "aria-describedby")))))

;;; ------------------------------------------------------------------
;;; Every control is labelled

(test a-control-without-a-label-is-an-error
  (signals error (tun.ui:text-input (:name "epost")))
  (signals error (tun.ui:text-input (:label "")) "an empty label is no label")
  (signals error (tun.ui:textarea (:name "notat")))
  (signals error (tun.ui:select (:options '(("a" "A")))))
  (signals error (tun.ui:checkbox (:name "vilkar")))
  (signals error (tun.ui:switch (:name "paminnelse")))
  (signals error (tun.ui:input-group (:suffix "kr")))
  (signals error (tun.ui:field (:for "x") "kontroll"))
  (signals error (tun.ui:fieldset () "felt"))
  (signals error (tun.ui:radios (:choices '(("ja" "Ja") ("nei" "Nei")))) "no legend")
  (signals error (tun.ui:checkboxes (:legend "Dager" :choices '(("man" nil))))
           "a choice without a label"))

(test controls-refuse-what-they-cannot-draw
  (signals error (tun.ui:field (:label "Navn") "kontroll") "a field needs :for")
  (signals error (tun.ui:text-input (:label "Navn" :type :hidden)))
  (signals error (tun.ui:text-input (:label "Postnummer" :width 7)))
  (signals error (tun.ui:radios (:legend "Kundetype" :name "k")) "no choices"))

;;; ------------------------------------------------------------------
;;; The error summary

(test the-error-summary-links-to-each-field
  (let* ((errors '(("kunde-navn" "Skriv inn navnet") ("kunde-epost" "Skriv inn e-posten")))
         (page (forms-html (tun.ui:error-summary (:errors errors)))))
    (is (search "role=\"alert\"" page))
    (is (search "tabindex=\"-1\"" page))
    (is (search "data-tun-error-summary" page) "the script finds it by its data attribute")
    (is (search "<a href=\"#kunde-navn\">Skriv inn navnet</a>" page))
    (is (search "<a href=\"#kunde-epost\">Skriv inn e-posten</a>" page))
    (is (search "There is a problem" page)))
  (is (search "focus" (tun.ui:component-script (tun.ui:find-component "error-summary")))))

;;; ------------------------------------------------------------------
;;; The file control (spec/files.md 6.1)

(test a-file-input-is-a-labelled-file-control-in-a-drop-zone
  (flet ((control ()
           (tun.ui:file-input (:label "Skjermbilder" :name "filer" :id "filer"
                               :hint "Opptil 10 MB."
                               :error "«a.txt»: Filtypen er ikke tillatt."))))
    (let ((page (forms-html (control))))
      (is (equal "filer" (forms-attribute page "label" "for")))
      (is (equal "file" (forms-attribute page "input" "type")))
      (is (equal "filer" (forms-attribute page "input" "name")))
      (is (search " multiple" page))
      (is (equal "image/png,image/jpeg,image/webp,image/gif,application/pdf"
                 (forms-attribute page "input" "accept")))
      (is (equal "filer-hint filer-error" (forms-attribute page "input" "aria-describedby")))
      (is (equal "true" (forms-attribute page "input" "aria-invalid")))
      (is (forms-in-order-p page "data-tun-file-input" "<input" "data-tun-file-input-list"))
      (is (search "Drag files here, or paste a screenshot." page))
      (is (equal page (forms-html (tun.html:untrusted (control))))
          "the same in extension output")))
  (is (not (search " multiple" (forms-html (tun.ui:file-input (:label "Kvittering" :max 1)))))
      "one file only")
  (is (search "enctype=\"multipart/form-data\""
              (forms-html (tun.html:untrusted
                           '(:form (:@ :method "post" :enctype "multipart/form-data")))))
      "a form's enctype passes in extension output"))

(test a-generated-form-takes-files
  (with-test-app ()
    (with-application (*app*)
      (let ((tun.web::*web-app* *app*)
            (*actor* (parse-actor "employee:anna")))
        (flet ((form-of (operation)
                 (forms-html (tun.web::operation-form (find-operation operation) "/notater"))))
          (let ((page (form-of 'file-notes-create)))
            (is (search "enctype=\"multipart/form-data\"" page))
            (is (search "data-tun-file-input" page))
            (is (cl-ppcre:scan (concatenate 'string "<input class=\"tun-file-input-control\" "
                                            "type=\"file\" name=\"screenshots\"")
                               page)))
          (let ((page (form-of 'file-notes-get)))
            (is (not (search "enctype" page)) "a form without files is not multipart")))))))
