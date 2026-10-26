;;;; core/query.lisp -- DEFINE-QUERY: reads written in SQL (spec/store.md 5).
;;;;
;;;; A query is SQL text with two kinds of holes (core/sql-text.lisp):
;;;; {ENTITY} for an entity's table and :NAME for a parameter.  The macro
;;;; splits the text into parts when it is compiled, refusing what the spec
;;;; refuses, and reads no other definition: entities are looked up when
;;;; the query runs, so redefining an entity never leaves a stale query
;;;; behind.  At start the server runs every query once against the real
;;;; database (CHECK-QUERIES), so a renamed column stops the start instead
;;;; of failing a request later.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; The text

(defun split-query-text (text package)
  "TEXT, a query's SQL, as SPLIT-SQL-TEXT gives it; refused unless it is one
SELECT or WITH ... SELECT."
  (unless (member (first-word text) '("SELECT" "WITH") :test #'string=)
    (sql-text-error text 0 "A query is one SELECT or WITH ... SELECT"))
  (split-sql-text text package))

(defun number-parameters (parts parameters)
  "PARTS with each (:PARAMETER NAME) replaced by (:PARAMETER N), N counting
the distinct names in order of first use from 1, and the list of names in
that order.  Every one of PARAMETERS (JSON names) must be used, and no other."
  (let ((order '()))
    (values (mapcar (lambda (part)
                      (if (and (consp part) (eq (first part) :parameter))
                          (let ((name (second part)))
                            (unless (member name parameters :test #'string=)
                              (error "Query uses :~a, which is not one of its parameters" name))
                            (unless (member name order :test #'string=)
                              (setf order (append order (list name))))
                            (list :parameter (1+ (position name order :test #'string=))))
                          part))
                    parts)
            (progn
              (dolist (name parameters)
                (unless (member name order :test #'string=)
                  (error "Query parameter ~a is never used in its text" name)))
              order))))

;;; ------------------------------------------------------------------
;;; Queries

(defclass query ()
  ((name :initarg :name :reader query-name)
   (parameters :initarg :parameters :reader query-parameters
               :documentation "PARAMETER objects, in the order they are declared.")
   (parameter-order :initarg :parameter-order :reader query-parameter-order
                    :documentation "JSON names of the parameters in the order of $1, $2...")
   (parts :initarg :parts :reader query-parts
          :documentation "Strings of SQL, (:ENTITY SYMBOL) and (:PARAMETER N).")
   (returns :initarg :returns :reader query-returns
            :documentation "An entity's symbol, or (:ROWS PARAMETER...) for the columns.")
   (description :initarg :description :reader query-description)
   (source :initarg :source :reader query-source)
   (module :initarg :module :reader query-module)
   (location :initarg :location :reader query-location)))

(defvar *queries* (make-hash-table :test 'eq :synchronized t)
  "Query name -> QUERY, for every DEFINE-QUERY loaded.")

(defun find-query (name)
  "The query named NAME, or NIL."
  (check-type name symbol)
  (gethash name *queries*))

(defun all-queries ()
  "Every defined query, by name."
  (sort (loop for query being the hash-values of *queries* collect query)
        #'string< :key (lambda (query) (symbol-name (query-name query)))))

(defun spec-list (spec)
  "A parameter or column SPEC as a list: a bare NAME is (NAME)."
  (if (consp spec) spec (list spec)))

(defun rows-query-p (query)
  (consp (query-returns query)))

(defmacro define-query (name (&rest parameters) (&key returns description) sql)
  "Define the function NAME, which runs SQL with its PARAMETERS (keyword
arguments) and returns records of the entity RETURNS names, or JSON objects
for RETURNS = (:ROWS (COLUMN :type TYPE)...).  spec/store.md 5."
  (check-type sql string)
  (unless (or (and returns (symbolp returns))
              (and (consp returns) (eq (first returns) :rows) (rest returns)))
    (error "Query ~s needs :returns, an entity or (:rows COLUMN...)" name))
  (let* ((specs (mapcar #'spec-list parameters))
         (names (mapcar #'first specs))
         (json-names (mapcar #'json-name-of names)))
    (multiple-value-bind (parts order)
        (number-parameters (split-query-text sql *package*) json-names)
      `(progn
         (setf (gethash ',name *queries*)
               (make-instance 'query
                              :name ',name
                              :parameters (mapcar #'parse-parameter-spec ',specs)
                              :parameter-order ',order
                              :parts ',parts
                              :returns ,(if (consp returns)
                                            `(cons :rows (mapcar #'parse-parameter-spec
                                                                 ',(mapcar #'spec-list
                                                                           (rest returns))))
                                            `',returns)
                              :description ,description
                              :source ,(current-definition-source)
                              :module ,(current-definition-module)
                              :location ,(current-source-location)))
         (defun ,name (&key ,@names)
           ,(or description (format nil "Run the query ~(~a~)." name))
           (run-query ',name (list ,@(loop for name in names
                                           append (list (intern (symbol-name name) :keyword)
                                                        name)))))))))

;;; ------------------------------------------------------------------
;;; Running one

(defun sql-entity-class (symbol source)
  "The entity class SYMBOL names in SQL text that SOURCE (:CORE or :CLIENT)
defined, refusing one a client may not read (spec/store.md 5.6)."
  (let ((class (find-entity-class symbol nil)))
    (unless (and class (not (entity-embedded-p class)))
      (error "{~(~a~)} is not a stored entity" symbol))
    (when (and (eq source :client)
               (or (entity-internal-p class) (some #'field-secret-p (entity-fields class))))
      (error "{~(~a~)} holds internal or secret data; a client's SQL cannot read it" symbol))
    class))

(defun query-entity-class (query symbol)
  (sql-entity-class symbol (query-source query)))

(defun table-sql (class)
  (let ((table (entity-table class)))
    (unless (cl-ppcre:scan "^[a-z_][a-z0-9_]*$" table)
      (error "Unsafe table name ~s" table))
    (format nil "\"~a\"" table)))

(declaim (ftype (function (t t &key (:check t)) (values string list &optional))
                record-source-sql))

(defun query-sql (query &key check)
  "QUERY's text as Postgres receives it, parameters $N and each {ENTITY} its
table or the records the actor reaches of it (spec/store.md 6.4): (values
SQL VALUES), VALUES those of the parameters record policies add after the
query's own.  CHECK is RECORD-SOURCE-SQL's."
  (let ((added '())
        (next (1+ (length (query-parameter-order query)))))
    (values (with-output-to-string (out)
              (dolist (part (query-parts query))
                (if (stringp part)
                    (write-string part out)
                    (ecase (first part)
                      (:entity
                       (multiple-value-bind (sql values)
                           (record-source-sql (query-entity-class query (second part)) next
                                              :check check)
                         (write-string sql out)
                         (setf added (append added values))
                         (incf next (length values))))
                      (:parameter (format out "$~d" (second part)))))))
            added)))

(defun query-values (query arguments)
  "The stored values for $1, $2... from ARGUMENTS, a plist of keywords."
  (loop for json-name in (query-parameter-order query)
        collect (let* ((parameter (find json-name (query-parameters query)
                                        :key #'parameter-json-name :test #'string=))
                       (type (parameter-type parameter))
                       (value (getf arguments (parameter-keyword parameter))))
                  (cond ((typep type 'boolean-type) (type->db type value))
                        ((null value)
                         (when (parameter-required-p parameter)
                           (error "Query ~(~a~) needs ~(~a~)" (query-name query)
                                  (parameter-name parameter)))
                         nil)
                        ((not (typep value (type-lisp-type type)))
                         (error "Query ~(~a~): ~(~a~) is ~s, not a ~a" (query-name query)
                                (parameter-name parameter) value (type-name type)))
                        (t (type->db type value))))))

(defun expected-columns (query)
  "The column names QUERY's result must have, and those it may have besides."
  (if (rows-query-p query)
      (values (mapcar #'parameter-json-name (rest (query-returns query))) '())
      (let ((class (query-entity-class query (query-returns query))))
        (values (cons "id" (remove "id" (mapcar #'field-json-name (entity-stored-fields class))
                                   :test #'string=))
                '("seq")))))

(defun column-problem (query columns)
  "Why COLUMNS (a result's column names) are not what QUERY returns, or NIL."
  (multiple-value-bind (expected optional) (expected-columns query)
    (let ((missing (set-difference expected columns :test #'string=))
          (extra (set-difference columns (append expected optional) :test #'string=))
          (twice (loop for (column . rest) on columns
                       when (member column rest :test #'string=) collect column)))
      (when (or missing extra twice)
        (format nil "the result's columns are not what :returns says~
                     ~@[; missing ~{~a~^, ~}~]~@[; not expected ~{~a~^, ~}~]~
                     ~@[; twice ~{~a~^, ~}~]"
                missing extra twice)))))

(defun row->record (class columns row)
  (let ((record (make-instance class)))
    (loop for column in columns
          for value in row
          do (cond ((string= column "id") (setf (entity-id record) value))
                   ((string= column "seq"))
                   (t (let ((field (find-field class column)))
                        (setf (field-value record field) (db->type (field-type field) value))))))
    record))

(defun row->object (specs columns row)
  (let ((object (jobj)))
    (dolist (spec specs object)
      (let ((type (parameter-type spec))
            (value (nth (position (parameter-json-name spec) columns :test #'string=) row)))
        (setf (jget object (parameter-json-name spec)) (type->json type (db->type type value)))))))

(defun run-query (name arguments)
  "Run the query NAME with ARGUMENTS, a plist of its parameters' keywords,
in the current transaction: a list of records, or of JSON objects."
  (let ((query (or (find-query name) (error "~s is not a query" name))))
    (assert-in-transaction)
    (check-deadline)
    (when (and *under-eval* (rows-query-p query))
      (error "Query ~(~a~) returns rows, which eval cannot filter by policy" name))
    (multiple-value-bind (rows columns)
        (multiple-value-bind (sql added) (query-sql query)
          (store-query *store* sql (append (query-values query arguments) added)))
      (let ((problem (column-problem query columns)))
        (when problem (error "Query ~(~a~): ~a" name problem)))
      (if (rows-query-p query)
          (let ((specs (rest (query-returns query))))
            (mapcar (lambda (row) (row->object specs columns row)) rows))
          (let* ((class (query-entity-class query (query-returns query)))
                 (records (mapcar (lambda (row) (row->record class columns row)) rows)))
            (if *under-eval*
                (remove-if-not (lambda (record) (entity-readable-p record *actor*)) records)
                records))))))

;;; ------------------------------------------------------------------
;;; Checking every query at start

(defun query-problem (query)
  "Why QUERY cannot run on the current store, or NIL: run once with every
parameter NULL and no rows wanted (spec/store.md 5.7), and each entity with a
record policy in the form the policy gives it (6.6)."
  (handler-case
      (with-transaction (:read)
        (let ((sql (format nil "SELECT * FROM (~a) AS q LIMIT 0" (query-sql query :check t))))
          (column-problem query
                          (nth-value 1 (store-query *store* sql
                                                    (make-list (length (query-parameter-order
                                                                        query))))))))
    (error (e)
      (substitute #\Space #\Newline (princ-to-string e)))))

(defun check-queries ()
  "Refuse to start when any query cannot run on this application's store."
  (when (store-runs-queries-p *store*)
    (let ((problems (loop for query in (all-queries)
                          for problem = (query-problem query)
                          when problem
                          collect (format nil "~(~a~)~@[ (~a)~]: ~a" (query-name query)
                                          (query-location query) problem))))
      (when problems
        (extension-error "Queries that cannot run:~{~%  ~a~}" problems)))))
