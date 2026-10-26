;;;; package.lisp -- the client's package. It uses Common Lisp and Tun's
;;;; public interface, the TUN package, and names TUN.UI, the components its
;;;; pages are built from, as UI.

(defpackage #:{{name}}
  (:use #:cl #:tun)
  (:local-nicknames (#:ui #:tun.ui))
  (:export #:*application-class* #:{{name}}))
