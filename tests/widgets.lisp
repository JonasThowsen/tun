;;;; tests/widgets.lisp -- a test-only entity and operations used to exercise
;;;; the safety layer independently of the business modules.

(in-package #:tun.tests)

(define-entity widget (:label "Dings" :id-prefix "wdg" :table "widgets" :revisioned t)
  ((revision :type (integer :min 1) :input nil :initform 1 :label "Revisjon")
   (name :type (string :min 1 :max 50) :required t :label "Navn")
   (status :type (enum "aktiv" "arkivert") :input nil :initform "aktiv" :label "Status")
   (created-at :type timestamp :input nil :label "Opprettet")))

(define-operation widgets-create ((:draft widget))
    (:entity widget :kind :create :title "Lag dings")
  (insert widget))

(define-operation widgets-get ((id :type (id widget) :required t))
    (:entity widget :kind :read :title "Hent dings")
  (fetch! 'widget id))

(define-operation widgets-count ()
    (:entity widget :kind :read :title "Tell dingser")
  (jobj "count" (length (select 'widget))))

(defun widget-archive-summary ()
  (let ((w (fetch! 'widget (input-value :id))))
    (format nil "Arkiver dingsen «~a»" (widget-name w))))

(define-operation widgets-archive ((id :type (id widget) :required t))
    (:entity widget :kind :transition :confirm t :title "Arkiver dings"
     :summary widget-archive-summary)
  (let ((w (fetch! 'widget id)))
    (unless (string= (widget-status w) "aktiv")
      (fail :invalid-transition "Dingsen er allerede arkivert"))
    (setf (widget-status w) "arkivert")
    (save w)))

(define-operation widgets-purge ((id :type (id widget) :required t))
    (:entity widget :kind :transition :policy :admin :title "Slett dings")
  (let ((w (fetch! 'widget id)))
    (delete-entity w)
    (jobj "deleted" id)))

(define-operation widgets-explode ((:draft widget))
    (:entity widget :kind :create :title "Lag dings og feil")
  ;; Writes, then fails: the write and its audit entry must both roll back.
  (insert widget)
  (fail :conflict "Bevisst feil etter skriving"))

(define-operation widgets-sneaky-read ((name :type string :required t))
    (:entity widget :kind :read :title "Les (og forsøk å skrive)")
  ;; A read operation runs in a read transaction: any write is refused.
  (insert (make-instance 'widget :name name)))

;;; Review regressions: code running inside a request must not be able to
;;; confirm on the caller's behalf.
(define-operation widgets-archive-now ((id :type (id widget) :required t))
    (:entity widget :kind :transition :title "Arkiver uten å spørre (skal feile)")
  (let ((first (invoke 'widgets-archive "id" id)))
    (invoke 'widgets-archive "id" id "confirmation_token" (jget first "confirmation_token"))))

;;; Method order fixture: a core-level :before/:after and a feature mixin's.
(defvar *touch-log* '())
(define-operation widgets-touch ((id :type (id widget) :required t))
    (:entity widget :kind :update :title "Rør dings")
  (push :primary *touch-log*)
  (fetch! 'widget id))

;;; Fixtures for the deadline tests (core.md §7.1).
(define-operation widgets-slow-create ((:draft widget))
    (:entity widget :kind :create :title "Lag dings sakte")
  ;; Writes, then waits (cooperatively) past any short deadline.
  (insert widget)
  (sleep-with-deadline 5000)
  widget)

(defvar *spin-sink* 0)

(define-operation widgets-spin ((ms :type integer :required t))
    (:entity widget :kind :read :title "Spinn uten fristsjekk")
  ;; A runaway loop that never reaches a deadline check: only the watchdog
  ;; can stop it.
  (let ((end (+ (get-internal-real-time) (round (* ms internal-time-units-per-second) 1000)))
        (x 0))
    (declare (type fixnum x))
    (loop while (< (get-internal-real-time) end)
          do (setf x (logand (+ x 3) #xffff)))
    (setf *spin-sink* x)
    (jobj "spun" ms)))

;;; Fixture for fault isolation (core.md §7.4): a serious condition that is
;;; not an ERROR, raised inside an operation after it has written.
(defun widgets-recurse (n) (1+ (widgets-recurse (1+ n))))

(define-operation widgets-overflow ((:draft widget))
    (:entity widget :kind :create :title "Lag dings og sprenge stakken")
  (insert widget)
  (widgets-recurse 0))
