;;;; tests/typescript-tests.lisp -- the outputs operations declare
;;;; (spec/core.md 3.11) and the TypeScript module of a single-page screen
;;;; (spec/typescript.md 2, 3): its text, svelte-check's verdict on a Svelte
;;;; component as an operation changes under it, the module run in Node, tun
;;;; typescript on the showcase, and the design tokens a screen links
;;;; (spec/ui.md 3).

(in-package #:tun.tests)

(def-suite typescript :in core)
(in-suite typescript)

;;; ------------------------------------------------------------------
;;; The fixture: an entity and operations of each kind of output

(define-entity ts-note (:label "TS note" :id-prefix "tsn" :table "ts_notes")
  ((title :type (string :min 1 :max 80) :required t :label "Title")
   (status :type (enum "open" "closed") :initform "open" :label "Status")
   (estimate-minor :type money :label "Estimate")
   (done :type boolean :label "Done")
   (tags :type (list-of string) :label "Tags")
   (token :type (string :max 80) :secret t :input nil :label "Token")))

(define-computed-field ts-note shout (note) (:type string :label "Shout")
  (string-upcase (ts-note-title note)))

(defvar *ts-page* nil
  "What ts_notes_page answers in place of its page, when a test makes it lie.")

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter +ts-operations+
    '((define-operation ts-notes-create ((:draft ts-note))
          (:entity ts-note :kind :create :returns ts-note :title "Create a note")
        (insert ts-note))
      (define-operation ts-notes-rename ((id :type (id ts-note) :required t)
                                         (new-title :type (string :min 1 :max 80) :required t))
          (:entity ts-note :kind :update :returns ts-note :title "Rename a note")
        (let ((note (fetch! 'ts-note id)))
          (setf (ts-note-title note) new-title)
          (save note)))
      (define-operation ts-notes-answer ((id :type (id ts-note) :required t)
                                         (answer :type (enum "yes" "no" "later") :required t))
          (:entity ts-note :kind :transition :returns ts-note :title "Answer a note")
        (let ((note (fetch! 'ts-note id)))
          (when (equal answer "yes") (setf (ts-note-status note) "closed"))
          (save note)))
      (define-operation ts-notes-count ()
          (:entity ts-note :kind :read :title "Count the notes"
                   :returns (:object (count (:value integer))
                                     (latest ts-note :optional t)
                                     (titles (:list (:value string)))))
        (let ((notes (select 'ts-note)))
          (jobj "count" (length notes)
                "latest" (if notes (entity->json (car (last notes))) :null)
                "titles" (jarr (mapcar #'ts-note-title notes))))))
    "The fixture's operations a screen calls, as forms, so a test can define a
changed one and then this one again."))

(defmacro define-ts-operations ()
  `(progn ,@+ts-operations+))

(define-ts-operations)

(define-operation ts-notes-page ()
    (:entity ts-note :kind :read :returns (:page ts-note) :title "A page of notes")
  (or *ts-page*
      (let ((notes (select 'ts-note)))
        (jobj "items" (jarr (mapcar #'entity->json notes))
              "returned" (length notes)
              "has_more" nil))))

(define-operation ts-notes-close ((id :type (id ts-note) :required t))
    (:entity ts-note :kind :transition :confirm t :returns ts-note :title "Close a note")
  (let ((note (fetch! 'ts-note id)))
    (setf (ts-note-status note) "closed")
    (save note)))

(define-operation ts-notes-raw ()
    (:kind :read :title "Raw notes")
  (jobj "anything" 1))

(defun ts-operation-form (name)
  (find name +ts-operations+ :key #'second))

;;; ------------------------------------------------------------------
;;; Helpers: a folder of the test's own, tsc and node

(defun ts-folder ()
  "A new, empty folder for one test's files, named for the loop that made
the tests, in the system's temporary directory."
  (let ((folder (uiop:ensure-directory-pathname
                 (format nil "~atypescript-client-~36r-~36r/" (uiop:temporary-directory)
                         (sb-posix:getpid) (random (expt 36 8))))))
    (ensure-directories-exist folder)
    folder))

(defmacro with-ts-folder ((folder) &body body)
  `(let ((,folder (ts-folder)))
     (unwind-protect (progn ,@body)
       (uiop:delete-directory-tree ,folder :validate t :if-does-not-exist :ignore))))

(defparameter +ts-config+
  "{\"compilerOptions\": {\"strict\": true, \"exactOptionalPropertyTypes\": true,
  \"noUnusedLocals\": true, \"noUnusedParameters\": true, \"isolatedModules\": true,
  \"verbatimModuleSyntax\": true, \"target\": \"es2022\", \"module\": \"es2022\",
  \"moduleResolution\": \"bundler\", \"lib\": [\"es2022\", \"dom\"], \"rootDir\": \".\",
  \"outDir\": \"out\", \"newLine\": \"lf\"}, \"include\": [\"*.ts\"]}"
  "The strictest settings a screen's project is likely to take.")

(defun fixture-file (name)
  (asdf:system-relative-pathname "tun" (format nil "tests/typescript/~a" name)))

(defun write-text-file (path text)
  (with-open-file (out path :direction :output :if-exists :supersede :external-format :utf-8)
    (write-string text out))
  path)

(defun copy-fixture (name folder)
  (write-text-file (merge-pathnames name folder)
                   (uiop:read-file-string (fixture-file name) :external-format :utf-8)))

(defun run-command (command)
  "Values the output, standard and error together, and the exit status of COMMAND."
  (multiple-value-bind (output error status)
      (uiop:run-program command :output :string :error-output :string :ignore-error-status t)
    (values (concatenate 'string output error) status)))

(defun run-tsc (folder &rest arguments)
  "Values tsc's output and exit status for the project in FOLDER."
  (run-command (list* "tsc" "-p" (namestring folder) arguments)))

(defun ts-project (folder &rest files)
  "FOLDER made a project of the fixture's module and the fixture's FILES."
  (write-typescript-module folder "fixture")
  (write-text-file (merge-pathnames "tsconfig.json" folder) +ts-config+)
  (dolist (file files) (copy-fixture file folder))
  folder)

(defun screen-node-modules ()
  "The node_modules of the showcase screen's packages, svelte-check, Svelte
and TypeScript among them, which Tun's dev shell names (spec/typescript.md
6.5)."
  (let ((modules (uiop:getenv "TUN_SCREEN_NODE_MODULES")))
    (unless (and modules (probe-file (format nil "~a/svelte-check/bin/svelte-check" modules)))
      (error "TUN_SCREEN_NODE_MODULES names no svelte-check: run inside Tun's nix develop"))
    modules))

(defparameter +svelte-config+
  "{\"compilerOptions\": {\"strict\": true, \"exactOptionalPropertyTypes\": true,
  \"noUnusedLocals\": true, \"noUnusedParameters\": true, \"isolatedModules\": true,
  \"verbatimModuleSyntax\": true, \"target\": \"es2022\", \"module\": \"es2022\",
  \"moduleResolution\": \"bundler\", \"lib\": [\"es2022\", \"dom\"], \"types\": [],
  \"noEmit\": true}, \"include\": [\"*.ts\", \"*.svelte\"]}"
  "The showcase screen's settings, for svelte-check of the fixture's component.")

(defmacro with-svelte-project ((folder &rest files) &body body)
  "Run BODY with FOLDER a new project of the fixture's module, FILES and the
screen's packages, linked as its node_modules; the link is taken away before
the folder, so nothing of the store is touched."
  (let ((link (gensym "LINK")))
    `(with-ts-folder (,folder)
       (let ((,link (namestring (merge-pathnames "node_modules" ,folder))))
         (write-typescript-module ,folder "fixture")
         (write-text-file (merge-pathnames "tsconfig.json" ,folder) +svelte-config+)
         (dolist (file (list ,@files)) (copy-fixture file ,folder))
         (sb-posix:symlink (screen-node-modules) ,link)
         (unwind-protect (progn ,@body)
           (sb-posix:unlink ,link))))))

(defun run-svelte-check (folder)
  "Values svelte-check's output and exit status for the project in FOLDER, a
warning failing it as an error does."
  (run-command (list "node" (format nil "~a/svelte-check/bin/svelte-check" (screen-node-modules))
                     "--workspace" (namestring folder) "--fail-on-warnings")))

(defun ts-file-octets (path)
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence octets in)
      octets)))

;;; ------------------------------------------------------------------
;;; Declared outputs (criteria 1, 2)

(test a-returns-declaration-is-checked-when-compiled
  (flet ((refused-p (returns)
           (handler-case (progn (macroexpand-1 `(define-operation ts-probe () (:returns ,returns) nil))
                                nil)
             (error () t))))
    (is (not (refused-p 'ts-note)) "an entity")
    (is (not (refused-p '(:page ts-note))) "a page")
    (is (not (refused-p '(:object (items (:list ts-note)) (total (:value integer) :optional t))))
        "an object")
    (is (not (refused-p '(:object))) "an object of any keys")
    (is (refused-p '(:list ts-note)) "a list is no result")
    (is (refused-p '(:value string)) "nor a value")
    (is (refused-p :ts-note) "a keyword")
    (is (refused-p '(:page (:list ts-note))) "a page of something but records")
    (is (refused-p '(:object (a ts-note) (a ts-note))) "a key twice")
    (is (refused-p '(:object (a))) "a key without its output")
    (is (refused-p '(:object (a ts-note :maybe t))) "an unknown option")
    (is (refused-p '(:object (a (:value no-such-type)))) "no field type")
    (is (refused-p '(:records ts-note)) "no form")))

(test the-registry-describes-what-an-operation-returns
  (with-test-app ()
    (let ((operations (coerce (jget (call-ok "registry_describe" "viewer:v") "operations") 'list)))
      (let ((schema (jget (find-by "name" "ts_notes_create" operations) "returns")))
        (is (equal "object" (jget schema "type")))
        (is (equal "ts_note" (jget schema "title")))
        (is (equal '("id" "title" "status" "estimate_minor" "done" "tags" "token" "shout")
                   (coerce (jget schema "required") 'list))
            "every field and computed field is always there"))
      (is (equal "array" (jget (jget (jget (jget (find-by "name" "ts_notes_page" operations)
                                                 "returns")
                                           "properties")
                                     "items")
                               "type")))
      (is (json-null-p (jget (find-by "name" "ts_notes_raw" operations) "returns"))
          "null for an operation that declares nothing"))))

(test a-result-that-breaks-its-declaration-fails-under-the-test-clock
  (with-test-app ()
    (call-ok "ts_notes_create" "employee:e" "title" "Milk" "tags" (jarr '("a")))
    (is (= 1 (jget (call-ok "ts_notes_page" "employee:e") "returned")) "a right page answers")
    (is (= 1 (jget (call-ok "ts_notes_count" "employee:e") "count")))
    (flet ((failure (page)
             (let ((*ts-page* page))
               (handler-case (progn (call "ts_notes_page" "employee:e") nil)
                 (operation-error () "an operation error")
                 (error (e) (princ-to-string e))))))
      (let* ((note (entity->json (first (with-application (*app*)
                                          (with-transaction (:read) (select 'ts-note))))))
             (wrong (let ((copy (parse-json (to-json-string note))))
                      (setf (gethash "status" copy) "nope")
                      copy)))
        (let ((message (failure (jobj "items" (jarr (list wrong)) "returned" 1 "has_more" nil))))
          (is (search "ts_notes_page" message) "names the tool: ~a" message)
          (is (search "items[0].status" message) "and where: ~a" message))
        (is (search "has_more" (failure (jobj "items" (jarr '()) "returned" 0)))
            "a key left out")
        (is (search "at items," (failure (jobj "items" "none" "returned" 0 "has_more" nil)))
            "a list that is not one")))
    (multiple-value-bind (json code)
        (call "ts_notes_close" "employee:e"
              "id" (jget (first (coerce (jget (call-ok "ts_notes_page" "employee:e") "items") 'list))
                         "id"))
      (is (null code))
      (is (eq t (jget json "confirmation_required")) "a request for confirmation is not checked")))
  (with-test-app (:test-clock nil)
    (let ((*ts-page* (jobj "items" "none")))
      (is (equal "none" (jget (call-ok "ts_notes_page" "employee:e") "items"))
          "on the real clock nothing is checked"))))

;;; ------------------------------------------------------------------
;;; The module's text (criteria 3 to 7)

(test the-module-is-the-same-bytes-each-time
  (let ((first (typescript-module "fixture")))
    (is (string= first (typescript-module "fixture")))
    (is (eql 0 (search "// api.ts: generated by `tun typescript` from the registry of fixture, Tun core "
                       first)))
    (is (search "Do not edit" first))
    (let ((positions (mapcar (lambda (name) (search (format nil "export function ~a(" name) first))
                             '("accountsCreate" "auditList" "tsNotesAnswer" "tsNotesCreate"))))
      (is (every #'integerp positions))
      (is (equal positions (sort (copy-list positions) #'<)) "functions in the order of their tools"))))

(test the-module-holds-what-a-session-may-call
  (let ((module (typescript-module "fixture")))
    (is (search "export function sessionTestApprove(" module) "a session-only operation")
    (is (search "session only" module))
    (is (not (search "export function clockSet(" module)) "no test-only tool")
    (is (not (search "export function eval(" module)) "no eval-only tool")
    (multiple-value-bind (text operations exact) (typescript-module "fixture")
      (declare (ignore text))
      (is (= operations (count-if-not (lambda (op) (or (operation-test-only-p op)
                                                       (operation-debug-only-p op)
                                                       (tun.core::operation-eval-only-p op)))
                                      (all-operations))))
      (is (= exact (count-if #'operation-returns (all-operations)))))))

(test two-tools-whose-functions-would-meet-stop-the-module
  (unwind-protect
       (progn
         (eval '(define-operation ts-a-b1 () (:kind :read :title "One") (jobj)))
         (eval '(define-operation ts-a-b-1 () (:kind :read :title "Other") (jobj)))
         (let ((message (handler-case (progn (typescript-module "fixture") nil)
                          (error (e) (princ-to-string e)))))
           (is (search "ts_a_b1" message) "~a" message)
           (is (search "ts_a_b_1" message))))
    (dolist (name '(ts-a-b1 ts-a-b-1))
      (remhash name tun.core::*operations*)
      (setf tun.core::*operation-order* (remove name tun.core::*operation-order*)))))

(test json-schema-becomes-typescript
  (flet ((ts (json) (tun.core::schema-typescript (parse-json json))))
    (is (equal "string" (ts "{\"type\": \"string\", \"maxLength\": 3}")))
    (is (equal "\"open\" | \"closed\"" (ts "{\"type\": \"string\", \"enum\": [\"open\", \"closed\"]}")))
    (is (equal "number" (ts "{\"type\": \"integer\"}")))
    (is (equal "number" (ts "{\"type\": \"number\"}")))
    (is (equal "boolean" (ts "{\"type\": \"boolean\"}")))
    (is (equal "null" (ts "{\"type\": \"null\"}")))
    (is (equal "string[]" (ts "{\"type\": \"array\", \"items\": {\"type\": \"string\"}}")))
    (is (equal "Array<\"a\" | \"b\">"
               (ts "{\"type\": \"array\", \"items\": {\"type\": \"string\", \"enum\": [\"a\", \"b\"]}}")))
    (is (equal (format nil "{~%  a: string;~%  /** B */~%  b?: number | null;~%}")
               (ts "{\"type\": \"object\", \"properties\": {\"a\": {\"type\": \"string\"},
                     \"b\": {\"type\": \"integer\", \"description\": \"B\"}}, \"required\": [\"a\"]}")))
    (is (equal (format nil "{~%  \"lines[0]\": string;~%}")
               (ts "{\"type\": \"object\", \"properties\": {\"lines[0]\": {\"type\": \"string\"}},
                     \"required\": [\"lines[0]\"]}"))
        "a key that is no identifier is quoted")
    (is (equal "{ [key: string]: unknown }" (ts "{\"type\": \"object\"}")))
    (is (equal "{ [key: string]: never }"
               (ts "{\"type\": \"object\", \"properties\": {}, \"additionalProperties\": false}")))
    (is (equal "string | null" (ts "{\"anyOf\": [{\"type\": \"string\"}, {\"type\": \"null\"}]}")))
    (is (equal "unknown" (ts "{}")))
    (is (equal "unknown" (ts "{\"anyOf\": [{}, {\"type\": \"null\"}]}")))))

(test the-module-types-inputs-from-their-schema
  (let ((module (typescript-module "fixture")))
    (flet ((has (text) (is (search text module) "the module has ~s" text)))
      (has (format nil "export type TsNotesAnswerInput = {~%"))
      (has (format nil "  answer: \"yes\" | \"no\" | \"later\";~%"))
      (has (format nil "  new_title: string;~%"))
      (has (format nil "  status?: \"open\" | \"closed\" | null;~%"))
      (has (format nil "  request_key?: string | null;~%"))
      (has (format nil "  confirmation_token?: string | null;~%"))
      (has "export type TsNotesRawInput = { [key: string]: never };")
      (has "export function tsNotesRaw(input: TsNotesRawInput = {}, options?: CallOptions)")
      (has "export function tsNotesCreate(input: TsNotesCreateInput, options?: CallOptions)"))))

(test the-module-types-declared-outputs-exactly
  (let ((module (typescript-module "fixture")))
    (flet ((has (text) (is (search text module) "the module has ~s" text)))
      (has (format nil "export interface TsNote {~%  id: string;~%  title: string;~%  ~
                        status: \"open\" | \"closed\" | null;~%  estimate_minor: number | null;~%  ~
                        done: boolean;~%  tags: string[];~%  token: string;~%  ~
                        shout: string | null;~%}"))
      (has "export type TsNotesCreateOutput = TsNote;")
      (has "export type TsNotesPageOutput = Page<TsNote>;")
      (has (format nil "export type TsNotesCountOutput = {~%  count: number;~%  ~
                        latest?: TsNote | null;~%  titles: string[];~%};"))
      (has "export type TsNotesRawOutput = Undeclared;")
      (has "The output is undeclared.")
      (has "Promise<Answer<TsNotesCloseOutput> | Confirm>")
      (has "Promise<Answer<TsNotesCreateOutput>>"))))

(test the-refusal-codes-are-the-api-s
  (is (equal '("forbidden" "invalid_input" "not_found" "conflict" "invalid_transition"
               "unavailable" "insufficient_stock" "confirmation_invalid" "idempotency_conflict"
               "deadline_exceeded" "read_only" "unauthenticated" "unknown_tool" "invalid_json"
               "internal_error")
             (refusal-codes)))
  (let ((module (typescript-module "fixture")))
    (dolist (code (refusal-codes))
      (is (search (format nil "  | ~s" code) module) "RefusalCode has ~a" code))))

;;; ------------------------------------------------------------------
;;; svelte-check and node (typescript-client's criteria 7, 8)

(test svelte-check-takes-the-component-and-refuses-it-once-an-operation-changed
  (with-svelte-project (folder "Screen.svelte")
    (multiple-value-bind (output status) (run-svelte-check folder)
      (is (eql 0 status) "svelte-check accepts the component against its module:~%~a" output))
    (flet ((after-change (change)
             ;; Defining an operation again redefines its generic function,
             ;; which SBCL warns of, as it should here.
             (handler-bind ((warning #'muffle-warning))
               (unwind-protect
                    (progn (eval change)
                           (write-typescript-module folder "fixture")
                           (multiple-value-list (run-svelte-check folder)))
                 (eval (ts-operation-form (second change)))
                 (write-typescript-module folder "fixture")))))
      (loop for (what change) in
            `(("a parameter renamed"
               (define-operation ts-notes-rename ((id :type (id ts-note) :required t)
                                                  (title :type (string :min 1 :max 80) :required t))
                   (:entity ts-note :kind :update :returns ts-note :title "Rename a note")
                 (fetch! 'ts-note id)))
              ("a value taken out of an enum"
               (define-operation ts-notes-answer ((id :type (id ts-note) :required t)
                                                  (answer :type (enum "yes" "no") :required t))
                   (:entity ts-note :kind :transition :returns ts-note :title "Answer a note")
                 (fetch! 'ts-note id)))
              ("a key taken out of a declared output"
               (define-operation ts-notes-count ()
                   (:entity ts-note :kind :read :title "Count the notes"
                            :returns (:object (latest ts-note :optional t)
                                              (titles (:list (:value string)))))
                 (jobj "latest" :null "titles" (jarr '())))))
            do (destructuring-bind (output status) (after-change change)
                 (is (not (eql 0 status)) "~a: svelte-check refuses the component" what)
                 (is (search "Screen.svelte" output) "~a: naming the component's file:~%~a"
                     what output)))
      (multiple-value-bind (output status) (run-svelte-check folder)
        (is (eql 0 status) "and accepts it again once each is as it was:~%~a" output)))))

(test the-module-answers-every-kind-of-answer-in-node
  (with-ts-folder (folder)
    (ts-project folder "runtime.ts")
    (multiple-value-bind (output status) (run-tsc folder)
      (is (eql 0 status) "tsc compiles the module and its driver:~%~a" output))
    (write-text-file (merge-pathnames "out/package.json" folder) "{\"type\": \"module\"}")
    (multiple-value-bind (output status)
        (run-command (list "node" (namestring (merge-pathnames "out/runtime.js" folder))))
      (is (eql 0 status) "node runs it:~%~a" output)
      (let* ((results (parse-json output))
             (request (jget results "request")))
        (flet ((result (name) (jget results name)))
          (is (equal "/api/ts_notes_create" (jget request "url")))
          (is (equal "POST" (jget request "method")))
          (is (equal "same-origin" (jget request "credentials")))
          (is (equal "application/json" (jget (jget request "headers") "Content-Type")))
          (is (equal "PROOF" (jget (jget request "headers") "Tun-Api-Proof"))
              "the proof from the page's meta tag")
          (is (equal "Milk" (jget (jget request "body") "title")) "the input as the body")
          (is (equal "ok" (jget (result "ok") "kind")))
          (is (equal "tsn_1" (jget (jget (result "ok") "value") "id")))
          (let ((confirm (result "confirm")))
            (is (equal "confirm" (jget confirm "kind")))
            (is (equal "tok" (jget (jget confirm "confirmation") "confirmation_token")))
            (is (equal "2026-11-17T10:00:00Z" (jget (jget confirm "confirmation") "expires_at")))
            (is (equal "Close Milk" (jget (jget confirm "confirmation") "summary"))))
          (is (equal "ok" (jget (result "notConfirmable") "kind"))
              "an operation that is not confirmed takes such an answer as its output")
          (let ((refusal (jget (result "refused") "refusal")))
            (is (equal "refused" (jget (result "refused") "kind")))
            (is (equal "invalid_input" (jget refusal "code")))
            (is (= 422 (jget refusal "status")))
            (is (equal "Invalid input" (jget refusal "message")))
            (is (equal "must be filled in is too long" (jget (jget refusal "fields") "title"))
                "two messages of one field, joined")
            (is (equal "must be one of: open, closed" (jget (jget refusal "fields") "status")))
            (is (= 3 (jget (jget refusal "details") "expected_revision")))
            (is (null (nth-value 1 (jget (jget refusal "details") "fields")))))
          (loop for (name reason code) in '(("network" "network" 0) ("aborted" "network" 0)
                                            ("notJson" "answer" 502) ("noDocument" "answer" 500)
                                            ("unknownCode" "answer" 400))
                do (is (equal "failed" (jget (result name) "kind")) "~a fails" name)
                (is (equal reason (jget (jget (result name) "failure") "reason")) "~a" name)
                (is (eql code (jget (jget (result name) "failure") "status")) "~a" name)))))))

;;; ------------------------------------------------------------------
;;; tun typescript (criterion 9)

(defun tun-root () (asdf:system-source-directory "tun"))

(test tun-typescript-writes-the-showcase-screen-s-committed-module
  (with-ts-folder (folder)
    (let ((root (tun-root)))
      (multiple-value-bind (output status)
          (run-command (list (namestring (merge-pathnames "bin/tun" root)) "typescript"
                             (namestring (merge-pathnames "module/" folder))
                             "--dir" (namestring (merge-pathnames "checks/showcase/" root))))
        (is (eql 0 status) "tun typescript runs:~%~a" output)
        (is (search "operations" output) "and says what it wrote: ~a" output))
      (is (equalp (ts-file-octets (merge-pathnames "checks/showcase/screen/src/api.ts" root))
                  (ts-file-octets (merge-pathnames "module/api.ts" folder)))
          "the committed module is what the command writes: run it again and commit it")
      ;; The screen's built files are Nix's (spec/typescript.md 6.5), never git's.
      (multiple-value-bind (output status)
          (run-command (list "git" "-C" (namestring root) "ls-files"
                             "checks/showcase/screen/dist" "checks/showcase/screen/public"))
        (is (eql 0 status) "git ls-files: ~a" output)
        (is (equal "" output) "no built file of the screen is committed: ~a" output)))))

(test tun-typescript-refuses-a-wrong-command-line
  (with-ts-folder (folder)
    (flet ((status (&rest arguments)
             (let ((*standard-output* (make-broadcast-stream))
                   (*error-output* (make-broadcast-stream)))
               (tun.cli:run (cons "typescript" arguments)))))
      (is (= 2 (status)) "no FOLDER")
      (is (= 2 (status (namestring (merge-pathnames "a/" folder))
                       (namestring (merge-pathnames "b/" folder))))
          "two")
      (is (= 2 (status (namestring (merge-pathnames "c/" folder)) "--nope")) "an unknown option")
      (is (= 2 (status (namestring (merge-pathnames "d/" folder)) "--dir" (namestring folder)))
          "a DIR that holds no client")
      (is (null (directory (merge-pathnames "*/" folder))) "and nothing was written"))))

;;; ------------------------------------------------------------------
;;; The design tokens a screen links (spec/ui.md 3)

(defun css-root-properties (css)
  "The custom properties CSS declares in a rule whose selector starts with
:root, as sorted strings \"MEDIA | SELECTOR | --NAME: VALUE\": MEDIA the
@media queries around the rule (an @layer is no part of it), white space
in each part made one space."
  (let ((text (cl-ppcre:regex-replace-all "(?s)/\\*.*?\\*/" css ""))
        (stack '())
        (start 0)
        (found '()))
    (labels ((clean (part) (string-trim " " (cl-ppcre:regex-replace-all "\\s+" part " ")))
             (declaration (end)
               (let* ((rule (first stack))
                      (part (clean (subseq text start end)))
                      (colon (position #\: part)))
                 (when (and rule (string-prefix-p ":root" rule)
                            colon (string-prefix-p "--" part))
                   (push (format nil "~{~a~^ ~} | ~a | ~a: ~a"
                                 (reverse (remove-if-not (lambda (p) (string-prefix-p "@media" p))
                                                         (rest stack)))
                                 rule (clean (subseq part 0 colon))
                                 (clean (subseq part (1+ colon))))
                         found)))))
      (loop for i from 0 below (length text)
            do (case (char text i)
                 (#\{ (push (clean (subseq text start i)) stack) (setf start (1+ i)))
                 (#\; (declaration i) (setf start (1+ i)))
                 (#\} (declaration i) (pop stack) (setf start (1+ i)))))
      (sort found #'string<))))

(test the-tokens-file-holds-the-pages-tokens-and-nothing-else
  (let ((pages (css-root-properties (tun.ui:stylesheet)))
        (file (css-root-properties (tun.ui:tokens-stylesheet))))
    (is (< 60 (length file)) "the tokens are read: ~d" (length file))
    (is (equal pages file)
        "the same custom properties on :root, each with its value, selector and media query:~%~
only the pages': ~s~%only the file's: ~s"
        (set-difference pages file :test #'string=) (set-difference file pages :test #'string=))
    (is (member " | :root | --background: light-dark(#ffffff, #19191c)" file :test #'string=)
        "light and dark in one value")
    (is (member "@media (pointer: coarse) | :root | --control-height: 2.75rem" file
                :test #'string=)
        "under its media query")
    (is (find-if (lambda (p) (search "--primary: light-dark(#171717, #ededed)" p)) file)))
  (is (equal (list " | :root | --a: 1" " | :root | --b: light-dark(1, 2)")
             (css-root-properties "@layer tokens { :root { --a: 1; /* x */ --b: light-dark(1,
  2) } } body { --c: 3; }"))
      "the reader: comments, layers and other rules left out")
  (is (not (equal (css-root-properties ":root { --a: 1; }")
                  (css-root-properties ":root { --a: 2; }")))
      "a value that differs is a difference"))

(test the-tokens-file-is-served-to-anyone
  (with-test-server (port)
    (multiple-value-bind (status body headers) (web-request port "/assets/tokens.css")
      (is (= 200 status) "signed out")
      (is (equal (tun.ui:tokens-stylesheet) body))
      (is (equal "text/css; charset=utf-8" (header-of headers :content-type)))
      (is (equal "no-cache" (header-of headers :cache-control)))
      (is (equal "nosniff" (header-of headers :x-content-type-options))))
    (is (= 200 (web-request port "/assets/tokens.css" :jar (web-login port "employee:anna")))
        "signed in")))
