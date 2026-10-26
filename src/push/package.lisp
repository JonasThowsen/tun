;;;; push/package.lisp -- TUN.PUSH: push notifications to an installed app
;;;; (spec/push.md).
;;;;
;;;; crypto.lisp has Web Push's cryptography: the encryption of a message
;;;; for one browser (RFC 8291) and the VAPID token that says who sends it
;;;; (RFC 8292).  push.lisp has the subscriptions, NOTIFY-PUSH, the job
;;;; that delivers each notification and the port it delivers through.

(defpackage #:tun.push
  (:use #:cl #:tun.core)
  (:import-from #:tun.auth #:base64url #:base64url-octets #:find-account-by-name
                #:account-name #:account-status)
  (:import-from #:tun.jobs #:define-job #:enqueue-job #:cancel-job #:fail-job)
  (:export
   ;; the cryptography (crypto.lisp)
   #:hkdf-sha256 #:p256-public-key #:ecdh-secret #:combined-key #:content-key #:content-nonce
   #:encrypt-push #:decrypt-push #:+record-size+ #:+push-header-octets+
   #:push-message-too-large #:push-message-not-authentic
   #:vapid-private-key #:vapid-keys #:vapid-public-key-text #:vapid-token #:vapid-authorization
   ;; subscriptions, sending and delivery (push.lisp)
   #:push-subscription #:push-subscription-account #:push-subscription-endpoint
   #:push-subscription-session #:push-subscription-server-key #:push-subscription-device
   #:push-service-endpoint #:+push-service-hosts+ #:device-name
   #:notify-push #:send-push #:+push-retry-delays+ #:+push-time-limit+ #:+push-ttl+
   #:+most-notification-octets+
   #:push-service #:deliver-push #:web-push-service #:log-push-service
   #:forget-session-subscriptions
   #:push-subscribe #:push-unsubscribe #:push-check #:push-devices #:push-test))
