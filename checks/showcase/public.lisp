;;;; public.lisp -- two pages a customer opens without signing in (spec/ui.md
;;;; 8, «Public pages»): a quote, whose frame shows the company's name from
;;;; the setting showcase.company_name, as a client serving many companies
;;;; answers PUBLIC-PAGE-TITLE, and a notice that keeps the application's.

(in-package #:showcase)

(define-setting "showcase.company_name"
    (:type "string" :default "Lindenhof Services"
     :description "The company's name, as customers see it on a quote."))

(defmethod public-page-title ((app showcase) prefix)
  (if (equal prefix "quote")
      (or (setting-value-at-use "showcase.company_name") (call-next-method))
      (call-next-method)))

(register-public-page
 "quote"
 (lambda (method parts form session)
   (declare (ignore method form session))
   (if (equal parts '("q1"))
       (values 200 (tr "Your quote")
               (list (ui:card (:title (tr "Garden party, 14 June"))
                       `(:p ,(tr "Tent, tables and chairs for 40 guests, delivered and collected.")))))
       (values 404 (tr "Page not found") (list `(:p ,(tr "Check the link in the email.")))))))

(register-public-page
 "notice"
 (lambda (method parts form session)
   (declare (ignore method parts form session))
   (values 200 (tr "Opening hours")
           (list (ui:card ()
                   `(:p ,(tr "Monday to Friday, 8 to 16.")))))))
