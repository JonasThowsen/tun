;;;; web.lisp -- employee-private notification list and read action, built
;;;; from the design system's components (spec/ui.md).
(in-package #:tun.notifications)

(defun read-button (item)
  "The form that marks the notification ITEM read."
  `(:form (:@ :method "post" :action "/varsler")
          (:input (:@ :type "hidden" :name "id" :value ,(jget item "id")))
          ,(ui:button (:type "submit" :variant :outline :size :sm :icon :check)
                      "Marker som lest")))

(defun notification-row (item)
  "One notification: its text (a link to what it is about), whether it is
read, and while it is unread the button that marks it read."
  (let ((unread (json-null-p (jget item "read_at")))
        (link (jget item "link")))
    (ui:card (:size :sm)
             (ui:cluster (:justify :between)
                         (ui:stack (:gap :xs)
                                   (if (stringp link)
                                       (ui:link (:href link) (jget item "text"))
                                       `(:p ,(jget item "text")))
                                   (ui:cluster ()
                                               (ui:badge (:variant (if unread :info :outline))
                                                         (if unread "Ulest" "Lest"))))
                         (when unread (read-button item))))))

(defun staff-notifications-page (method parts form query)
  (declare (ignore parts query))
  (when (eq method :post) (call-tool "notifications_mark_read" (jobj "id" (jget form "id"))))
  (let* ((count (call-tool "notifications_unread_count" (jobj)))
         (items (coerce (jget (call-tool "notifications_list" (jobj "limit" 100)) "items") 'list))
         (unread (if (jget count "capped") "99+" (princ-to-string (jget count "count")))))
    (values 200 "Varsler"
            (list `(:p "Uleste: " (:strong ,unread))
                  (if items
                      (apply #'ui:stack* (list :gap :sm) (mapcar #'notification-row items))
                      (ui:empty-state (:icon :bell :title "Ingen varsler"
                                             :description "Det som trenger deg, kommer hit.")))))))

(tun.web:register-staff-page "varsler" #'staff-notifications-page :title "Varsler" :icon :bell)
(defmethod tun.web:staff-navigation-title ((app notifications-module) prefix title)
  (if (and (equal prefix "varsler") (actor-permits-p *actor* :employee))
      (let ((count (call-tool "notifications_unread_count" (jobj))))
        (format nil "~a (~a)" title (if (jget count "capped") "99+" (jget count "count"))))
      (call-next-method)))
(seal-module "notifications")
