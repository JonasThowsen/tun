;;;; tests/push-tests.lisp -- push notifications (spec/push.md): the
;;;; encryption against RFC 8291's example, VAPID and Tun's key, the
;;;; subscriptions and their tools, NOTIFY-PUSH, delivery through a fake push
;;;; service, the Web Push adapter over real HTTP, and the paths under /push/.

(in-package #:tun.tests)

(def-suite push :in core)
(in-suite push)

(defun b64 (text)
  "The octets TEXT, base64url as the RFCs print it with spaces and line breaks, encodes."
  (tun.auth:base64url-octets (remove-if (lambda (c) (member c '(#\Space #\Newline))) text)))

;;; RFC 8291 5 and Appendix A.
(defparameter +rfc-plaintext+ "When I grow up, I want to be a watermelon")
(defparameter +rfc-auth+ "BTBZMqHH6r4Tts7J_aSIgg")
(defparameter +rfc-receiver-private+ "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94")
(defparameter +rfc-receiver-public+
  "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4")
(defparameter +rfc-sender-private+ "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw")
(defparameter +rfc-sender-public+
  "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8")
(defparameter +rfc-salt+ "DGv6ra1nlYgDCS1FRnbzlw")

(defun ascii-octets (text)
  (sb-ext:string-to-octets text :external-format :ascii))

;;; ------------------------------------------------------------------
;;; Encryption (spec/push.md 6.1)

(test rfc-8291-example-encrypts-to-its-exact-body
  (let* ((receiver (b64 +rfc-receiver-public+))
         (sender (b64 +rfc-sender-public+))
         (auth (b64 +rfc-auth+))
         (salt (b64 +rfc-salt+))
         (ecdh (tun.push:ecdh-secret (b64 +rfc-sender-private+) receiver))
         (ikm (tun.push:combined-key auth ecdh receiver sender)))
    (is (equalp (b64 "kyrL1jIIOHEzg3sM2ZWRHDRB62YACZhhSlknJ672kSs") ecdh) "ecdh_secret")
    (is (equalp (b64 "Snr3JMxaHVDXHWJn5wdC52WjpCtd2EIEGBykDcZW32k")
                (tun.push::hmac-sha256 auth ecdh))
        "PRK_key")
    (is (equalp (b64 "S4lYMb_L0FxCeq0WhDx813KgSYqU26kOyzWUdsXYyrg") ikm) "IKM")
    (is (equalp (b64 "09_eUZGrsvxChDCGRCdkLiDXrReGOEVeSCdCcPBSJSc")
                (tun.push::hmac-sha256 salt ikm))
        "PRK")
    (is (equalp (b64 "oIhVW04MRdy2XN9CiKLxTg") (tun.push:content-key salt ikm)) "CEK")
    (is (equalp (b64 "4h_95klXJ5E_qnoN") (tun.push:content-nonce salt ikm)) "NONCE")
    (is (equalp (b64 +rfc-sender-public+)
                (tun.push:p256-public-key (b64 +rfc-sender-private+)))
        "the sender's public key from its private key")
    (is (equalp (b64 "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml
mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT
pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN")
                (tun.push:encrypt-push (ascii-octets +rfc-plaintext+) receiver auth
                                       :sender-private (b64 +rfc-sender-private+)
                                       :sender-public sender :salt salt))
        "the body of RFC 8291 5")))

(test the-receiver-decrypts-what-tun-sends
  (let* ((receiver (b64 +rfc-receiver-public+))
         (auth (b64 +rfc-auth+))
         (plaintext (sb-ext:string-to-octets "{\"title\":\"Ny sak til deg: «Eksporten» på Ø\"}"
                                             :external-format :utf-8))
         (first-body (tun.push:encrypt-push plaintext receiver auth))
         (second-body (tun.push:encrypt-push plaintext receiver auth)))
    (is (equalp plaintext (tun.push:decrypt-push first-body (b64 +rfc-receiver-private+)
                                                 receiver auth)))
    (is (not (equalp first-body second-body)) "a new key and salt each time")
    (is (= (+ tun.push:+push-header-octets+ (length plaintext) 17) (length first-body)))
    (signals tun.push:push-message-too-large
        (tun.push:encrypt-push (make-array 3994 :element-type '(unsigned-byte 8)
                                                :initial-element 65)
                               receiver auth)
      "more than one record holds")
    (let ((changed (copy-seq first-body)))
      (setf (aref changed 100) (logxor 1 (aref changed 100)))
      (signals tun.push:push-message-not-authentic
          (tun.push:decrypt-push changed (b64 +rfc-receiver-private+) receiver auth)
        "a changed message does not verify"))))

;;; ------------------------------------------------------------------
;;; VAPID and Tun's key (spec/push.md 6.2, 6.3)

(test ironclad-verifies-rfc-7515-es256
  (let ((public (concatenate '(vector (unsigned-byte 8)) #(4)
                             (b64 "f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU")
                             (b64 "x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0")))
        (input (concatenate 'string "eyJhbGciOiJFUzI1NiJ9."
                            "eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFt"
                            "cGxlLmNvbS9pc19yb290Ijp0cnVlfQ"))
        (signature (b64 "DtEhU3ljbEg8L38VWAfUAqOyKAM6-Xx-F4GawxaepmXFCgfTjDxw5djxLa8ISlSA
pmWQxfKTUJqPP3-Kg6NU1Q")))
    (is (ironclad:verify-signature (ironclad:make-public-key :secp256r1 :y public)
                                   (ironclad:digest-sequence :sha256 (ascii-octets input))
                                   signature))
    (is (equalp public (tun.push:p256-public-key
                        (b64 "jpsQnnGQmL-YBIffH1136cspYG6-0iY7X1fCE9-E9LI")))
        "and the public key is the private key times the generator")))

(defun token-part (text)
  (parse-json (sb-ext:octets-to-string (b64 text) :external-format :utf-8)))

(defun token-verifies-p (token key)
  "True when the JWT TOKEN's ES256 signature verifies with the public KEY (base64url)."
  (let* ((dot (position #\. token :from-end t)))
    (ironclad:verify-signature (ironclad:make-public-key :secp256r1 :y (b64 key))
                               (ironclad:digest-sequence :sha256
                                                         (ascii-octets (subseq token 0 dot)))
                               (b64 (subseq token (1+ dot))))))

(defun authorization-parts (header)
  "Values the token and the key of a vapid t=TOKEN, k=KEY header."
  (cl-ppcre:register-groups-bind (token key) ("^vapid t=([^,]+), k=(\\S+)$" header)
    (values token key)))

(test a-vapid-token-says-who-sends-and-is-signed
  (with-test-app (:public-url "https://saker.example.no")
    (with-application (*app*)
      (with-transaction (:read)
        (multiple-value-bind (token key)
            (authorization-parts
             (tun.push:vapid-authorization "https://fcm.googleapis.com/fcm/send/abc"))
          (let ((parts (cl-ppcre:split "\\." token)))
            (is (= 3 (length parts)))
            (let ((header (token-part (first parts)))
                  (claims (token-part (second parts))))
              (is (equal "JWT" (jget header "typ")))
              (is (equal "ES256" (jget header "alg")))
              (is (equal "https://fcm.googleapis.com" (jget claims "aud")))
              (is (= (+ (- (now) 2208988800) (* 12 3600)) (jget claims "exp")))
              (is (equal "https://saker.example.no" (jget claims "sub")))))
          (is (equal key (tun.push:vapid-public-key-text)))
          (is (= 65 (length (b64 key))))
          (is (token-verifies-p token key) "the signature verifies with k")))))
  (dolist (url '("http://localhost:8080" nil))
    (with-test-app (:public-url url)
      (with-application (*app*)
        (with-transaction (:read)
          (let* ((header (tun.push:vapid-authorization "https://web.push.apple.com/QGuQ"))
                 (claims (token-part (second (cl-ppcre:split "\\." (authorization-parts header))))))
            (is (equal "https://web.push.apple.com" (jget claims "aud")))
            (is (not (nth-value 1 (gethash "sub" claims)))
                "no sub without an https public URL: ~s" url)))))))

(test the-key-is-derived-from-the-secret-setting
  (with-test-app ()
    (flet ((key () (with-application (*app*)
                     (with-transaction (:read) (tun.push:vapid-public-key-text)))))
      (let ((first (key)))
        (is (equal first (key)) "the same secret, the same key")
        (is (equalp (tun.push:p256-public-key (tun.push:vapid-private-key "hemmelig"))
                    (tun.push:p256-public-key (tun.push:vapid-private-key "hemmelig"))))
        (let ((setting (find "push.hemmelighet"
                             (coerce (jget (call-ok "settings_list" "admin:ada") "items") 'list)
                             :key (lambda (item) (jget item "key")) :test #'equal)))
          (is (equal "***" (jget setting "value")))
          (is (eq t (jget setting "secret"))))
        (call-ok "settings_set" "admin:ada" "key" "push.hemmelighet" "value" "en ny hemmelighet")
        (is (not (equal first (key))) "another secret, another key")))))

;;; ------------------------------------------------------------------
;;; A push service that answers as the test says

(defclass recording-push (tun.push:push-service)
  ((answers :initarg :answers :initform nil :accessor recording-answers
            :documentation "The next statuses, in order, NIL for no answer; then 201.")
   (calls :initform nil :accessor recording-calls
          :documentation "Each call as (ENDPOINT HEADERS BODY), newest first."))
  (:documentation "A push service whose answers the test chooses."))

(defmethod tun.push:deliver-push ((service recording-push) endpoint headers body)
  (push (list endpoint headers body) (recording-calls service))
  (let ((status (if (recording-answers service) (pop (recording-answers service)) 201)))
    (if status
        (values status (format nil "status ~d" status))
        (values nil "kunne ikke nås"))))

(defmacro with-push ((service &rest answers) &body body)
  "Run BODY in a fresh application, installed as an app, whose push service
is SERVICE, a RECORDING-PUSH answering ANSWERS."
  `(let ((,service (make-instance 'recording-push :answers (list ,@answers))))
     (with-test-app (:class 'installable-app :push-service ,service)
       ,@body)))

(define-operation push-test-notify ((name :type string) (title :type string) (body :type string)
                                    (url :type string) (tag :type string)
                                    (then-fail :type boolean))
    (:kind :update :policy :employee :title "Send varsel (test)")
  (let ((count (tun.push:notify-push name :title title :body body :url url :tag tag)))
    (when then-fail
      (fail :conflict "Arbeidet feilet etter at varselet ble lagt i køen"))
    (jobj "devices" count)))

(defparameter *endpoint-number* 0)

(defun new-endpoint ()
  (format nil "https://fcm.googleapis.com/fcm/send/enhet-~d" (incf *endpoint-number*)))

(defun subscribe (actor &key (endpoint (new-endpoint)) (device "Chrome på Mac"))
  "ACTOR's new subscription at ENDPOINT, with RFC 8291's receiver key; its id."
  (jget (call-ok "push_subscribe" actor "endpoint" endpoint "p256dh" +rfc-receiver-public+
                 "auth" +rfc-auth+ "device" device)
        "id"))

(defun subscriptions-named (name)
  (with-application (*app*)
    (with-transaction (:read)
      (select 'tun.push:push-subscription :where `(:= "account" ,name)))))

(defun notify-device (name &rest arguments)
  (jget (apply #'call-ok "push_test_notify" "employee:kari" "name" name
               (append arguments '("title" "Ny sak til deg")))
        "devices"))

(defun deliver-push ()
  (drain-jobs :queue "push"))

(defun push-job-states ()
  "The state of every send_push job, oldest first."
  (with-application (*app*)
    (with-transaction (:read)
      (mapcar #'tun.jobs:job-state
              (select 'tun.jobs:job :where '(:= "kind" "send_push") :order-by '(("seq" :asc)))))))

;;; ------------------------------------------------------------------
;;; Subscriptions (spec/push.md 3, 8)

(test subscribing-stores-the-device-for-the-caller
  (with-push (service)
    (let* ((endpoint (new-endpoint))
           (id (subscribe "employee:kari" :endpoint endpoint :device "iPhone")))
      (with-application (*app*)
        (with-transaction (:read)
          (let ((subscription (fetch 'tun.push:push-subscription id)))
            (is (equal "kari" (tun.push:push-subscription-account subscription)))
            (is (equal endpoint (tun.push:push-subscription-endpoint subscription)))
            (is (equal "iPhone" (tun.push:push-subscription-device subscription)))
            (is (equal (tun.push:vapid-public-key-text)
                       (tun.push:push-subscription-server-key subscription)))
            (is (null (tun.push:push-subscription-session subscription)) "no session in-process")
            (is (equal "***" (jget (entity->json subscription) "auth")) "the secret is masked"))))
      (let ((devices (coerce (jget (call-ok "push_devices" "employee:kari") "items") 'list)))
        (is (= 1 (length devices)))
        (is (equal "iPhone" (jget (first devices) "device")))
        (is (not (search "fcm" (to-json-string (jarr devices)))) "no endpoint")
        (is (not (search +rfc-auth+ (to-json-string (jarr devices)))) "no keys"))
      (is (zerop (length (jget (call-ok "push_devices" "employee:ola") "items")))))))

(test an-endpoint-belongs-to-whoever-subscribed-it-last
  (with-push (service)
    (let ((endpoint (new-endpoint)))
      (subscribe "employee:kari" :endpoint endpoint)
      (subscribe "employee:ola" :endpoint endpoint)
      (is (null (subscriptions-named "kari")))
      (is (= 1 (length (subscriptions-named "ola")))))))

(test only-a-push-services-address-is-taken
  (with-push (service)
    (dolist (endpoint '("http://fcm.googleapis.com/fcm/send/x"
                        "https://fcm.googleapis.com:8443/fcm/send/x"
                        "https://bruker:passord@fcm.googleapis.com/fcm/send/x"
                        "https://10.0.0.1/x" "https://[::1]/x" "https://127.0.0.1/x"
                        "https://localhost/x" "https://box.tail1234.ts.net/x"
                        "https://fcm.googleapis.com.evil.example/x"
                        "https://evilfcm.googleapis.com/x" "https://push.apple.com/x"
                        "https://fcm.googleapis.com" "https://fcm.googleapis.com/x#y"
                        "https://fcm.googleapis.com/x y"))
      (is (equal "invalid_input"
                 (nth-value 1 (call "push_subscribe" "employee:kari" "endpoint" endpoint
                                    "p256dh" +rfc-receiver-public+ "auth" +rfc-auth+)))
          "~a is refused" endpoint))
    (dolist (endpoint '("https://fcm.googleapis.com/fcm/send/dQw4w9"
                        "https://web.push.apple.com/QGuQyavXutnMH"
                        "https://updates.push.services.mozilla.com/wpush/v2/gAAAAAB"
                        "https://wns2-par02p.notify.windows.com/w/?token=BQYAAAB"))
      (is (null (nth-value 1 (call "push_subscribe" "employee:kari" "endpoint" endpoint
                                   "p256dh" +rfc-receiver-public+ "auth" +rfc-auth+)))
          "~a is taken" endpoint))
    (subscribe "employee:kari" :endpoint "https://FCM.googleapis.com/fcm/send/Stor")
    (is (find "https://fcm.googleapis.com/fcm/send/Stor" (subscriptions-named "kari")
              :key #'tun.push:push-subscription-endpoint :test #'equal)
        "what is stored is rebuilt from the parts that were checked")))

(test the-browsers-keys-are-checked
  (with-push (service)
    (flet ((refused (p256dh auth)
             (nth-value 1 (call "push_subscribe" "employee:kari" "endpoint" (new-endpoint)
                                "p256dh" p256dh "auth" auth))))
      (is (equal "invalid_input" (refused "BCVx" +rfc-auth+)) "too short")
      (is (equal "invalid_input"
                 (refused (tun.auth:base64url
                           (concatenate '(vector (unsigned-byte 8)) #(4)
                                        (subseq (b64 +rfc-receiver-public+) 1 33)
                                        (subseq (b64 +rfc-receiver-public+) 1 33)))
                          +rfc-auth+))
          "not a point on P-256")
      (is (equal "invalid_input" (refused +rfc-receiver-public+ "BTBZMqHH6r4Tts7J")) "auth not 16")
      (is (equal "invalid_input" (refused +rfc-receiver-public+ "!!!")) "not base64url"))))

(test an-account-keeps-ten-devices
  (with-push (service)
    (let ((moving (new-endpoint))
          (first (subscribe "employee:kari")))
      (subscribe "employee:ola" :endpoint moving)
      (dotimes (i 9) (subscribe "employee:kari"))
      (is (= 10 (length (subscriptions-named "kari"))))
      (subscribe "employee:kari")
      (is (= 10 (length (subscriptions-named "kari"))))
      (is (not (find first (subscriptions-named "kari") :key #'entity-id :test #'equal))
          "the oldest went")
      (is (eq t (jget (call-ok "push_subscribe" "employee:kari" "endpoint" moving
                               "p256dh" +rfc-receiver-public+ "auth" +rfc-auth+)
                      "on")))
      (is (= 10 (length (subscriptions-named "kari"))))
      (is (find moving (subscriptions-named "kari")
                :key #'tun.push:push-subscription-endpoint :test #'equal)
          "an endpoint moved from another account is the newest, and stays")
      (is (eq t (jget (call-ok "push_check" "employee:kari" "endpoint" moving) "on"))))))

(test without-the-web-app-nothing-is-subscribed-or-sent
  (let ((service (make-instance 'recording-push)))
    (with-test-app (:push-service service)
      (is (equal "invalid_input"
                 (nth-value 1 (call "push_subscribe" "employee:kari" "endpoint" (new-endpoint)
                                    "p256dh" +rfc-receiver-public+ "auth" +rfc-auth+)))
          "push_subscribe refuses")
      ;; One stored while the client was installable.
      (with-application (*app*)
        (with-transaction (:write)
          (insert (make-instance 'tun.push:push-subscription
                                 :account "kari" :endpoint (new-endpoint)
                                 :p256dh +rfc-receiver-public+ :auth +rfc-auth+
                                 :server-key (tun.push:vapid-public-key-text)
                                 :created-at (now)))))
      (is (= 0 (notify-device "kari")) "notify-push sends nothing")
      (is (null (enqueued-jobs 'tun.push:send-push)))
      (is (= 1 (length (subscriptions-named "kari"))) "and keeps the subscription"))))

(test the-browsers-secret-is-not-in-the-request-record
  (with-push (service)
    (let ((id (new-id "req")))
      (let ((*request-id* id))
        (subscribe "employee:kari"))
      (let ((input (jget (call-ok "introspect_request" "admin:ada" "request_id" id) "input")))
        (is (equal "***" (jget input "auth")) "auth is masked")
        (is (equal +rfc-receiver-public+ (jget input "p256dh")) "the public key is not")))))

(test a-clients-page-cannot-take-the-push-paths
  (let ((tun.web::*staff-pages* (make-hash-table :test 'equal)))
    (let ((*package* (find-package "TUN.CUSTOMERS")))
      (tun.web:register-staff-page "push" 'identity))
    (signals extension-error (with-test-app () nil)))
  (let ((tun.web::*public-pages* (make-hash-table :test 'equal)))
    (let ((*package* (find-package "TUN.CUSTOMERS")))
      (tun.web:register-public-page "push/x" 'identity))
    (signals extension-error (with-test-app () nil))))

(test unsubscribing-and-checking-a-device
  (with-push (service)
    (let ((endpoint (new-endpoint)))
      (subscribe "employee:kari" :endpoint endpoint)
      (is (eq t (jget (call-ok "push_check" "employee:kari" "endpoint" endpoint) "on")))
      (is (eq nil (jget (call-ok "push_check" "employee:ola" "endpoint" endpoint) "on"))
          "not another's")
      (is (eq nil (jget (call-ok "push_check" "employee:kari" "endpoint" "nonsense") "on")))
      (is (equal "not_found" (nth-value 1 (call "push_unsubscribe" "employee:ola"
                                                "endpoint" endpoint))))
      (is (eq nil (jget (call-ok "push_unsubscribe" "employee:kari" "endpoint" endpoint) "on")))
      (is (null (subscriptions-named "kari")))
      (is (eq nil (jget (call-ok "push_check" "employee:kari" "endpoint" endpoint) "on"))))))

(test a-new-key-turns-every-device-off
  (with-push (service)
    (let ((endpoint (new-endpoint)))
      (subscribe "employee:kari" :endpoint endpoint)
      (call-ok "settings_set" "admin:ada" "key" "push.hemmelighet" "value" "en ny hemmelighet")
      (is (eq nil (jget (call-ok "push_check" "employee:kari" "endpoint" endpoint) "on")))
      (is (= 0 (notify-device "kari")))
      (is (null (subscriptions-named "kari")) "the old subscription is deleted"))))

(test disabling-an-account-deletes-its-devices
  (with-push (service)
    (let ((account (call-ok "accounts_create" "admin:ada" "name" "kari" "kind" "person"
                            "role" "employee" "email" "kari@example.no")))
      (subscribe "employee:kari")
      (subscribe "employee:ola")
      (call-ok "accounts_update" "admin:ada" "id" (jget account "id") "status" "disabled")
      (is (null (subscriptions-named "kari")))
      (is (= 1 (length (subscriptions-named "ola"))) "nobody else's")
      (is (= 0 (notify-device "kari")))
      (call-ok "accounts_update" "admin:ada" "id" (jget account "id") "status" "active")
      (is (null (subscriptions-named "kari")) "enabling it again brings none back"))))

(test a-test-notification-goes-once-a-minute
  (with-push (service)
    (subscribe "employee:kari")
    (subscribe "employee:kari")
    (is (= 2 (jget (call-ok "push_test" "employee:kari") "devices")))
    (is (equal "conflict" (nth-value 1 (call "push_test" "employee:kari"))))
    (is (= 0 (jget (call-ok "push_test" "employee:ola") "devices")) "nobody else is held back")
    (clock-at (+ (clock-time) 60))
    (is (= 2 (jget (call-ok "push_test" "employee:kari") "devices")))
    (deliver-push)
    (is (= 4 (length (recording-calls service))))))

;;; ------------------------------------------------------------------
;;; Sending (spec/push.md 4)

(test notify-push-queues-a-job-per-device-in-the-callers-write
  (with-push (service)
    (subscribe "employee:kari")
    (subscribe "employee:kari")
    (subscribe "employee:ola")
    (is (= 2 (notify-device "kari" "body" "Eksporten feiler" "url" "/saker/itm_12"
                            "tag" "sak:itm_12")))
    (is (= 2 (length (enqueued-jobs 'tun.push:send-push))))
    (is (equal "conflict" (nth-value 1 (call "push_test_notify" "employee:kari" "name" "kari"
                                             "title" "Hei" "then_fail" t))))
    (is (= 2 (length (enqueued-jobs 'tun.push:send-push))) "nothing after a rollback")
    (is (= 0 (notify-device "nobody")))
    (is (= 2 (deliver-push)))
    (is (= 2 (length (recording-calls service))))))

(test a-notifications-fields-are-checked
  (with-push (service)
    (subscribe "employee:kari")
    (flet ((refused (&rest arguments)
             (nth-value 1 (apply #'call "push_test_notify" "employee:kari" "name" "kari"
                                 arguments))))
      (is (equal "invalid_input" (refused)) "a title is required")
      (is (equal "invalid_input" (refused "title" "")))
      (is (equal "invalid_input" (refused "title" (make-string 121 :initial-element #\a))))
      (is (equal "invalid_input"
                 (refused "title" "Hei" "body" (make-string 1001 :initial-element #\a))))
      (is (equal "invalid_input"
                 (refused "title" "Hei" "tag" (make-string 65 :initial-element #\a))))
      (dolist (url '("saker/12" "//example.com/x" "/\\example.com/x" "https://example.com/x"))
        (is (equal "invalid_input" (refused "title" "Hei" "url" url)) "the URL ~s" url))
      (is (equal "invalid_input"
                 (refused "title" "Hei"
                          "body" (make-string 1000 :initial-element (code-char #x1F514))))
          "a notification over 3993 octets")
      (is (null (refused "title" "Hei" "url" "/saker/12?vis=alle")))
      (is (null (refused "title" "Hei" "body" (make-string 1000 :initial-element #\ø)))
          "2000 octets fit"))
    (is (= 2 (length (enqueued-jobs 'tun.push:send-push))) "only the good ones were queued")))

;;; ------------------------------------------------------------------
;;; Delivery (spec/push.md 5)

(defun header-value (name headers)
  (cdr (assoc name headers :test #'string-equal)))

(test a-delivered-notification-is-encrypted-for-its-device
  (with-push (service)
    (let ((endpoint (new-endpoint)))
      (subscribe "employee:kari" :endpoint endpoint)
      (notify-device "kari" "body" "Eksporten feiler for Fjord AS" "url" "/saker/itm_12"
                     "tag" "sak:itm_12")
      (is (= 1 (deliver-push)))
      (is (equal '("succeeded") (push-job-states)))
      (destructuring-bind (to headers body) (first (recording-calls service))
        (is (equal endpoint to))
        (is (equal "86400" (header-value "TTL" headers)))
        (is (equal "aes128gcm" (header-value "Content-Encoding" headers)))
        (is (equal "application/octet-stream" (header-value "Content-Type" headers)))
        (multiple-value-bind (token key)
            (authorization-parts (header-value "Authorization" headers))
          (is (token-verifies-p token key)))
        (let ((json (parse-json (sb-ext:octets-to-string
                                 (tun.push:decrypt-push body (b64 +rfc-receiver-private+)
                                                        (b64 +rfc-receiver-public+)
                                                        (b64 +rfc-auth+))
                                 :external-format :utf-8))))
          (is (equal "Ny sak til deg" (jget json "title")))
          (is (equal "Eksporten feiler for Fjord AS" (jget json "body")))
          (is (equal "/saker/itm_12" (jget json "url")))
          (is (equal "sak:itm_12" (jget json "tag"))))))
    (notify-device "kari")
    (deliver-push)
    (let ((json (parse-json (sb-ext:octets-to-string
                             (tun.push:decrypt-push (third (first (recording-calls service)))
                                                    (b64 +rfc-receiver-private+)
                                                    (b64 +rfc-receiver-public+) (b64 +rfc-auth+))
                             :external-format :utf-8))))
      (is (equal "/" (jget json "url")) "/ when no URL is given")
      (is (not (nth-value 1 (gethash "tag" json))) "no tag when none is given"))))

(test a-device-that-is-gone-is-deleted
  (dolist (status '(404 410))
    (with-push (service status)
      (subscribe "employee:kari")
      (notify-device "kari")
      (deliver-push)
      (is (null (subscriptions-named "kari")) "~d deletes the subscription" status)
      (is (equal '("cancelled") (push-job-states))))))

(test a-refused-message-fails-at-once
  (dolist (status '(400 401 403 413))
    (with-push (service status)
      (subscribe "employee:kari")
      (notify-device "kari")
      (deliver-push)
      (is (equal '("failed") (push-job-states)) "~d fails" status)
      (is (= 1 (length (subscriptions-named "kari"))) "and keeps the subscription")
      (is (= 1 (length (recording-calls service)))))))

(test a-temporary-failure-is-tried-again-later
  (with-push (service 429 500 nil 503 429 500 502)
    (subscribe "employee:kari")
    (notify-device "kari")
    (dolist (delay tun.push:+push-retry-delays+)
      (is (= 1 (deliver-push)))
      (is (equal '("retrying") (push-job-states)))
      (let ((due (+ (clock-time) delay)))
        (clock-at (1- due))
        (is (= 0 (deliver-push)) "not before its time")
        (clock-at due)))
    (is (= 1 (deliver-push)) "the seventh attempt")
    (is (equal '("failed") (push-job-states)))
    (is (= 7 (length (recording-calls service))))
    (is (= 1 (length (subscriptions-named "kari"))))))

(test a-job-whose-subscription-is-gone-is-cancelled
  (with-push (service)
    (let ((endpoint (new-endpoint)))
      (subscribe "employee:kari" :endpoint endpoint)
      (notify-device "kari")
      (call-ok "push_unsubscribe" "employee:kari" "endpoint" endpoint)
      (deliver-push)
      (is (equal '("cancelled") (push-job-states)))
      (is (null (recording-calls service)))))
  (with-push (service)
    (subscribe "employee:kari")
    (notify-device "kari")
    ;; A host no longer on the list is not posted to.
    (with-application (*app*)
      (with-transaction (:write)
        (let ((subscription (first (subscriptions-named "kari"))))
          (setf (tun.push:push-subscription-endpoint subscription) "https://box.tail1234.ts.net/x")
          (save subscription))))
    (deliver-push)
    (is (equal '("cancelled") (push-job-states)))
    (is (null (subscriptions-named "kari")))
    (is (null (recording-calls service)))))

(define-application one-push-app ()
  (:queues (:push 1))
  (:default-initargs :name "Ett varsel om gangen"))

(test the-push-queue-runs-two-at-once
  (with-test-app ()
    (is (= 2 (application-queue-limit *app* :push)))
    (is (= 1 (application-queue-limit *app* :mail)) "other queues stay at one"))
  (with-test-app (:class 'one-push-app)
    (is (= 1 (application-queue-limit *app* :push)) "the application's own number wins")))

;;; ------------------------------------------------------------------
;;; The Web Push adapter over HTTP (spec/push.md 5)

(defclass fake-push-service (hunchentoot:acceptor)
  ((answers :initform nil :accessor push-service-answers
            :documentation "The next statuses, in order; then 201.")
   (requests :initform nil :accessor push-service-requests
             :documentation "Each request as a plist, newest first."))
  (:default-initargs :address "127.0.0.1" :access-log-destination nil
                     :message-log-destination nil))

(defmethod hunchentoot:acceptor-dispatch-request ((service fake-push-service) request)
  (push (list :path (hunchentoot:script-name request)
              :headers (hunchentoot:headers-in request)
              :body (hunchentoot:raw-post-data :force-binary t))
        (push-service-requests service))
  (setf (hunchentoot:return-code*) (or (pop (push-service-answers service)) 201))
  "")

(defvar *fake-push-url* nil "Where PUSH-TEST-DELIVER posts.")

(define-operation push-test-deliver ()
    (:kind :read :title "Lever et varsel (test)")
  (multiple-value-bind (status answer)
      (tun.push:deliver-push (make-instance 'tun.push:web-push-service) *fake-push-url*
                             '(("Content-Type" . "application/octet-stream")
                               ("Content-Encoding" . "aes128gcm") ("TTL" . "86400")
                               ("Authorization" . "vapid t=a.b.c, k=BKEY"))
                             (make-array 3 :element-type '(unsigned-byte 8)
                                         :initial-contents '(1 2 3)))
    (jobj "status" (or status :null) "answer" answer)))

(test the-web-push-adapter-posts-over-http
  (let* ((port (free-port))
         (service (make-instance 'fake-push-service :port port)))
    (hunchentoot:start service)
    (unwind-protect
         (with-test-app ()
           (let ((*fake-push-url* (format nil "http://127.0.0.1:~d/push/enhet-hemmelig" port))
                 (*request-id* (new-id "req")))
             (is (= 201 (jget (call-ok "push_test_deliver" "employee:kari") "status")))
             (let* ((request (first (push-service-requests service)))
                    (headers (getf request :headers)))
               (is (equal "/push/enhet-hemmelig" (getf request :path)))
               (is (equalp #(1 2 3) (getf request :body)))
               (is (equal "application/octet-stream" (cdr (assoc :content-type headers))))
               (is (equal "aes128gcm" (cdr (assoc :content-encoding headers))))
               (is (equal "86400" (cdr (assoc :ttl headers))))
               (is (equal "vapid t=a.b.c, k=BKEY" (cdr (assoc :authorization headers)))))
             (let ((step (find "external" (trace-steps *request-id*)
                               :key (lambda (s) (jget s "kind")) :test #'equal)))
               (is (equal (format nil "POST http://127.0.0.1:~d/…" port) (jget step "name")))
               (is (equal "201" (jget step "detail")))
               (is (not (search "hemmelig" (to-json-string step))) "not the device's address")))
           (setf (push-service-answers service) (list 410))
           (let ((*fake-push-url* (format nil "http://127.0.0.1:~d/push/x" port)))
             (is (= 410 (jget (call-ok "push_test_deliver" "employee:kari") "status"))
                 "any status is the port's to judge")))
      (hunchentoot:stop service))
    (with-test-app ()
      (let ((*fake-push-url* (format nil "http://127.0.0.1:~d/push/x" port)))
        (is (json-null-p (jget (call-ok "push_test_deliver" "employee:kari") "status"))
            "no answer from a service that is down")))))

;;; ------------------------------------------------------------------
;;; The paths under /push/ (spec/push.md 2.3), sessions and logging out (3)

(defun session-for (name)
  "Values a new session cookie for the account NAME and the session's id."
  (with-application (*app*)
    (with-transaction (:write)
      (multiple-value-bind (cookie session)
          (tun.auth::start-session (tun.auth:find-account-by-name name))
        (values cookie (entity-id session))))))

(defun session-jar (cookie)
  (make-instance 'drakma:cookie-jar
                 :cookies (list (make-instance 'drakma:cookie :name "tun_session" :value cookie
                                               :domain "127.0.0.1" :path "/"))))

(defun expire-session (id)
  (with-application (*app*)
    (with-transaction (:write)
      (let ((session (fetch 'tun.auth::session id)))
        (setf (tun.auth::session-created-at session) (- (now) (* 31 86400)))
        (save session)))))

(defun post-push (port path jar &rest fields)
  "Values the status and JSON of POST PATH with FIELDS as a form."
  (multiple-value-bind (status body)
      (web-request port path :method :post :jar jar
                   :parameters (loop for (name value) on fields by #'cddr
                                     collect (cons name value)))
    (values status (and (plusp (length body)) (parse-json body)))))

(defun browser-fields (endpoint)
  (list "endpoint" endpoint "p256dh" +rfc-receiver-public+ "auth" +rfc-auth+))

(test the-key-is-public-and-the-rest-needs-a-login
  (with-test-server (port :class 'installable-app :push-service (make-instance 'recording-push))
    (multiple-value-bind (status body headers) (web-request port "/push/key")
      (is (= 200 status))
      (is (search "application/json" (cdr (assoc :content-type headers))))
      (is (equal "no-cache" (cdr (assoc :cache-control headers))))
      (is (= 65 (length (b64 (jget (parse-json body) "key"))))))
    (dolist (path '("/push/subscription" "/push/unsubscribe" "/push/state" "/push/test"))
      (is (= 401 (post-push port path nil)) "~a without a login" path))
    (is (= 403 (web-request port "/push/subscription" :method :post
                            :headers '(("X-Tun-Actor" . "employee:kari")
                                       ("Sec-Fetch-Site" . "cross-site")))))
    (is (= 404 (web-request port "/push/nothing")))
    (let ((jar (web-login port "employee:kari")))
      (multiple-value-bind (status json)
          (apply #'post-push port "/push/subscription" jar (browser-fields (new-endpoint)))
        (is (= 200 status))
        (is (eq t (jget json "on"))))
      (multiple-value-bind (status json)
          (apply #'post-push port "/push/subscription" jar (browser-fields "https://localhost/x"))
        (is (= 422 status))
        (is (equal "invalid_input" (jget (jget json "error") "code")))))
    (is (stringp (tun.push:push-subscription-device (first (subscriptions-named "kari"))))
        "the device is named from its user agent, drakma's here")
    (is (equal "iPhone"
               (tun.push:device-name
                (concatenate 'string "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) "
                             "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 "
                             "Mobile/15E148 Safari/604.1"))))
    (is (equal "Chrome på Android"
               (tun.push:device-name
                (concatenate 'string "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
                             "(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36")))))
  (with-test-server (port)
    (is (= 404 (web-request port "/push/key")) "no key without (:web-app ...)")))

(test logging-out-turns-the-device-off
  (with-test-server (port :class 'installable-app :push-service (make-instance 'recording-push))
    (call-ok "accounts_create" "admin:ada" "name" "kari" "kind" "person" "role" "employee"
             "email" "kari@example.no")
    (let ((made-here (new-endpoint))
          (made-elsewhere (new-endpoint)))
      (multiple-value-bind (cookie-1 session-1) (session-for "kari")
        (multiple-value-bind (cookie-other session-other) (session-for "kari")
          (declare (ignore session-other))
          (apply #'post-push port "/push/subscription" (session-jar cookie-1)
                 (browser-fields made-here))
          (apply #'post-push port "/push/subscription" (session-jar cookie-other)
                 (browser-fields made-elsewhere))
          (is (equal session-1 (tun.push:push-subscription-session
                                (find made-here (subscriptions-named "kari")
                                      :key #'tun.push:push-subscription-endpoint :test #'equal))))
          ;; The first session expires; the person signs in again on that device.
          (expire-session session-1)
          (multiple-value-bind (cookie-2 session-2) (session-for "kari")
            (multiple-value-bind (status json)
                (post-push port "/push/state" (session-jar cookie-2) "endpoint" made-here)
              (is (= 200 status))
              (is (eq t (jget json "on"))))
            (is (equal session-2 (tun.push:push-subscription-session
                                  (find made-here (subscriptions-named "kari")
                                        :key #'tun.push:push-subscription-endpoint
                                        :test #'equal)))
                "checking ties it to the new session")
            (web-request port "/logout" :method :post :jar (session-jar cookie-2))
            (let ((left (mapcar #'tun.push:push-subscription-endpoint
                                (subscriptions-named "kari"))))
              (is (equal (list made-elsewhere) left)
                  "logging out deleted this device's and no other's"))))))))
