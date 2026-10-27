;;;; tests/fixtures/files-heap-server.lisp -- a server for the memory tests
;;;; of spec/files.md 4.3 and 5.4, in a process of its own so its heap is
;;;; the image's default: sbcl --dynamic-space-size 2048 --load this --port N.
;;;; It prints "ready" once it listens.

(load (merge-pathnames "../../scripts/setup.lisp" *load-truename*))
(in-package #:tun-build)

(load-quietly "tun")

(defpackage #:files-heap
  (:use #:cl #:tun.core))
(in-package #:files-heap)

(define-entity heap-note (:label "Notat" :id-prefix "hpn" :table "heap_notes"
                                 :attachments (:max 100))
  ((title :type (string :max 200) :label "Tittel")))

(define-operation heap-notes-create ((:draft heap-note))
    (:entity heap-note :kind :create :policy :employee :title "Nytt notat")
  (insert heap-note))

(define-operation heap-notes-get ((id :type (id heap-note) :required t))
    (:entity heap-note :kind :read :policy :viewer :title "Notat")
  (fetch! 'heap-note id))

(defun heap-page (method path form query)
  "A note's files, posted as a page's form is: NOTE names the note."
  (declare (ignore path query))
  (if (eq method :post)
      (multiple-value-bind (json code)
          (tun.web:web-call "attachments_add" (jobj "entity" "heap_note"
                                                    "record_id" (jget form "note")
                                                    "files" (jget form "filer")))
        (values (if code 422 200) "Filer"
                (list (princ-to-string (if code "nei" (length (jget json "items")))))))
      (values 200 "Filer" (list "skjema"))))

(tun.web:register-staff-page "heap" 'heap-page :policy :employee)

(define-operation heap-live-bytes ()
    (:entity heap-note :kind :read :policy :viewer :title "Levende haug")
  "The live heap after a full collection, for a test to see that it stays flat."
  (sb-ext:gc :full t)
  (jobj "bytes" (sb-kernel:dynamic-usage)))

(define-operation heap-fault ((text :type (string :max 1048576)))
    (:entity heap-note :kind :read :policy :viewer :title "Feil med tekst")
  "Fail with TEXT in the error's message: a fault whose message a caller wrote."
  (error "Feil: ~a" text))

(defun heap-fault-page (method parts form session)
  "A public page that fails with the posted TEXT in the error's message."
  (declare (ignore method parts session))
  (error "Feil i skjema: ~a" (jget form "text")))

(tun.web:register-public-page "feilside" 'heap-fault-page)

(define-operation heap-consed ()
    (:entity heap-note :kind :read :policy :viewer :title "Tildelt")
  "Octets allocated since the image started, for a test to see what a request costs."
  (jobj "bytes" (sb-ext:get-bytes-consed)))

(defvar *peak* 0 "The highest heap use seen since the last HEAP-PEAK.")

(sb-thread:make-thread (lambda ()
                         (loop (setf *peak* (max *peak* (sb-kernel:dynamic-usage)))
                               (sleep 0.002)))
                       :name "heap peak")

(define-operation heap-peak ()
    (:entity heap-note :kind :read :policy :viewer :title "Høyeste haug")
  "The highest heap use, garbage included, seen since the last call."
  (prog1 (jobj "bytes" *peak*)
    (setf *peak* (sb-kernel:dynamic-usage))))

(define-operation heap-records ()
    (:entity heap-note :kind :read :policy :viewer :title "Poster")
  "How many finished request records there are, and the most text one keeps."
  (let ((records (finished-requests)))
    (jobj "count" (length records)
          "most_octets" (reduce #'max records :key #'tun.core::request-record-octets
                                              :initial-value 0))))

;;; End with the test that started this server: when it is gone, its end of
;;; standard input closes.
(sb-thread:make-thread (lambda ()
                         (loop while (read-char *standard-input* nil nil))
                         (sb-ext:exit :abort t))
                       :name "parent watch")

(let* ((port (parse-integer (second (member "--port" sb-ext:*posix-argv* :test #'string=))))
       (application (tun.runtime:open-application 'application :identity :claimed :test-clock t)))
  (tun.http:start-server application :port port)
  (format t "~&ready~%")
  (finish-output)
  (loop (sleep 60)))
