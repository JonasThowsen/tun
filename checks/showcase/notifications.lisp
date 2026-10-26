;;;; notifications.lisp -- the «Varsler» page: notifications on this device
;;;; with Tun's push-switch, and a notification a person sends to themselves
;;;; through notify-push, as a client's own code would (spec/push.md 1).

(in-package #:showcase)

(define-operation notifications-send-to-me ((title :type (string :min 1 :max 120) :required t
                                                   :label "Tittel")
                                            (body :type (string :max 1000) :label "Tekst"))
    (:kind :update :policy :employee :title "Send et varsel til meg"
           :description "Sender et varsel til enhetene dine, som åpner sakene.")
  (jobj "devices" (notify-push (actor-name *actor*) :title title :body body :url "/saker"
                               :tag "showcase")))

(defun notifications-body (&key message)
  "The page: this device's switch, then a form that sends a notification."
  (list (ui:stack (:gap :lg)
          (ui:card (:title "Denne enheten"
                           :description "Slå på varsler her, og slå dem av når du vil.")
            (ui:push-switch ()))
          (ui:card (:title "Send et varsel til deg selv"
                           :description "Det kommer på hver enhet du har slått på varsler
for, og åpner sakene.")
            `(:form (:@ :method "post" :action "/varsler")
                    ,(ui:stack (:gap :md)
                       message
                       (ui:text-input (:label "Tittel" :name "title" :value "Ny sak til deg"))
                       (ui:textarea (:label "Tekst" :name "body" :rows 3
                                     :value "Eksporten feiler for kunden"))
                       (ui:form-actions ()
                         (ui:button (:type "submit" :icon :send) "Send varselet"))))))))

(define-page notifications-page ("varsler" :title "Varsler" :icon :bell :policy :employee)
    (method path form query)
  (declare (ignore path query))
  (if (eq method :post)
      (multiple-value-bind (json code)
          (web-call "notifications_send_to_me"
                    (jobj "title" (jget form "title") "body" (jget form "body")))
        (values (if code 422 200) "Varsler"
                (notifications-body
                 :message (if code
                              (error-alert json)
                              (ui:alert (:variant :success :title "Sendt")
                                (format nil "Varselet går til ~d ~:*~[enheter~;enhet~:;enheter~]."
                                        (jget json "devices")))))))
      (values 200 "Varsler" (notifications-body))))
