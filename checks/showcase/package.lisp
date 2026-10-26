;;;; package.lisp -- the showcase's package: Common Lisp and Tun's public
;;;; interface, as a client's.

(defpackage #:showcase
  (:use #:cl #:tun)
  (:local-nicknames (#:ui #:tun.ui))
  (:export #:*application-class* #:showcase))
