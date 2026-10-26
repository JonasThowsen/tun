;;;; package.lisp -- the client package uses CL and the public TUN package only.

(defpackage #:test-client
  (:use #:cl #:tun)
  (:export #:*application-class* #:nordvik
           #:loyalty-tier-for #:tier-discount-percent))
