;;;; tun-reviews.asd -- the reviews module (tun-platform.md 2; README).

(defsystem "tun-reviews"
  :description "tun module reviews: a generic review workflow with kind handlers."
  :version "1.0.0"
  :depends-on ("tun")
  :serial t
  :components ((:file "reviews")
               (:file "nb")))
