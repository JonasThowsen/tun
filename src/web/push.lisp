;;;; web/push.lisp -- Tun's paths under /push/ for push notifications
;;;; (spec/push.md 2.3): the public key, and the posts the switch makes
;;;; for this device, each calling its tool as the signed-in person.

(in-package #:tun.web)

(declaim (optimize (safety 3) (debug 2)))

(defun push-path-p (path)
  "True for PATH under /push/, which no client page takes."
  (string-prefix-p "/push/" path))

(defun answer-json (status json)
  "Answer STATUS with JSON, not to be cached."
  (setf (hunchentoot:return-code*) status
        (hunchentoot:content-type*) "application/json; charset=utf-8"
        (hunchentoot:header-out "Cache-Control") "no-cache")
  (sb-ext:string-to-octets (to-json-string json) :external-format :utf-8))

(defun push-form ()
  "The posted fields as a JSON object."
  (let ((form (jobj)))
    (dolist (pair (hunchentoot:post-parameters*) form)
      (setf (gethash (car pair) form) (cdr pair)))))

(defun push-tool-answer (tool arguments)
  "Answer TOOL's result for ARGUMENTS, called as the signed-in person, or its
error document with the status its code has on /api."
  (multiple-value-bind (json code) (web-call tool arguments)
    (answer-json (if code (error-status code) 200) json)))

(defun serve-push (method path)
  "Answer a request for PATH under /push/ (spec/push.md 2.3), or NIL when
there is no such path."
  (let ((form (and (eq method :post) (push-form))))
    (flet ((field (name) (or (jget form name) "")))
      (cond ((string= path "/push/key")
             (cond ((not (eq method :get)) nil)
                   ((null (web-app)) nil)
                   (t (answer-json 200 (jobj "key" (with-transaction (:read)
                                                     (tun.push:vapid-public-key-text)))))))
            ((not (eq method :post)) nil)
            ((null *actor*)
             (answer-json 401 (jobj "error" (jobj "code" "unauthenticated"
                                                  "message" "Logg inn først"))))
            ((string= path "/push/subscription")
             (let ((device (tun.push:device-name (hunchentoot:header-in* :user-agent))))
               (push-tool-answer "push_subscribe"
                                 (apply #'jobj "endpoint" (field "endpoint")
                                        "p256dh" (field "p256dh") "auth" (field "auth")
                                        (and device (list "device" device))))))
            ((string= path "/push/unsubscribe")
             (push-tool-answer "push_unsubscribe" (jobj "endpoint" (field "endpoint"))))
            ((string= path "/push/state")
             (push-tool-answer "push_check" (jobj "endpoint" (field "endpoint"))))
            ((string= path "/push/test")
             (push-tool-answer "push_test" (jobj)))
            (t nil)))))
