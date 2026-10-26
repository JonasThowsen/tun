;;;; tests/ui-feedback-tests.lisp -- the feedback group of the design system
;;;; (spec/ui.md 6): the confirm panel's form, and the roles that decide
;;;; what a screen reader announces.

(in-package #:tun.tests)

(def-suite ui-feedback :in core)
(in-suite ui-feedback)

(defun feedback-html (markup)
  "MARKUP rendered as HTML."
  (tun.html:render-html markup))

(defun feedback-attributes (attribute html)
  "Every value of ATTRIBUTE in HTML, in order."
  (let ((values '()))
    (cl-ppcre:do-register-groups (value) ((format nil " ~a=\"([^\"]*)\"" attribute) html)
      (push value values))
    (nreverse values)))

(defun feedback-roles (markup)
  "The role attributes in MARKUP, in order."
  (feedback-attributes "role" (feedback-html markup)))

;;; ------------------------------------------------------------------
;;; Confirm panel

(defun delete-customer-confirmation ()
  (tun.ui:confirm-panel (:title "Slette kunden Berg Rørlegger AS?"
                                :action "/kunder/42/customers_delete"
                                :confirm-label "Slett kunde"
                                :cancel-href "/kunder/42"
                                :warning "Dette kan ikke angres."
                                :hidden '(("confirmation_token" "c7f3a9e2") ("id" 42)))
                        '(:p "Kunden slettes.")))

(test the-confirm-panel-posts-its-hidden-fields-to-its-action
  (let ((html (feedback-html (delete-customer-confirmation))))
    (is (search (concatenate 'string "<form class=\"tun-confirm-panel-actions\" method=\"post\""
                             " action=\"/kunder/42/customers_delete\">")
                html))
    (is (search "<input type=\"hidden\" name=\"confirmation_token\" value=\"c7f3a9e2\">" html))
    (is (search "<input type=\"hidden\" name=\"id\" value=\"42\">" html)
        "a value that is not a string is written as text")
    (is (cl-ppcre:scan "<button [^>]*type=\"submit\"[^>]*>Slett kunde</button>" html))
    (is (cl-ppcre:scan "<a [^>]*href=\"/kunder/42\"[^>]*>Avbryt</a>" html)
        "cancel is a link back")
    (is (< (search "type=\"submit\"" html) (search "</form>" html))
        "the button is inside the form")))

(test the-confirm-panel-is-a-region-named-by-its-heading
  (let* ((html (feedback-html (delete-customer-confirmation)))
         (labelledby (first (feedback-attributes "aria-labelledby" html))))
    (is (eql 0 (search "<section class=\"tun-confirm-panel\"" html)))
    (is (search (format nil "<h2 class=\"tun-confirm-panel-title\" id=\"~a\">" labelledby) html))
    (is (search "Advarsel: </span>Dette kan ikke angres." html)
        "the warning says it is one to a screen reader, not only with its mark")))

(test the-confirm-panel-button-follows-its-variant
  (flet ((submit-variant (markup)
           (cl-ppcre:register-groups-bind (variant)
               ("<button [^>]*data-variant=\"([a-z]+)\"[^>]*type=\"submit\"" (feedback-html markup))
             variant)))
    (is (equal "destructive" (submit-variant (delete-customer-confirmation))))
    (is (equal "primary"
               (submit-variant (tun.ui:confirm-panel* (list :title "Sende faktura?"
                                                            :action "/f/1/send"
                                                            :confirm-label "Send"
                                                            :cancel-href "/f/1"
                                                            :variant :primary)))))))

(test the-confirm-panel-needs-what-its-form-is-made-of
  (signals error (tun.ui:confirm-panel (:title "Slette?" :confirm-label "Slett"
                                               :cancel-href "/")))
  (signals error (tun.ui:confirm-panel (:title "Slette?" :action "/x" :cancel-href "/")))
  (signals error (tun.ui:confirm-panel (:title "Slette?" :action "/x" :confirm-label "Slett")))
  (signals error (tun.ui:confirm-panel (:title "Slette?" :action "/x" :confirm-label "Slett"
                                               :cancel-href "/" :variant :ghost)))
  (signals error (tun.ui:confirm-panel (:title "Slette?" :action "/x" :confirm-label "Slett"
                                               :cancel-href "/" :hidden '(("token"))))))

;;; ------------------------------------------------------------------
;;; Roles

(test only-a-destructive-alert-interrupts
  (is (equal '("alert")
             (feedback-roles (tun.ui:alert (:variant :destructive) "Ordren kunne ikke lagres."))))
  (dolist (variant '(:default :info :success :warning))
    (is (null (feedback-roles (tun.ui:alert* (list :variant variant) "Tekst.")))
        "a ~(~a~) alert has no role" variant))
  (is (equal '("status") (feedback-roles (tun.ui:alert (:role :status) "Kopiert."))))
  (is (null (feedback-roles (tun.ui:alert (:variant :destructive :role nil) "Tekst.")))
      "a destructive alert can be told not to interrupt")
  (signals error (tun.ui:alert (:role :region) "Tekst.")))

(test an-alert-shows-its-variant-icon-unless-told-otherwise
  (is (search "tun-icon" (feedback-html (tun.ui:alert (:variant :success) "Lagret."))))
  (is (not (search "tun-icon"
                   (feedback-html (tun.ui:alert (:variant :success :icon nil) "Lagret.")))))
  (is (not (search "tun-icon" (feedback-html (tun.ui:alert () "Merknad.")))))
  (signals error (tun.ui:alert (:variant :primary) "Tekst.")))

(test a-flash-is-a-status-whose-close-button-needs-javascript
  (let ((html (feedback-html (tun.ui:flash () "Kunden er lagret."))))
    (is (equal '("status") (feedback-attributes "role" html)))
    (is (search "aria-label=\"Lukk meldingen\"" html))
    (is (search " hidden data-tun-flash-close" html)
        "hidden in the markup, shown by the script"))
  (is (not (search "data-tun-flash-close"
                   (feedback-html (tun.ui:flash (:dismissible nil) "Du er logget ut."))))))

(test a-spinner-is-announced-unless-it-is-decoration
  (let ((html (feedback-html (tun.ui:spinner ()))))
    (is (equal '("status") (feedback-attributes "role" html)))
    (is (search ">Laster…</span>" html)))
  (let ((html (feedback-html (tun.ui:spinner () "Henter ordre…"))))
    (is (equal '("status") (feedback-attributes "role" html)))
    (is (not (search "Laster…" html)) "visible text replaces the hidden label"))
  (let ((html (feedback-html (tun.ui:spinner (:label nil)))))
    (is (null (feedback-attributes "role" html)))
    (is (search "class=\"tun-spinner\" aria-hidden=\"true\"" html))))

(test skeletons-are-hidden-and-a-labelled-group-is-announced
  (is (search "aria-hidden=\"true\"" (feedback-html (tun.ui:skeleton ()))))
  (let ((html (feedback-html (tun.ui:skeleton (:label "Laster kunder…") (tun.ui:skeleton ())))))
    (is (equal '("status") (feedback-attributes "role" html)))
    (is (search "Laster kunder…" html)))
  (is (search "data-shape=\"group\" data-direction=\"column\" aria-hidden=\"true\""
              (feedback-html (tun.ui:skeleton () (tun.ui:skeleton ())))))
  (signals error (tun.ui:skeleton (:shape :circle :width :half)))
  (signals error (tun.ui:skeleton (:width :huge))))

(test a-progress-bar-is-labelled-and-says-its-value
  (let* ((html (feedback-html (tun.ui:progress (:label "Ordren behandles" :value 3 :max 5
                                                       :value-text "3 av 5 steg"))))
         (for (first (feedback-attributes "for" html))))
    (is (search (format nil "<progress id=\"~a\" max=\"5\" value=\"3\" ~
                             aria-valuetext=\"3 av 5 steg\">"
                        for)
                html)
        "the label is tied to the <progress>"))
  (is (search ">66 %</span>" (feedback-html (tun.ui:progress (:label "Import" :value 66)))))
  (let ((html (feedback-html (tun.ui:progress (:label "Henter fakturaer")))))
    (is (not (search "value=" html)) "without a value the bar is indeterminate"))
  (signals error (tun.ui:progress (:value 3))))
