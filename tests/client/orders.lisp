;;;; orders.lisp -- hours on order lines: a client field on an embedded entity
;;;; of a module, which reaches the line schemas and the order form.

(in-package #:test-client)

(extend-entity order-line (:name order-line-hours)
  ((hours :type (integer :min 0 :max 100000) :label "Timer"
          :description "Antall timer arbeid på linjen.")))
