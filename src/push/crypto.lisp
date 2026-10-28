;;;; push/crypto.lisp -- Web Push's cryptography (spec/push.md 6).
;;;;
;;;; A push message is encrypted for one browser with its P-256 key and
;;;; authentication secret, in the aes128gcm content coding (RFC 8291,
;;;; RFC 8188), and carries a VAPID token, a JWT signed with ES256, that
;;;; proves which server sent it (RFC 8292).  Ironclad does the curve
;;;; arithmetic, ECDSA, AES-GCM and HMAC; HKDF (RFC 5869) is written out
;;;; here, since Web Push needs no more than one block of it.
;;;;
;;;; Keys are octet vectors: a private key is its 32-octet scalar, a public
;;;; key its uncompressed point, 0x04 followed by x and y (65 octets).

(in-package #:tun.push)

(declaim (optimize (safety 3) (debug 2)))

(deftype octets () '(simple-array (unsigned-byte 8) (*)))

(define-condition push-message-too-large (error)
  ((size :initarg :size :reader push-message-too-large-size)
   (largest :initarg :largest :reader push-message-too-large-largest))
  (:report (lambda (c s)
             (format s "A push message holds at most ~d octets, not ~d"
                     (push-message-too-large-largest c) (push-message-too-large-size c))))
  (:documentation "A plaintext too long for the one record of a push message."))

(define-condition push-message-not-authentic (error) ()
  (:report "The push message's tag does not verify: it was changed, or is for another key")
  (:documentation "A push message that does not decrypt with the receiver's key."))

(defun octets (&rest parts)
  "PARTS joined into one octet vector: each an octet vector, an ASCII text
or one octet as an integer."
  (apply #'concatenate 'octets
         (mapcar (lambda (part)
                   (etypecase part
                     (string (sb-ext:string-to-octets part :external-format :ascii))
                     ((integer 0 255) (vector part))
                     (vector part)))
                 parts)))

(defun hmac-sha256 (key data)
  "HMAC-SHA-256 of DATA under KEY, both octets."
  (let ((mac (ironclad:make-hmac key :sha256)))
    (ironclad:update-hmac mac data)
    (ironclad:hmac-digest mac)))

(defun hkdf-sha256 (salt ikm info length)
  "LENGTH octets of key material from IKM, SALT and INFO, by HKDF with
SHA-256 (RFC 5869): extract a pseudorandom key, then expand it.  LENGTH is
at most 32, one block of the expansion, which is all Web Push takes."
  (check-type length (integer 1 32))
  (let ((prk (hmac-sha256 salt ikm)))
    (subseq (hmac-sha256 prk (octets info 1)) 0 length)))

;;; ------------------------------------------------------------------
;;; P-256

(defparameter +p256-generator+
  (ironclad:hex-string-to-byte-array
   (concatenate 'string
                "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
                "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"))
  "The generator of P-256 (SEC 2, 2.4.2), as an uncompressed point.")

(defparameter +p256-order+
  #xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
  "n, the number of points the generator reaches (SEC 2, 2.4.2).")

(defun private-key-object (private public)
  "Ironclad's key for the scalar PRIVATE, with PUBLIC beside it.  Ironclad
keeps both in one object; ECDH and signing use only the scalar."
  (ironclad:make-private-key :secp256r1 :x private :y public))

(defun public-key-object (public)
  (ironclad:make-public-key :secp256r1 :y public))

(defun point-times (private public)
  "The point PUBLIC multiplied by the scalar PRIVATE, uncompressed.  This is
what ironclad's Diffie-Hellman computes; it signals an error when PUBLIC is
not a point on the curve."
  (ironclad:diffie-hellman (private-key-object private public) (public-key-object public)))

(defun p256-public-key (private)
  "The public key of the scalar PRIVATE: the generator multiplied by it."
  (point-times private +p256-generator+))

(defun p256-key-pair ()
  "Values a new random private key and its public key."
  (let ((private (getf (ironclad:destructure-private-key
                        (ironclad:generate-key-pair :secp256r1))
                       :x)))
    (values private (p256-public-key private))))

(defun p256-point-p (public)
  "True when PUBLIC, octets, is an uncompressed point on P-256."
  (and (typep public 'octets)
       (= (length public) 65)
       (= (aref public 0) 4)
       (handler-case (progn (point-times (ironclad:integer-to-octets 1 :n-bits 256) public) t)
         (error () nil))))

(defun ecdh-secret (private public)
  "The shared secret of ECDH between the scalar PRIVATE and the point
PUBLIC: the x coordinate of their product, 32 octets."
  (subseq (point-times private public) 1 33))

;;; ------------------------------------------------------------------
;;; Encryption (RFC 8291 3.3, 3.4; RFC 8188 2)

(defparameter +record-size+ 4096
  "The record size the header announces.  The message is one record, so it
also bounds what one message holds.")

(defparameter +push-header-octets+ 86
  "The header: salt (16), record size (4), key length (1), the sender's
public key (65).")

(defun combined-key (auth ecdh-secret receiver-public sender-public)
  "IKM, the key that combines the ECDH secret with the browser's
authentication secret AUTH (RFC 8291 3.3)."
  (hkdf-sha256 auth ecdh-secret (octets "WebPush: info" 0 receiver-public sender-public) 32))

(defun content-key (salt ikm)
  "CEK, the AES-128-GCM key of the record (RFC 8188 2.2)."
  (hkdf-sha256 salt ikm (octets "Content-Encoding: aes128gcm" 0) 16))

(defun content-nonce (salt ikm)
  "NONCE, the nonce of the record, the first and only (RFC 8188 2.3)."
  (hkdf-sha256 salt ikm (octets "Content-Encoding: nonce" 0) 12))

(defun aes-gcm-mode (key nonce)
  (ironclad:make-authenticated-encryption-mode :gcm :cipher-name :aes :key key
                                               :initialization-vector nonce))

(defun encrypt-push (plaintext receiver-public auth &key sender-private sender-public salt)
  "PLAINTEXT, octets, encrypted for the browser whose key is RECEIVER-PUBLIC
and whose authentication secret is AUTH: the request body, the header and
then one aes128gcm record.  A new key pair and salt are made unless given,
as the RFC's example gives them.  Signals PUSH-MESSAGE-TOO-LARGE when
PLAINTEXT does not fit one record."
  (let ((largest (- +record-size+ +push-header-octets+ 17)))
    (unless (<= (length plaintext) largest)
      (error 'push-message-too-large :size (length plaintext) :largest largest)))
  (multiple-value-bind (private public)
      (if sender-private (values sender-private sender-public) (p256-key-pair))
    (let* ((salt (or salt (ironclad:random-data 16)))
           (ikm (combined-key auth (ecdh-secret private receiver-public) receiver-public public))
           (mode (aes-gcm-mode (content-key salt ikm) (content-nonce salt ikm)))
           ;; 2 is the delimiter that ends the last record; no padding follows.
           (ciphertext (ironclad:encrypt-message mode (octets plaintext 2))))
      (octets salt (ironclad:integer-to-octets +record-size+ :n-bits 32)
              (length public) public
              ciphertext (ironclad:produce-tag mode)))))

(defun decrypt-push (body receiver-private receiver-public auth)
  "The plaintext of BODY, a message ENCRYPT-PUSH made for RECEIVER-PUBLIC,
as the browser decrypts it with its private key and AUTH.  Signals
PUSH-MESSAGE-NOT-AUTHENTIC when the tag does not verify."
  (let* ((salt (subseq body 0 16))
         (key-length (aref body 20))
         (sender-public (subseq body 21 (+ 21 key-length)))
         (record (subseq body (+ 21 key-length) (- (length body) 16)))
         (tag (subseq body (- (length body) 16)))
         (ikm (combined-key auth (ecdh-secret receiver-private sender-public)
                            receiver-public sender-public))
         (mode (aes-gcm-mode (content-key salt ikm) (content-nonce salt ikm)))
         (padded (ironclad:decrypt-message mode record)))
    (unless (equalp tag (ironclad:produce-tag mode))
      (error 'push-message-not-authentic))
    ;; The plaintext ends at the last delimiter; only zeros of padding follow it.
    (subseq padded 0 (position 2 padded :from-end t))))

;;; ------------------------------------------------------------------
;;; VAPID (RFC 8292) and Tun's key (spec/push.md 6.2, 6.3)

(defparameter +vapid-secret-setting+ "push.secret"
  "The secret setting Tun's key pair is derived from.")

(define-setting "push.secret"
    (:type "secret"
           :description "Tun's key for notifications on the phone (VAPID) is made from this. If it changes, every device must turn notifications on again."))

(defun vapid-private-key (secret)
  "The private key derived from SECRET, a text: 1 + (HMAC-SHA-256 under the
secret's UTF-8 octets of «tun web push vapid», as an integer, mod n - 1),
so it is never 0 and below n."
  (let* ((mac (hmac-sha256 (sb-ext:string-to-octets secret :external-format :utf-8)
                           (octets "tun web push vapid")))
         (scalar (1+ (mod (ironclad:octets-to-integer mac) (1- +p256-order+)))))
    (ironclad:integer-to-octets scalar :n-bits 256)))

(defun vapid-keys ()
  "Values Tun's private and public key, derived from the setting
push.secret as it is now."
  (let ((private (vapid-private-key (setting-value-at-use +vapid-secret-setting+))))
    (values private (p256-public-key private))))

(defun vapid-public-key-text ()
  "Tun's public key in base64url: the applicationServerKey browsers subscribe with."
  (base64url (nth-value 1 (vapid-keys))))

(defparameter +unix-epoch+ 2208988800
  "The Unix epoch in universal time: a JWT's times are seconds since it.")

(defparameter +vapid-lifetime+ (* 12 3600)
  "How long a token is good for.  RFC 8292 allows at most 24 hours.")

(defparameter +vapid-header+ "{\"typ\":\"JWT\",\"alg\":\"ES256\"}"
  "The token's header, written out so its octets are always the same.")

(defun vapid-token (audience expires subject private)
  "A VAPID token for AUDIENCE, the push service's origin, valid until
EXPIRES (universal time), naming SUBJECT (a URL, or NIL for none), signed
with PRIVATE by ES256: the signature is R and S, 32 octets each."
  (let* ((claims (apply #'jobj "aud" audience "exp" (- expires +unix-epoch+)
                        (and subject (list "sub" subject))))
         (input (format nil "~a.~a"
                        (base64url (octets +vapid-header+))
                        (base64url (sb-ext:string-to-octets (to-json-string claims)
                                                            :external-format :utf-8))))
         (digest (ironclad:digest-sequence :sha256 (octets input))))
    (format nil "~a.~a" input
            (base64url (ironclad:sign-message (private-key-object private +p256-generator+)
                                              digest)))))

(defun endpoint-origin (endpoint)
  "The scheme, host and port of ENDPOINT: a VAPID token's audience."
  (subseq endpoint 0 (or (position #\/ endpoint :start (length "https://")) (length endpoint))))

(defun vapid-subject ()
  "The token's sub: the server's public URL when it is https, else NIL."
  (let ((url (application-public-url *application*)))
    (and url (string-prefix-p "https://" url) url)))

(defun vapid-authorization (endpoint)
  "The Authorization header's value for a message to ENDPOINT:
vapid t=TOKEN, k=KEY (RFC 8292 3)."
  (multiple-value-bind (private public) (vapid-keys)
    (format nil "vapid t=~a, k=~a"
            (vapid-token (endpoint-origin endpoint) (+ (now) +vapid-lifetime+) (vapid-subject)
                         private)
            (base64url public))))
