;;;; core/counts.lisp -- counts by key, each held to a bound: how many
;;;; connections, requests or waits one client holds at once (core.md §7.5,
;;;; spec/waiting.md 1).  A key's entry lives only while its count is above
;;;; zero, so the table is never larger than what is held at that moment.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defclass key-counts ()
  ((name :initarg :name :reader key-counts-name)
   (lock :reader key-counts-lock)
   (table :initform (make-hash-table :test 'equal) :reader key-counts-table
          :documentation "Key -> how many it holds, for keys holding at least one."))
  (:documentation "Counts by key, such as a client's address, guarded by one mutex."))

(defmethod initialize-instance :after ((counts key-counts) &key)
  (setf (slot-value counts 'lock)
        (sb-thread:make-mutex :name (format nil "~a counts" (key-counts-name counts)))))

(defun make-key-counts (name)
  "Empty counts by key; NAME says what they count, for the mutex's name."
  (make-instance 'key-counts :name name))

(defun take-count (counts key bound)
  "Count one more for KEY in COUNTS when it holds fewer than BOUND, or
whatever it holds when BOUND is NIL.  True when it was counted; NIL, and
nothing counted, when KEY holds BOUND already."
  (sb-thread:with-mutex ((key-counts-lock counts))
    (let ((held (gethash key (key-counts-table counts) 0)))
      (when (or (null bound) (< held bound))
        (setf (gethash key (key-counts-table counts)) (1+ held))
        t))))

(defun give-back-count (counts key)
  "Count one less for KEY in COUNTS: what a TAKE-COUNT that answered true took."
  (sb-thread:with-mutex ((key-counts-lock counts))
    (let ((held (gethash key (key-counts-table counts) 0)))
      (if (> held 1)
          (setf (gethash key (key-counts-table counts)) (1- held))
          (remhash key (key-counts-table counts))))))

(defun key-count (counts key)
  "How many KEY holds in COUNTS now."
  (sb-thread:with-mutex ((key-counts-lock counts))
    (gethash key (key-counts-table counts) 0)))
