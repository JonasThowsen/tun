;;;; wait.lisp -- /wait: a page that answers after the milliseconds its query
;;;; asks for, with links and a form to a slow and a fast one and a part that
;;;; loads by itself, so a check can see the loading sign (spec/ui.md 4.1).

(in-package #:showcase)

(defparameter +longest-wait+ 5000
  "The longest /wait waits, in milliseconds.")

(defun asked-wait (query)
  "The milliseconds QUERY's ms asks for, from 0 to +LONGEST-WAIT+."
  (let ((ms (parse-integer (or (jget query "ms") "0") :junk-allowed t)))
    (min +longest-wait+ (max 0 (or ms 0)))))

(defun wait-links ()
  (ui:cluster ()
    (ui:button (:href "/wait?ms=1500") (tr "A slow page"))
    (ui:button (:href "/wait?ms=0" :variant :outline) (tr "A fast page"))
    `(:form (:@ :method "post" :action "/wait?ms=1500")
            ,(ui:button (:type "submit" :variant :outline) (tr "Send a slow form")))))

(define-page wait-page ("wait" :title "Wait" :icon :clock :policy :employee :navigation nil)
    (method path form query)
  (declare (ignore form))
  (let ((ms (asked-wait query)))
    (sleep (/ ms 1000))
    (cond ((eq method :post) (values 303 "/wait?ms=0&sent=1"))
          ((equal path '("part"))
           (values 200 :fragment (list `(:p (:@ :id "wait-part") ,(tr "The part has loaded.")))))
          (t
           (values 200 (tr "Wait")
                   (list `(:p ,(tr "This page waited ~d ms." ms))
                         (wait-links)
                         `(:div (:@ :hx-get "/wait/part?ms=1000" :hx-trigger "load"
                                    :hx-swap "outerHTML")
                                ,(tr "A part that loads by itself…"))))))))
