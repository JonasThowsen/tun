;;;; notifications.lisp -- the «Notifications» page: notifications on this
;;;; device with Tun's push-switch, and a notification a person sends to
;;;; themselves through notify-push, as a client's own code would (spec/push.md 1).

(in-package #:showcase)

(define-operation notifications-send-to-me ((title :type (string :min 1 :max 120) :required t
                                                   :label "Title")
                                            (body :type (string :max 1000) :label "Text"))
    (:kind :update :policy :employee :title "Send a notification to me"
           :description "Sends a notification to your devices, which opens the items.")
  (jobj "devices" (notify-push (actor-name *actor*) :title title :body body :url "/items"
                               :tag "showcase")))

(defun notifications-body (&key message)
  "The page: this device's switch, then a form that sends a notification."
  (list (ui:stack (:gap :lg)
          (ui:card (:title (tr "This device")
                    :description (tr "Turn notifications on here, and off whenever you like."))
            (ui:push-switch ()))
          (ui:card (:title (tr "Send a notification to yourself")
                    :description
                    (tr "It arrives on each device with notifications on, and opens the items."))
            `(:form (:@ :method "post" :action "/notifications")
                    ,(ui:stack (:gap :md)
                       message
                       (ui:text-input (:label (tr "Title") :name "title"
                                       :value (tr "A new item for you")))
                       (ui:textarea (:label (tr "Text") :name "body" :rows 3
                                     :value (tr "The export fails for the customer")))
                       (ui:form-actions ()
                         (ui:button (:type "submit" :icon :send)
                                    (tr "Send the notification")))))))))

(defun sent-alert (json)
  "The page's word that the notification was sent, and to how many devices:
JSON is the operation's answer."
  (ui:alert (:variant :success :title (tr "Sent"))
    (tr "The notification goes to ~d device~:p." (jget json "devices"))))

(define-page notifications-page ("notifications" :title "Notifications" :icon :bell
                                                 :policy :employee)
    (method path form query)
  (declare (ignore path query))
  (if (eq method :post)
      (multiple-value-bind (json code)
          (web-call "notifications_send_to_me"
                    (jobj "title" (jget form "title") "body" (jget form "body")))
        (values (if code 422 200) (tr "Notifications")
                (notifications-body :message (if code (error-alert json) (sent-alert json)))))
      (values 200 (tr "Notifications") (notifications-body))))
