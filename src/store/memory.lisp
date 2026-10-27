;;;; store/memory.lisp -- in-memory adapter for the store port.
;;;;
;;;; Rows are kept in their database encoding (TYPE->DB), so entities
;;;; round-trip exactly as they do through SQLite and callers never share
;;;; mutable state with the store.  One recursive mutex serializes all
;;;; transactions; an undo log implements rollback and savepoints.

(defpackage #:tun.store.memory
  (:use #:cl #:tun.core)
  (:export #:memory-store))

(in-package #:tun.store.memory)

(declaim (optimize (safety 3) (debug 2)))

(defclass memory-store (store)
  ((tables :initform (make-hash-table :test 'eq) :reader memory-tables)
   (seq :initform 0 :accessor memory-seq)
   (lock :initform (sb-thread:make-mutex :name "memory store") :reader memory-lock)
   (undo :initform '() :accessor memory-undo)
   (contents :initform (make-hash-table :test 'equal) :reader memory-contents
             :documentation "Files' content by attachment id (spec/files.md 5.1).")))

(defmethod store-description ((store memory-store)) "memory")
(defmethod store-open ((store memory-store)) store)
(defmethod store-close ((store memory-store)) store)
(defmethod store-migrate ((store memory-store) classes) (declare (ignore classes)) store)

(defmethod store-describe-schema ((store memory-store))
  ;; No tables: the shapes the entity classes give, and no migrations.
  (values (jarr (loop for class in (all-entity-classes)
                      unless (entity-embedded-p class)
                        collect (jobj "name" (entity-table class)
                                      "columns" (jarr (list* (jobj "name" "seq" "type" "INTEGER" "nullable" nil)
                                                             (loop for field in (entity-stored-fields class)
                                                                   collect (jobj "name" (field-json-name field)
                                                                                 "type" (type-sql (field-type field))
                                                                                 "nullable" (json-bool (not (string= (field-json-name field) "id"))))))))))
          (jarr '())))

(defun table (store class-name)
  "Rows of CLASS-NAME: a list of (seq . row-hash) in insertion order (newest first internally)."
  (gethash class-name (memory-tables store)))

(defun (setf table) (rows store class-name)
  (setf (gethash class-name (memory-tables store)) rows))

(defmethod store-call-in-transaction ((store memory-store) function mode)
  (let ((wait-start (trace-clock-us)))
   (sb-thread:with-recursive-lock ((memory-lock store))
    (when (eq mode :write) (note-write-lock-wait (- (trace-clock-us) wait-start)))
    (let ((mark (memory-undo store))
          (ok nil))
      (unwind-protect
           (multiple-value-prog1 (funcall function)
             (setf ok t))
        (unless ok
          ;; Undo everything logged since MARK, newest first.
          (loop until (eq (memory-undo store) mark)
                do (funcall (pop (memory-undo store)))))
        (when (and ok (null mark))
          (setf (memory-undo store) '())))))))

(defun log-undo (store thunk)
  (push thunk (memory-undo store)))

(defun entity->row (entity)
  (let ((row (make-hash-table :test 'equal)))
    (dolist (field (entity-stored-fields (class-of entity)) row)
      (setf (gethash (field-json-name field) row)
            (type->db (field-type field) (field-value entity field))))))

(defun row->entity (class-name seq row)
  (declare (ignore seq))
  (let ((instance (make-instance class-name)))
    (dolist (field (entity-stored-fields (class-of instance)) instance)
      (setf (field-value instance field)
            (db->type (field-type field) (gethash (field-json-name field) row))))))

(defun check-unique (store class-name row &optional except-seq)
  (let ((class (find-class class-name)))
    (dolist (columns (entity-unique class))
      (dolist (entry (table store class-name))
        (when (and (not (eql (car entry) except-seq))
                   (every (lambda (c) (let ((v (gethash c row)))
                                        (and v (equal v (gethash c (cdr entry))))))
                          columns))
          (fail :conflict "Finnes allerede (~{~a~^, ~} må være unik)" columns))))
    (let ((id (gethash "id" row)))
      (dolist (entry (table store class-name))
        (when (and id (not (eql (car entry) except-seq)) (equal id (gethash "id" (cdr entry))))
          (fail :conflict "Id ~a finnes allerede" id))))))

(defmethod store-insert ((store memory-store) entity)
  (let* ((class-name (class-name (class-of entity)))
         (row (entity->row entity))
         (seq (incf (memory-seq store))))
    (check-unique store class-name row)
    (push (cons seq row) (table store class-name))
    (log-undo store (lambda () (setf (table store class-name)
                                     (remove seq (table store class-name) :key #'car))))
    entity))

(defun find-entry (store class-name id)
  (find id (table store class-name) :key (lambda (e) (gethash "id" (cdr e))) :test #'equal))

(defmethod store-update ((store memory-store) entity)
  (let* ((class-name (class-name (class-of entity)))
         (entry (or (find-entry store class-name (entity-id entity))
                    (error "Update of missing ~a ~a" class-name (entity-id entity))))
         (old (cdr entry))
         (row (entity->row entity)))
    (check-unique store class-name row (car entry))
    (setf (cdr entry) row)
    (log-undo store (lambda () (setf (cdr entry) old)))
    entity))

(defmethod store-delete ((store memory-store) class-name id)
  (let ((before (table store class-name)))
    (setf (table store class-name) (remove id before :key (lambda (e) (gethash "id" (cdr e))) :test #'equal))
    (log-undo store (lambda () (setf (table store class-name) before)))
    t))

(defmethod store-find ((store memory-store) class-name id)
  (let ((entry (find-entry store class-name id)))
    (and entry (row->entity class-name (car entry) (cdr entry)))))

(defmethod store-lock-row ((store memory-store) class-name id)
  (declare (ignore class-name id))
  ;; Every transaction already holds the store mutex.
  t)

;;; WHERE evaluation over db-encoded rows.

(defun compare (op a b)
  (cond ((or (null a) (null b)) nil)
        ((and (realp a) (realp b))
         (ecase op (:< (< a b)) (:<= (<= a b)) (:> (> a b)) (:>= (>= a b))))
        (t (let ((a (princ-to-string a)) (b (princ-to-string b)))
             (ecase op (:< (string< a b)) (:<= (string<= a b)) (:> (string> a b)) (:>= (string>= a b)))))))

(defun matches-p (class seq row where)
  (if (null where)
      t
      (destructuring-bind (op &rest args) where
        (flet ((col (name) (if (string= name "seq") seq (gethash name row)))
               (val (name v) (where-value->db class name v)))
          (ecase op
            (:and (every (lambda (w) (matches-p class seq row w)) args))
            (:or (some (lambda (w) (matches-p class seq row w)) args))
            (:= (let ((v (val (first args) (second args)))) (and v (equal (col (first args)) v))))
            (:/= (let ((c (col (first args)))) (and c (not (equal c (val (first args) (second args)))))))
            ((:< :<= :> :>=) (compare op (col (first args)) (val (first args) (second args))))
            (:in (member (col (first args)) (mapcar (lambda (v) (val (first args) v)) (second args))
                         :test #'equal))
            (:null (null (col (first args))))
            (:not-null (not (null (col (first args))))))))))

(defun entry-key (entry column)
  (if (string= column "seq") (car entry) (gethash column (cdr entry))))

(defun value< (a b)
  (cond ((null a) (not (null b)))     ; NULLs first, as in SQLite
        ((null b) nil)
        ((and (realp a) (realp b)) (< a b))
        (t (string< (princ-to-string a) (princ-to-string b)))))

(defmethod store-select ((store memory-store) class-name &key where order-by limit offset)
  (let* ((class (find-class class-name))
         (entries (remove-if-not (lambda (e) (matches-p class (car e) (cdr e) where))
                                 (reverse (table store class-name))))
         (order (append order-by '(("seq" :asc)))))
    (dolist (spec order) (where-field class (first spec)))
    (setf entries
          (stable-sort entries
                       (lambda (x y)
                         (loop for (column direction) in order
                               for a = (entry-key x column)
                               for b = (entry-key y column)
                               do (cond ((value< a b) (return (eq direction :asc)))
                                        ((value< b a) (return (eq direction :desc))))
                               finally (return nil)))))
    (when offset (setf entries (nthcdr offset entries)))
    (when limit (setf entries (subseq entries 0 (min limit (length entries)))))
    (mapcar (lambda (e) (row->entity class-name (car e) (cdr e))) entries)))

;;; Files' content (spec/files.md 5.1), kept apart from the rows as the
;;; Postgres store keeps it in a table of its own.

(defmethod store-write-content ((store memory-store) id octets)
  (assert-writable)
  (let ((contents (memory-contents store)))
    (multiple-value-bind (old present) (gethash id contents)
      (setf (gethash id contents) (copy-seq octets))
      (log-undo store (lambda ()
                        (if present
                            (setf (gethash id contents) old)
                            (remhash id contents))))))
  id)

(defmethod store-read-content ((store memory-store) id start length)
  (let ((octets (gethash id (memory-contents store))))
    (and octets
         (subseq octets (min start (length octets)) (min (+ start length) (length octets))))))

(defmethod store-delete-content ((store memory-store) id)
  (assert-writable)
  (let ((contents (memory-contents store)))
    (multiple-value-bind (old present) (gethash id contents)
      (when present
        (remhash id contents)
        (log-undo store (lambda () (setf (gethash id contents) old))))))
  t)

;;; Each store call is one "store" step of the current request (core.md §8.2);
;;; there is no SQL, so the step names the operation and the entity.

(defmacro define-traced-store-call (gf lambda-list description)
  `(defmethod ,gf :around ,lambda-list
     (let ((started (trace-clock-us)))
       (multiple-value-prog1 (call-next-method)
         (note-store-statement ,description started)))))

(define-traced-store-call store-insert ((store memory-store) entity)
  (format nil "INSERT ~(~a~)" (class-name (class-of entity))))
(define-traced-store-call store-update ((store memory-store) entity)
  (format nil "UPDATE ~(~a~)" (class-name (class-of entity))))
(define-traced-store-call store-delete ((store memory-store) class-name id)
  (format nil "DELETE ~(~a~) ~a" class-name id))
(define-traced-store-call store-find ((store memory-store) class-name id)
  (format nil "FIND ~(~a~) ~a" class-name id))
(define-traced-store-call store-write-content ((store memory-store) id octets)
  (progn octets (format nil "WRITE CONTENT ~a" id)))
(define-traced-store-call store-read-content ((store memory-store) id start length)
  (format nil "READ CONTENT ~a ~d ~d" id start length))
(define-traced-store-call store-delete-content ((store memory-store) id)
  (format nil "DELETE CONTENT ~a" id))
(define-traced-store-call store-select ((store memory-store) class-name &key where order-by limit offset)
  (progn where order-by limit offset (format nil "SELECT ~(~a~)" class-name)))
