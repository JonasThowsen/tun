;;;; push/push.lisp -- push subscriptions, NOTIFY-PUSH and delivery
;;;; (spec/push.md 3-5, 8).
;;;;
;;;; A person turns notifications on for a device: the browser subscribes
;;;; to its push service and Tun stores the subscription, one per device,
;;;; under the person's name.  NOTIFY-PUSH, inside a write, enqueues one
;;;; SEND-PUSH job per device in the caller's transaction, as SEND-MAIL
;;;; does for a mail.  Each attempt encrypts the notification for its
;;;; device, signs a VAPID token and posts it through the application's push
;;;; service, outside any transaction.  The push service's answer decides:
;;;; delivered, the device is gone (404 or 410: the subscription is
;;;; deleted), try again later, or refused for good.
;;;;
;;;; A push service is a port: DELIVER-PUSH on an adapter.  WEB-PUSH-SERVICE
;;;; posts over HTTPS through TUN.OUTBOUND; LOG-PUSH-SERVICE, which an
;;;; application with the test clock gets, sends nothing.

(in-package #:tun.push)

(declaim (optimize (safety 3) (debug 2)))

(define-entity push-subscription (:label "Varselabonnement" :id-prefix "psh"
                                         :table "push_subscriptions" :internal t
                                         :unique (("endpoint")) :indexes (("account") ("session")))
  ((account :type (string :min 1 :max 64) :required t :input nil :label "Konto"
            :description "The name of the account, the actor's name, whose notifications it gets.")
   (endpoint :type (string :min 1 :max 1000) :required t :input nil :label "Adresse"
             :description "The push service's URL for the browser, rebuilt from its parts.")
   (p256dh :type (string :min 1 :max 100) :required t :input nil :label "Nettleserens nøkkel")
   (auth :type (string :min 1 :max 40) :required t :input nil :secret t
         :label "Nettleserens hemmelighet")
   (server-key :type (string :min 1 :max 100) :required t :input nil :label "Tuns nøkkel"
               :description "Tun's public key when it was made; another key cannot reach it.")
   (session :type (string :max 64) :input nil :label "Økt"
            :description "The session it was made or last checked in: logging out of
that session deletes it.")
   (device :type (string :max 80) :input nil :label "Enhet")
   (created-at :type timestamp :input nil :label "Opprettet")
   (tested-at :type timestamp :input nil :label "Prøvevarsel sendt")))

;;; ------------------------------------------------------------------
;;; Push services' addresses (spec/push.md 3)

(defparameter +push-service-hosts+
  '("fcm.googleapis.com" ".push.apple.com"
    "updates.push.services.mozilla.com" ".push.services.mozilla.com"
    ".notify.windows.com")
  "The hosts Tun posts push messages to: a name, or, starting with a dot,
every host whose name ends so.  Google's (Chrome and the browsers built on
it), Apple's, Mozilla's and Microsoft's push services.")

(defparameter +endpoint-scanner+
  (cl-ppcre:create-scanner "^https://([a-z0-9.-]+)(/[^\\s#]*)$" :case-insensitive-mode t)
  "An https URL with a host name and a path: no user, no port, no fragment.")

(defun push-service-host-p (host)
  (some (lambda (allowed)
          (if (char= (char allowed 0) #\.)
              (and (> (length host) (length allowed))
                   (string= allowed host :start2 (- (length host) (length allowed))))
              (string= allowed host)))
        +push-service-hosts+))

(defun push-service-endpoint (text)
  "TEXT rebuilt from its host and path when it is an https URL at a push
service's host (+PUSH-SERVICE-HOSTS+), at most 1000 characters; else NIL.
What is rebuilt is what is stored and posted to, so the host checked is the
host connected to."
  (when (and (stringp text) (<= (length text) 1000))
    (cl-ppcre:register-groups-bind (host path) (+endpoint-scanner+ text)
      (let ((host (string-downcase host)))
        (when (push-service-host-p host)
          (concatenate 'string "https://" host path))))))

(defun shown-endpoint (endpoint)
  "ENDPOINT as the trace names it: its origin.  The path addresses the device."
  (format nil "POST ~a/…" (endpoint-origin endpoint)))

;;; ------------------------------------------------------------------
;;; The device's name, from its user agent

(defun device-name (user-agent)
  "A short Norwegian name for the device USER-AGENT describes, such as
\"iPhone\" or \"Chrome på Mac\", or NIL without one."
  (when (stringp user-agent)
    (flet ((has (text) (search text user-agent)))
      (let ((platform (cond ((has "iPhone") "iPhone")
                            ((has "iPad") "iPad")
                            ((has "Android") "Android")
                            ((has "Macintosh") "Mac")
                            ((has "Windows") "Windows")
                            ((has "Linux") "Linux")))
            (browser (cond ((has "Edg/") "Edge")
                           ((has "Firefox/") "Firefox")
                           ((has "Chrome/") "Chrome")
                           ((has "Safari/") "Safari"))))
        (cond ((member platform '("iPhone" "iPad") :test #'equal) platform)
              ((and browser platform) (format nil "~a på ~a" browser platform))
              (t (or platform browser)))))))

;;; ------------------------------------------------------------------
;;; Subscriptions

(defparameter +most-subscriptions+ 10
  "How many devices one account has notifications on; an 11th replaces the oldest.")

(defun caller-session ()
  "The session the current call came in, or NIL."
  (and (stringp *credential*) (string-prefix-p "ses_" *credential*) *credential*))

(defun subscriptions-of (name)
  "NAME's subscriptions, the one stored longest ago first."
  (select 'push-subscription :where `(:= "account" ,name)
                             :order-by '(("created_at" :asc) ("seq" :asc))))

(defun push-available-p ()
  "True when the application is installed as an app: only then does its
service worker show a notification (spec/push.md 1)."
  (and (application-web-app *application*) t))

(defun find-own-subscription (endpoint)
  "The caller's subscription at ENDPOINT, or NIL."
  (let ((endpoint (push-service-endpoint endpoint)))
    (and endpoint
         (select-one 'push-subscription
                     :where `(:and (:= "endpoint" ,endpoint)
                                   (:= "account" ,(actor-name *actor*)))))))

(defun browser-key (name text octets)
  "The octets TEXT, base64url, decodes to when they are OCTETS long, or NIL
with an input error for NAME."
  (let ((decoded (handler-case (base64url-octets text)
                   (error () nil))))
    (if (and decoded (= (length decoded) octets))
        decoded
        (input-error name "er ikke en nøkkel fra nettleseren"))))

(defun drop-oldest-subscriptions (name)
  "Delete NAME's oldest subscriptions beyond +MOST-SUBSCRIPTIONS+."
  (let ((all (subscriptions-of name)))
    (loop repeat (- (length all) +most-subscriptions+)
          for subscription in all
          do (delete-entity subscription))))

(defun forget-session-subscriptions (session)
  "Delete the subscriptions made or last checked in SESSION, a session's id,
in the caller's write: logging out of it (spec/push.md 3)."
  (when session
    (dolist (subscription (select 'push-subscription :where `(:= "session" ,session)))
      (delete-entity subscription))))

(defmethod tun.auth:account-disabled progn ((application application) account)
  (dolist (subscription (subscriptions-of (account-name account)))
    (delete-entity subscription)))

;;; ------------------------------------------------------------------
;;; Sending (spec/push.md 4)

(defparameter +most-notification-octets+ (- +record-size+ +push-header-octets+ 17)
  "The largest notification, as UTF-8 JSON: what one record holds in a body of
4096 octets, after the header, the delimiter and the tag.")

(defun local-path-p (url)
  "True when URL is a path on this server: it starts with / and its second
character is neither / nor \\, which a browser reads as another host."
  (and (plusp (length url))
       (char= (char url 0) #\/)
       (not (and (> (length url) 1) (member (char url 1) '(#\/ #\\))))))

(defun notification-json (title body url tag)
  "The notification as the service worker reads it, without the absent fields."
  (apply #'jobj "title" title "url" url
         (append (and body (list "body" body)) (and tag (list "tag" tag)))))

(defun notification-octets (title body url tag)
  "The notification as the octets a push message carries: its JSON in UTF-8."
  (sb-ext:string-to-octets (to-json-string (notification-json title body url tag))
                           :external-format :utf-8))

(defun check-text (name value &key required (min 0) max)
  "True when VALUE is NIL (and not REQUIRED) or a text of MIN to MAX
characters; else NIL, with an input error for NAME."
  (cond ((null value)
         (or (not required) (input-error name "må fylles ut")))
        ((not (stringp value)) (input-error name "må være en tekst"))
        ((< (length value) min) (input-error name "må fylles ut"))
        ((> (length value) max) (input-error name "kan ha høyst ~d tegn" max))
        (t t)))

(defun check-notification (title body url tag)
  "Signal invalid_input unless the notification's fields are as
spec/push.md 4 says, the whole of it within one record."
  (collecting-input-errors
   (check-text "title" title :required t :min 1 :max 120)
   (check-text "body" body :max 1000)
   (check-text "tag" tag :max 64)
   (when (check-text "url" url :required t :min 1 :max 1000)
     (unless (local-path-p url)
       (input-error "url" "må være en sti på denne serveren, som /saker/12")))
   (when (null *input-errors*)
     (let ((size (length (notification-octets title body url tag))))
       (when (> size +most-notification-octets+)
         (input-error "body" "varselet er ~d byte; det kan være høyst ~d"
                      size +most-notification-octets+))))))

(defun account-disabled-p (name)
  (let ((account (find-account-by-name name)))
    (and account (not (equal (account-status account) "active")))))

(defun notify-push (name &key title body url tag)
  "Send a notification to each device of the account NAME, inside the
current write: one SEND-PUSH job per device, which runs after the write
commits and never when it rolls back (spec/push.md 4).  URL, a path on this
server, is the page it opens, / when absent; TAG makes a later one with the
same tag replace it.  Returns how many devices it was queued for.  A bad
argument fails the operation with invalid_input."
  (check-type name string)
  (let ((url (or url "/")))
    (check-notification title body url tag)
    (if (or (not (push-available-p)) (account-disabled-p name))
        0
        (let ((key (vapid-public-key-text))
              (count 0))
          (dolist (subscription (subscriptions-of name) count)
            (if (equal (push-subscription-server-key subscription) key)
                (progn
                  (enqueue-job 'send-push :subscription-id (entity-id subscription)
                               :title title :body body :url url :tag tag)
                  (incf count))
                ;; Made with an older key: no push service takes a message for it.
                (delete-entity subscription)))))))

;;; ------------------------------------------------------------------
;;; The port (spec/push.md 5)

(defclass push-service () ()
  (:documentation "Where push messages go.  A subclass has a DELIVER-PUSH method."))

(defgeneric deliver-push (service endpoint headers body)
  (:documentation "Post BODY, octets, with HEADERS (an alist of strings,
Content-Type among them) to ENDPOINT through SERVICE.  Values the push
service's status and its answer's text, or NIL and what came instead of an
answer."))

(defclass web-push-service (push-service) ()
  (:documentation "Posts to the browsers' push services over HTTPS, through the
calls to other systems of TUN.OUTBOUND."))

(defparameter +push-time-limit+ 10
  "Seconds a push service has to answer one attempt.")

(defmethod deliver-push ((service web-push-service) endpoint headers body)
  (let ((content-type (cdr (assoc "Content-Type" headers :test #'string-equal))))
    (tun.outbound:http-post endpoint body
                            :content-type content-type
                            :headers (remove "Content-Type" headers :key #'car
                                             :test #'string-equal)
                            :timeout +push-time-limit+
                            :name (shown-endpoint endpoint))))

(defclass log-push-service (push-service) ()
  (:documentation "Sends nothing and answers 201: what an application with the
test clock gets, so a test that sends no notification on purpose never
posts one."))

(defmethod deliver-push ((service log-push-service) endpoint headers body)
  (declare (ignore endpoint headers body))
  (values 201 ""))

;;; ------------------------------------------------------------------
;;; Delivery (spec/push.md 5)

(defparameter +push-retry-delays+ '(30 120 600 1800 3600 10800)
  "Seconds to wait after each failed attempt, the first to the sixth; a
notification whose seventh attempt fails is failed for good.")

(defparameter +push-ttl+ 86400
  "Seconds a push service keeps a message for a device that is offline.")

(declare-queue-default :push 2)

(define-condition push-not-delivered (error)
  ((reason :initarg :reason :reader push-not-delivered-reason))
  (:report (lambda (c s) (write-string (push-not-delivered-reason c) s)))
  (:documentation "A temporary failure to deliver a notification: its job tries again."))

(defun push-headers (endpoint)
  "The headers of a message to ENDPOINT (spec/push.md 6.1, 6.2)."
  `(("Content-Type" . "application/octet-stream")
    ("Content-Encoding" . "aes128gcm")
    ("TTL" . ,(princ-to-string +push-ttl+))
    ("Authorization" . ,(vapid-authorization endpoint))))

(defun delivery-outcome (status)
  "What the push service's STATUS, or NIL for no answer, means: :SENT,
:GONE (the device no longer takes messages), :RETRY or :FAILED."
  (cond ((null status) :retry)
        ((<= 200 status 299) :sent)
        ((member status '(404 410)) :gone)
        ((or (= status 429) (<= 500 status 599)) :retry)
        (t :failed)))

(defun delete-subscription (id)
  (with-transaction (:write)
    (let ((subscription (fetch 'push-subscription id)))
      (when subscription (delete-entity subscription)))))

(defun answer-excerpt (answer)
  (let ((text (if (stringp answer) answer "")))
    (subseq text 0 (min 200 (length text)))))

(define-job send-push ((subscription-id :type (id push-subscription) :required t)
                       (title :type (string :min 1 :max 120) :required t)
                       (body :type (string :max 1000))
                       (url :type (string :max 1000))
                       (tag :type (string :max 64)))
  (:queue :push :transaction nil :max-attempts 7 :backoff +push-retry-delays+ :timeout 30)
  "Make one attempt to deliver a notification to the device of the
subscription SUBSCRIPTION-ID (spec/push.md 5)."
  (let ((subscription (with-transaction (:read) (fetch 'push-subscription subscription-id))))
    (unless subscription
      (cancel-job "Abonnementet finnes ikke lenger"))
    (let ((endpoint (push-service-endpoint (push-subscription-endpoint subscription))))
      (unless endpoint
        (delete-subscription subscription-id)
        (cancel-job "Adressen er ikke hos en push-tjeneste"))
      (multiple-value-bind (status answer)
          (deliver-push (application-push-service *application*) endpoint
                        (with-transaction (:read) (push-headers endpoint))
                        (encrypt-push (notification-octets title body (or url "/") tag)
                                      (base64url-octets (push-subscription-p256dh subscription))
                                      (base64url-octets (push-subscription-auth subscription))))
        (ecase (delivery-outcome status)
          (:sent nil)
          (:gone
           (delete-subscription subscription-id)
           (cancel-job "Enheten tar ikke lenger imot varsler"))
          (:retry
           (error 'push-not-delivered
                  :reason (if status
                              (format nil "~a svarte ~d: ~a" (endpoint-origin endpoint) status
                                      (answer-excerpt answer))
                              (format nil "~a: ~a" (endpoint-origin endpoint) answer))))
          (:failed
           (fail-job (format nil "~a svarte ~d: ~a" (endpoint-origin endpoint) status
                             (answer-excerpt answer)))))))))

;;; ------------------------------------------------------------------
;;; Tools (spec/push.md 8)

(define-operation push-subscribe ((endpoint :type (string :max 2000) :required t
                                            :label "Adresse")
                                  (p256dh :type (string :max 200) :required t
                                          :label "Nettleserens nøkkel")
                                  (auth :type (string :max 100) :required t :secret t
                                        :label "Nettleserens hemmelighet")
                                  (device :type (string :max 80) :label "Enhet"))
    (:entity push-subscription :kind :update :policy :viewer :viewer-mutation t
             :title "Slå på varsler"
             :description "Lagrer abonnementet til denne enheten, så den får varslene dine.")
  (unless (push-available-p)
    (fail :invalid-input "Varsler krever at klienten kan installeres som app"))
  (let* ((name (actor-name *actor*))
         (fields (collecting-input-errors
                  (list (or (push-service-endpoint endpoint)
                            (input-error "endpoint" "er ikke en adresse hos en push-tjeneste"))
                        (let ((key (browser-key "p256dh" p256dh 65)))
                          (if (or (null key) (p256-point-p key))
                              key
                              (input-error "p256dh" "er ikke en nøkkel fra nettleseren")))
                        (browser-key "auth" auth 16))))
         (endpoint (first fields))
         (stored (select-one 'push-subscription :where `(:= "endpoint" ,endpoint)))
         (subscription (make-instance 'push-subscription :endpoint endpoint)))
    ;; The same browser again, perhaps another person's now: a new record,
    ;; stored now, so it is the newest of the account's.
    (when stored
      (delete-entity stored))
    (setf (push-subscription-account subscription) name
          (push-subscription-p256dh subscription) (base64url (second fields))
          (push-subscription-auth subscription) (base64url (third fields))
          (push-subscription-server-key subscription) (vapid-public-key-text)
          (push-subscription-session subscription) (caller-session)
          (push-subscription-device subscription) device
          (push-subscription-created-at subscription) (now))
    (insert subscription)
    (drop-oldest-subscriptions name)
    (jobj "on" t "id" (entity-id subscription))))

(define-operation push-unsubscribe ((endpoint :type (string :max 2000) :required t
                                              :label "Adresse"))
    (:entity push-subscription :kind :update :policy :viewer :viewer-mutation t
             :title "Slå av varsler"
             :description "Sletter abonnementet til denne enheten, så den ikke får flere varsler.")
  (let ((subscription (find-own-subscription endpoint)))
    (unless subscription
      (fail :not-found "Denne enheten har ikke varsler på"))
    (delete-entity subscription)
    (jobj "on" nil)))

(define-operation push-check ((endpoint :type (string :max 2000) :required t
                                        :label "Adresse"))
    (:entity push-subscription :kind :update :policy :viewer :viewer-mutation t
             :title "Har denne enheten varsler på"
             :description "Sier om enheten får varslene dine, og knytter den til økten du er i.")
  (let ((subscription (find-own-subscription endpoint)))
    (if (and subscription
             (equal (push-subscription-server-key subscription) (vapid-public-key-text)))
        (let ((session (caller-session)))
          (when (and session (not (equal session (push-subscription-session subscription))))
            (setf (push-subscription-session subscription) session)
            (save subscription))
          (jobj "on" t))
        (jobj "on" nil))))

(define-operation push-devices ()
    (:entity push-subscription :kind :read :policy :viewer :title "Enheter med varsler"
             :description "Enhetene dine som får varsler, uten adresser og nøkler.")
  (jobj "items"
        (jarr (mapcar (lambda (subscription)
                        (jobj "id" (entity-id subscription)
                              "device" (or (push-subscription-device subscription) :null)
                              "created_at" (format-rfc3339
                                            (push-subscription-created-at subscription))))
                      (subscriptions-of (actor-name *actor*))))))

(defparameter +push-test-interval+ 60
  "Seconds between two test notifications to one account.")

(define-operation push-test ()
    (:entity push-subscription :kind :update :policy :viewer :viewer-mutation t
             :title "Send et prøvevarsel"
             :description "Sender et varsel til enhetene dine, så du ser at det virker. Høyst
én gang i minuttet.")
  (let* ((name (actor-name *actor*))
         (subscriptions (subscriptions-of name)))
    (when (some (lambda (subscription)
                  (let ((at (push-subscription-tested-at subscription)))
                    (and at (< (- (now) at) +push-test-interval+))))
                subscriptions)
      (fail :conflict "Et prøvevarsel ble sendt for under ett minutt siden"))
    (dolist (subscription subscriptions)
      (setf (push-subscription-tested-at subscription) (now))
      (save subscription))
    (jobj "devices" (notify-push name :title "Varsler er på"
                                 :body (format nil "Slik ser et varsel fra ~a ut."
                                               (application-title *application*))
                                 :url "/"))))
