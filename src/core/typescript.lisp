;;;; core/typescript.lisp -- the TypeScript module of a single-page screen
;;;; (spec/typescript.md 3): the types of every operation's input, written
;;;; from the JSON Schema tools/list and /api validate with, and of its
;;;; output, from what it declares (outputs.lisp); one function per
;;;; operation; and the call, which answers refusals and failures as values.
;;;; A third projection of the registry beside MCP and /api.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +transport-refusal-codes+
  '("unauthenticated" "unknown_tool" "invalid_json" "internal_error")
  "The codes /api answers besides the operations' own (spec/api.md 3).")

(defun refusal-codes ()
  "Every code an error document from /api has (spec/typescript.md 3.4): the
operations' ERROR-CODEs and the transport's."
  (append (mapcar #'json-name-of (member-type-set 'error-code)) +transport-refusal-codes+))

(defparameter +runtime-type-names+
  '("Answer" "Confirm" "Confirmation" "RefusalCode" "Refusal" "Failure" "Page" "Undeclared"
    "CallOptions")
  "The names of the module's own types; a record type that would take one is
named with Record after it (spec/typescript.md 3.1).")

;;; ------------------------------------------------------------------
;;; Names (spec/typescript.md 3.1)

(defun name-parts (json-name)
  (remove "" (cl-ppcre:split "_" json-name) :test #'string=))

(defun pascal-name (json-name)
  "JSON-NAME, snake_case, in PascalCase: customers_list is CustomersList."
  (format nil "~{~@(~a~)~}" (name-parts json-name)))

(defun camel-name (json-name)
  "JSON-NAME, snake_case, in camelCase: customers_list is customersList."
  (let ((parts (name-parts json-name)))
    (format nil "~(~a~)~{~@(~a~)~}" (first parts) (rest parts))))

(defun record-type-name (class)
  "The interface of a record of the entity CLASS."
  (let ((name (pascal-name (entity-json-name class))))
    (if (member name +runtime-type-names+ :test #'string=)
        (concatenate 'string name "Record")
        name)))

(defun typescript-identifier-p (name)
  (and (cl-ppcre:scan "^[A-Za-z_$][A-Za-z0-9_$]*$" name) t))

(defun typescript-key (name)
  "NAME as a property's key: as it is when it is an identifier, else quoted."
  (if (typescript-identifier-p name) name (to-json-string name)))

(defun comment-text (text)
  "TEXT on one line, safe inside a /** */ comment."
  (cl-ppcre:regex-replace-all "\\*/" (cl-ppcre:regex-replace-all "\\s+" (string-trim " " text) " ")
                              "* /"))

;;; ------------------------------------------------------------------
;;; JSON Schema to TypeScript (spec/typescript.md 3.2)

(defun indentation (depth) (make-string (* 2 depth) :initial-element #\Space))

(defun union-type (members)
  "The union of the TypeScript types MEMBERS, each once, in their order;
unknown absorbs the rest.  A member that is itself a union of plain types
is taken apart; one with braces or angle brackets is kept whole."
  (let ((parts (remove-duplicates
                (loop for member in members
                      append (if (find-if (lambda (c) (find c "{}<>()")) member)
                                 (list member)
                                 (cl-ppcre:split " \\| " member)))
                :test #'string= :from-end t)))
    (cond ((member "unknown" parts :test #'string=) "unknown")
          (t (format nil "~{~a~^ | ~}" parts)))))

(defun array-type (item)
  (if (cl-ppcre:scan "^[A-Za-z0-9_$<>]+$" item)
      (format nil "~a[]" item)
      (format nil "Array<~a>" item)))

(defun object-type (members depth)
  "An object type of MEMBERS, each (KEY TYPE OPTIONAL DESCRIPTION), its
lines indented for DEPTH."
  (with-output-to-string (out)
    (format out "{~%")
    (dolist (member members)
      (destructuring-bind (key type optional description) member
        (when (and description (plusp (length (string-trim " " description))))
          (format out "~a/** ~a */~%" (indentation (1+ depth)) (comment-text description)))
        (format out "~a~a~:[~;?~]: ~a;~%" (indentation (1+ depth)) (typescript-key key) optional
                (if optional (union-type (list type "null")) type))))
    (format out "~a}" (indentation depth))))

(defun schema-typescript (schema &optional (depth 0))
  "The TypeScript type of a value SCHEMA, a JSON Schema as Tun writes them,
describes: a required property is NAME: T, another NAME?: T | null."
  (let ((forms (jget schema "anyOf"))
        (type (jget schema "type"))
        (choices (jget schema "enum")))
    (cond (forms (union-type (map 'list (lambda (form) (schema-typescript form depth)) forms)))
          (choices (format nil "~{~a~^ | ~}" (map 'list #'to-json-string choices)))
          ((equal type "string") "string")
          ((member type '("integer" "number") :test #'equal) "number")
          ((equal type "boolean") "boolean")
          ((equal type "null") "null")
          ((equal type "array")
           (array-type (if (jget schema "items")
                           (schema-typescript (jget schema "items") depth)
                           "unknown")))
          ((equal type "object")
           (let ((properties (jget schema "properties"))
                 (required (coerce (or (jget schema "required") #()) 'list)))
             (cond ((and properties (plusp (hash-table-count properties)))
                    (object-type (loop for key in (jkeys properties)
                                       for property = (gethash key properties)
                                       collect (list key (schema-typescript property (1+ depth))
                                                     (not (member key required :test #'string=))
                                                     (jget property "description")))
                                 depth))
                   ;; additionalProperties false: nothing may be given.
                   ((multiple-value-bind (more present) (jget schema "additionalProperties")
                      (and present (null more)))
                    "{ [key: string]: never }")
                   (t "{ [key: string]: unknown }"))))
          (t "unknown"))))

;;; ------------------------------------------------------------------
;;; Outputs (spec/typescript.md 3.3)

(defun output-entities (form)
  "The entity classes the output FORM names a record of."
  (cond ((symbolp form) (list (output-entity-class form)))
        (t (ecase (first form)
             (:page (list (output-entity-class (second form))))
             (:list (output-entities (second form)))
             (:object (loop for entry in (rest form) append (output-entities (second entry))))
             (:value '())))))

(defun output-typescript (form &optional (depth 0))
  "The TypeScript type of the output FORM declares."
  (cond ((symbolp form) (record-type-name (output-entity-class form)))
        (t (ecase (first form)
             (:page (format nil "Page<~a>" (record-type-name (output-entity-class (second form)))))
             (:list (array-type (output-typescript (second form) depth)))
             (:object (if (rest form)
                          (object-type (loop for entry in (rest form)
                                             collect (destructuring-bind (key output &key optional)
                                                         entry
                                                       (list (json-name-of key)
                                                             (output-typescript output (1+ depth))
                                                             optional nil)))
                                       depth)
                          "{ [key: string]: unknown }"))
             (:value (schema-typescript (type-output-schema (parse-field-type (second form)))
                                        depth))))))

;;; ------------------------------------------------------------------
;;; The module

(defparameter +typescript-runtime+
  "export type Answer<T> =
  | { kind: \"ok\"; value: T }
  | { kind: \"refused\"; refusal: Refusal }
  | { kind: \"failed\"; failure: Failure };

export type Confirm = { kind: \"confirm\"; confirmation: Confirmation };

export interface Confirmation {
  confirmation_token: string;
  expires_at: string;
  summary: unknown;
}

export interface Refusal {
  /** The error document's code. */
  code: RefusalCode;
  /** The HTTP status. */
  status: number;
  /** The message, in the language of the person's pages. */
  message: string;
  /** invalid_input: each field's message by the field's path, as a form shows it. */
  fields: { [field: string]: string };
  /** The error document's other keys. */
  details: { [key: string]: unknown };
}

export interface Failure {
  /** network: no answer came; answer: one came that is not the API's. */
  reason: \"network\" | \"answer\";
  /** The HTTP status, 0 when no answer came. */
  status: number;
  message: string;
}

export interface Page<T> {
  items: T[];
  returned: number;
  has_more: boolean;
}

/** The output of an operation that declares none: declare :returns to make it exact. */
export type Undeclared = { [key: string]: unknown };

export interface CallOptions {
  signal?: AbortSignal;
}

type Json = { [key: string]: unknown };

function isObject(value: unknown): value is Json {
  return typeof value === \"object\" && value !== null && !Array.isArray(value);
}

function proof(): string {
  const meta = document.querySelector('meta[name=\"tun-api-proof\"]');
  return meta?.getAttribute(\"content\") ?? \"\";
}

function refusalOf(status: number, error: Json, code: RefusalCode): Refusal {
  const fields: { [field: string]: string } = {};
  const details: { [key: string]: unknown } = {};
  for (const [key, value] of Object.entries(error)) {
    if (key !== \"code\" && key !== \"message\" && key !== \"fields\") details[key] = value;
  }
  const given = error[\"fields\"];
  if (Array.isArray(given)) {
    for (const entry of given) {
      if (!isObject(entry)) continue;
      const field = entry[\"field\"];
      const message = entry[\"message\"];
      if (typeof field !== \"string\" || typeof message !== \"string\") continue;
      fields[field] = Object.hasOwn(fields, field) ? fields[field] + \" \" + message : message;
    }
  }
  const text = error[\"message\"];
  return { code, status, message: typeof text === \"string\" ? text : \"\", fields, details };
}

function failed(reason: \"network\" | \"answer\", status: number, message: string): Answer<never> {
  return { kind: \"failed\", failure: { reason, status, message } };
}

async function call<R>(tool: string, input: object, confirmable: boolean,
                       options?: CallOptions): Promise<R> {
  return (await answer(tool, input, confirmable, options)) as unknown as R;
}

async function answer(tool: string, input: object, confirmable: boolean,
                      options?: CallOptions): Promise<Answer<unknown> | Confirm> {
  let response: Response;
  try {
    response = await fetch(\"/api/\" + tool, {
      method: \"POST\",
      credentials: \"same-origin\",
      headers: { \"Content-Type\": \"application/json\", \"Tun-Api-Proof\": proof() },
      body: JSON.stringify(input),
      signal: options?.signal ?? null,
    });
  } catch (error) {
    return failed(\"network\", 0, String(error));
  }
  let body: unknown;
  try {
    body = await response.json();
  } catch (error) {
    return failed(\"answer\", response.status, \"The answer is not JSON: \" + String(error));
  }
  if (response.ok) {
    if (confirmable && isObject(body) && body[\"confirmation_required\"] === true) {
      return {
        kind: \"confirm\",
        confirmation: {
          confirmation_token: String(body[\"confirmation_token\"]),
          expires_at: String(body[\"expires_at\"]),
          summary: body[\"summary\"],
        },
      };
    }
    return { kind: \"ok\", value: body };
  }
  const error = isObject(body) ? body[\"error\"] : undefined;
  const code = isObject(error) ? error[\"code\"] : undefined;
  if (isObject(error) && typeof code === \"string\" && isRefusalCode(code)) {
    return { kind: \"refused\", refusal: refusalOf(response.status, error, code) };
  }
  return failed(\"answer\", response.status, \"The answer holds no error document\");
}
"
  "The module's own types and its call (spec/typescript.md 3.4, 3.5).")

(defun module-operations ()
  "The operations the module has a function for (spec/typescript.md 2):
every one but the test-only, debug-only and eval-only, by tool name."
  (sort (remove-if (lambda (op) (or (operation-test-only-p op) (operation-debug-only-p op)
                                    (operation-eval-only-p op)))
                   (all-operations))
        #'string< :key #'operation-tool))

(defun check-module-names (operations classes)
  "Refuse a module in which two functions or two types would have one name."
  (let ((seen (make-hash-table :test 'equal)))
    (flet ((claim (name owner)
             (let ((other (gethash name seen)))
               (when other
                 (error "tun typescript: ~a and ~a would both be ~a in the module" other owner name))
               (setf (gethash name seen) owner))))
      (dolist (name +runtime-type-names+) (claim name "the module's own type"))
      (dolist (op operations)
        (let ((tool (operation-tool op)))
          (claim (camel-name tool) tool)
          (claim (format nil "~aInput" (pascal-name tool)) tool)
          (claim (format nil "~aOutput" (pascal-name tool)) tool)))
      (dolist (class classes)
        (claim (record-type-name class) (format nil "the entity ~a" (entity-json-name class)))))))

(defun write-operation (out op)
  "OP's input and output types and its function, to OUT."
  (let* ((tool (operation-tool op))
         (type (pascal-name tool))
         (schema (operation-input-schema op))
         (required (plusp (length (jget schema "required"))))
         (returns (operation-returns op))
         (result (if (operation-confirm-p op)
                     (format nil "Answer<~aOutput> | Confirm" type)
                     (format nil "Answer<~aOutput>" type))))
    (format out "~%export type ~aInput = ~a;~%" type (schema-typescript schema))
    (format out "~%export type ~aOutput = ~a;~%" type
            (if returns (output-typescript returns) "Undeclared"))
    (format out "~%/** ~a (~a; ~(~a~)~:[~;, session only~]~:[~;, confirmed~])~:[ The output is undeclared.~;~] */~%"
            (comment-text (let ((description (operation-description op)))
                            (if (plusp (length description)) description (operation-title op))))
            tool (operation-policy op) (operation-session-only-p op) (operation-confirm-p op)
            returns)
    (format out "export function ~a(input: ~aInput~:[ = {}~;~], options?: CallOptions): Promise<~a> {~%"
            (camel-name tool) type required result)
    (format out "  return call<~a>(~a, input, ~:[false~;true~], options);~%}~%"
            result (to-json-string tool) (operation-confirm-p op))))

(defun typescript-module (name)
  "The text of the TypeScript module of the client NAME's registry, as `tun
typescript` writes it (spec/typescript.md 3).  The same registry gives the
same text.  Values the text, the number of operations, and how many of them
declare their output."
  (let* ((operations (module-operations))
         (classes (sort (remove-duplicates
                         (loop for op in operations
                               when (operation-returns op)
                               append (output-entities (operation-returns op))))
                        #'string< :key #'record-type-name)))
    (check-module-names operations classes)
    (values
     (with-output-to-string (out)
       (format out "// api.ts: generated by `tun typescript` from the registry of ~a, Tun core ~a.~%"
               name +core-version+)
       (format out "// Do not edit: change the operations and run `tun typescript` again ~
                    (spec/typescript.md).~%~%")
       (write-string +typescript-runtime+ out)
       (format out "~%export type RefusalCode =~%~{  | ~s~^~%~};~%" (refusal-codes))
       (format out "~%const refusalCodes: readonly string[] = [~{~s~^, ~}];~%" (refusal-codes))
       (format out "~%function isRefusalCode(code: string): code is RefusalCode {~%  ~
                    return refusalCodes.includes(code);~%}~%")
       (dolist (class classes)
         (format out "~%/** A record of ~a. */~%export interface ~a ~a~%"
                 (entity-json-name class) (record-type-name class)
                 (schema-typescript (entity-output-schema class))))
       (dolist (op operations)
         (write-operation out op)))
     (length operations)
     (count-if #'operation-returns operations))))

(defun write-typescript-module (folder name)
  "Write FOLDER/api.ts, the module of the client NAME (TYPESCRIPT-MODULE),
making FOLDER when it does not exist.  Values the file's path, the number of
operations and how many declare their output."
  (multiple-value-bind (text operations exact) (typescript-module name)
    (let ((path (merge-pathnames "api.ts" (uiop:ensure-directory-pathname folder))))
      (ensure-directories-exist path)
      (with-open-file (out path :direction :output :if-exists :supersede
                           :external-format :utf-8)
        (write-string text out))
      (values path operations exact))))
