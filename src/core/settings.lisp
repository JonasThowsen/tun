;;;; Typed, declared tenant settings. Values are read from the store at use
;;;; time, or from an environment variable for a setting declared with :env
;;;; (spec/outbound.md 3), which is never stored.
(in-package #:tun.core)

(defstruct setting-declaration key type default nullable min max module source description env)
(defvar *setting-declarations* (make-hash-table :test 'equal))
(defvar *setting-initial-values* (make-hash-table :test 'equal))

(defmacro define-setting-initial-value (key value)
  "A client's first-start value; never replaces a tenant's stored choice."
  `(setf (gethash ,key *setting-initial-values*) ,value))

(defmacro define-setting (key (&key type default nullable min max description env))
  "Declare a tenant setting; duplicate keys owned by different definitions are
refused.  With ENV, the name of an environment variable, the value is that
variable's, read at use time."
  `(register-setting ,key ,type ,default ,nullable ,min ,max
                     ,(current-definition-module) ,(current-definition-source) ,description ,env))

(defparameter +environment-setting-types+ '("string" "secret" "url" "email")
  "The types a setting read from the environment can have: those a text is.")

(defparameter +locale-setting-types+ '("language" "currency" "time_zone")
  "The types of core's locale settings (spec/i18n.md 9): their default and
their values come from the application's (:locale ...) and Tun's tables.")

(defun register-setting (key type default nullable min max module source description env)
  (unless (member type (list* "string" "bool" "int" "email" "url" "actor" "secret"
                              (and (equal module "core") +locale-setting-types+))
                  :test #'equal)
    (extension-error "Setting ~a has unknown type ~a" key type))
  (when env
    (unless (and (stringp env) (cl-ppcre:scan "^[A-Za-z_][A-Za-z0-9_]*$" env))
      (extension-error "Setting ~a: :env names an environment variable, not ~s" key env))
    (unless (member type +environment-setting-types+ :test #'equal)
      (extension-error "Setting ~a: a ~a setting cannot come from the environment, only ~{~a~^, ~}"
                       key type +environment-setting-types+)))
  (let ((old (gethash key *setting-declarations*)))
    (when old (extension-error "Setting ~a is already declared by ~a" key (setting-declaration-module old)))
    (setf (gethash key *setting-declarations*)
          (make-setting-declaration :key key :type type :default default :nullable nullable
                                    :min min :max max :module module :source source :description description
                                    :env env))))

(defun declared-setting (key)
  (or (gethash key *setting-declarations*) (fail :not-found "The setting ~a is not declared" key)))

(defun setting-default (decl)
  "What the setting DECL declares holds when nothing is stored: its default,
or for a locale setting the application's (spec/i18n.md 9)."
  (let ((type (setting-declaration-type decl)))
    (if (member type +locale-setting-types+ :test #'equal)
        (let ((locale (default-locale *application*)))
          (cond ((equal type "language") (locale-language locale))
                ((equal type "currency") (locale-currency locale))
                (t (locale-time-zone locale))))
        (setting-declaration-default decl))))

(defun environment-setting-value (decl)
  "The value of the setting DECL declares from the environment: the
variable's, else the default.  A value that does not fit the setting's type
is an error naming the variable, not the value, which may be a secret."
  (let ((text (uiop:getenv (setting-declaration-env decl))))
    (cond ((zerop (length text)) (setting-default decl))
          ((setting-value-valid-p decl text) text)
          (t (error "The environment variable ~a does not hold a valid ~a for the setting ~a"
                    (setting-declaration-env decl) (setting-declaration-type decl)
                    (setting-declaration-key decl))))))

(defun current-setting-value (decl)
  "The value of the setting DECL declares: from the environment, else the
store, else the default."
  (if (setting-declaration-env decl)
      (environment-setting-value decl)
      (let ((row (select-one 'setting :where `(:= "key" ,(setting-declaration-key decl)))))
        (if row (setting-value row) (setting-default decl)))))

(defun setting-value-at-use (key &optional fallback)
  "Read a declared setting's current value; FALLBACK applies only to undeclared keys."
  (let ((decl (gethash key *setting-declarations*)))
    (if decl
        (let ((value (current-setting-value decl)))
          (if (json-null-p value) nil value))
        fallback)))

(defgeneric setting-actor-exists-p (application actor)
  (:method (application actor) (declare (ignore application actor)) nil))
(register-extension-protocol 'setting-actor-exists-p "rule" :point "setting_actor"
                             :description "Validate an actor setting through the employee directory.")

(defun secret-setting-p (key)
  (let ((declaration (gethash key *setting-declarations*)))
    (and declaration (equal "secret" (setting-declaration-type declaration)))))

(defun setting-public-value (decl)
  (let ((value (current-setting-value decl)))
    (if (and (null value)
             (or (setting-declaration-nullable decl) (setting-declaration-env decl))
             (not (equal "bool" (setting-declaration-type decl))))
        :null
        value)))

(defun setting-json (decl &key (value t))
  (let* ((secret (equal (setting-declaration-type decl) "secret"))
         (object (jobj "key" (setting-declaration-key decl) "type" (setting-declaration-type decl)
                       "default" (if secret "***" (let ((default (setting-declaration-default decl)))
                                                     (if (and (null default) (setting-declaration-nullable decl)) :null default)))
                       "module" (setting-declaration-module decl)
                       "source" (source-string (setting-declaration-source decl))
                       "description" (or (setting-declaration-description decl) "") "secret" (json-bool secret))))
    (when (setting-declaration-env decl)
      (setf (gethash "env" object) (setting-declaration-env decl)))
    (when value
      (setf (gethash "value" object)
            (let ((value (setting-public-value decl)))
              ;; A secret from the environment shows whether it is set.
              (if (and secret (not (json-null-p value))) "***" value))))
    object))

(defun setting-texts ()
  "Each declared setting's description, for people, as (DESCRIPTION MODULE
KEY), for the checks of spec/i18n.md 3.7."
  (loop for decl being the hash-values of *setting-declarations*
        when (plusp (length (or (setting-declaration-description decl) "")))
          collect (list (setting-declaration-description decl) (setting-declaration-module decl)
                        (setting-declaration-key decl))))

(defun settings-description (&key (value t))
  (mapcar (lambda (key) (setting-json (declared-setting key) :value value))
          (sort (loop for k being the hash-keys of *setting-declarations* collect k) #'string<)))

(defun initialise-settings ()
  (with-transaction (:write)
    (maphash (lambda (key decl)
               (when (and (equal "secret" (setting-declaration-type decl))
                          (null (setting-declaration-env decl))
                          (null (select-one 'setting :where `(:= "key" ,key))))
                 (write-setting key (sha256-hex (new-secret-token)))))
             *setting-declarations*)
    (maphash (lambda (key value)
               (let ((decl (gethash key *setting-declarations*)))
                 (when (and decl (null (setting-declaration-env decl))
                            (null (select-one 'setting :where `(:= "key" ,key))))
                   (validate-setting-value decl value)
                   (write-setting key value))))
             *setting-initial-values*)))

(defun setting-value-valid-p (decl value)
  "True when VALUE fits the setting DECL declares."
  (let ((type (setting-declaration-type decl)))
    (and (or (and (json-null-p value) (setting-declaration-nullable decl))
             (cond ((member type '("string" "secret") :test #'equal)
                    (and (stringp value) (not (blank-p value))
                         (<= (length value) 2000)
                         (notany (lambda (c) (< (char-code c) 32)) value)))
                   ((equal type "bool") (or (null value) (eq value t)))
                   ((equal type "int") (and (integerp value)
                                            (<= (or (setting-declaration-min decl) most-negative-fixnum) value
                                                (or (setting-declaration-max decl) most-positive-fixnum))))
                   ((equal type "email") (and (stringp value) (cl-ppcre:scan "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$" value)
                                              (notany (lambda (c) (member c '(#\Return #\Newline))) value)))
                   ((equal type "url") (and (stringp value) (cl-ppcre:scan "^https?://[^\\s]+$" value)))
                   ((equal type "language")
                    (and (stringp value)
                         (or (member value (application-languages *application*) :test #'equal)
                             ;; The checks' pseudo-language, with the test clock only.
                             (and (equal value +pseudo-language+)
                                  (typep (application-clock *application*) 'test-clock)))))
                   ((equal type "currency") (currency-p value))
                   ((equal type "time_zone") (time-zone-p value))
                   ((equal type "actor") (and (stringp value) (setting-actor-exists-p *application* value)))))
         t)))

(defun validate-setting-value (decl value)
  (unless (setting-value-valid-p decl value)
    (fail :invalid-input "Invalid value for the setting ~a (~a)"
          (setting-declaration-key decl) (setting-declaration-type decl))))

(define-setting "links.secret"
    (:type "secret" :description "Signs links sent to customers. Changing it voids every link sent."))

;;; The tenant's locale (spec/i18n.md 9).
(define-setting "locale.language"
    (:type "language" :description "The language of the pages, and of the copy Tun stores and sends."))
(define-setting "locale.currency"
    (:type "currency" :description "The currency amounts are counted in. It cannot change while amounts are stored."))
(define-setting "locale.time_zone"
    (:type "time_zone" :description "The time zone of local dates and times, and of schedules."))

(defun read-tenant-locale ()
  "The tenant's locale, from its settings, in a read of its own or the
transaction open now.  A stored language the application no longer offers
reads as its first (spec/i18n.md 2.3)."
  (with-transaction (:read)
    (let ((language (setting-value-at-use "locale.language"))
          (languages (application-languages *application*)))
      (make-locale :language (if (or (member language languages :test #'equal)
                                     (equal language +pseudo-language+))
                                 language
                                 (first languages))
                   :currency (setting-value-at-use "locale.currency")
                   :time-zone (setting-value-at-use "locale.time_zone")))))

(defun request-locale (&optional (application *application*))
  "The locale a request of APPLICATION (the current one by default) starting
now is answered in: the tenant's, read once from its settings (spec/i18n.md
2.4, 9).  Without a store to read, or when reading fails, the application's
defaults; without an application, NIL."
  (cond ((null application) nil)
        ;; A thread eval started does not read the store before its call:
        ;; eval's own read transaction may hold the memory store.
        ((or *under-eval* (null (application-store application))) (default-locale application))
        (t (let ((*application* application)
                 (*store* (or (and (eq application *application*) *store*)
                              (application-store application))))
             (handler-case (read-tenant-locale)
               (error () (default-locale application)))))))

(defgeneric money-records-exist-p (application)
  (:documentation "True when a stored record of an entity with a money field
exists in APPLICATION's store, so its currency cannot change (spec/i18n.md
5.3).")
  (:method (application)
    (declare (ignore application))
    (loop for class in (all-entity-classes)
          thereis (and (not (entity-embedded-p class))
                       (some (lambda (field) (typep (field-type field) 'money-type))
                             (entity-stored-fields class))
                       (select-one (class-name class))))))

(defun constant-time-string= (left right)
  "Compare every byte of equally sized token strings without an early mismatch exit."
  (when (and (stringp left) (stringp right))
    (let ((difference (logxor (length left) (length right))))
      (dotimes (i (min (length left) (length right)))
        (setf difference (logior difference (logxor (char-code (char left i)) (char-code (char right i))))))
      (zerop difference))))

(defun link-token (kind id)
  "Stable subject token: first twenty RFC4648 base32 characters of HMAC-SHA256 with the current secret."
  (let* ((mac (ironclad:make-hmac (sb-ext:string-to-octets (setting-value-at-use "links.secret")
                                                        :external-format :utf-8) :sha256))
         (alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"))
    (ironclad:update-hmac mac (sb-ext:string-to-octets (format nil "~a:~a" kind id) :external-format :utf-8))
    (let ((bytes (ironclad:hmac-digest mac)))
      (coerce (loop for bit from 0 below 100 by 5
                    collect (char alphabet (loop for offset below 5
                                                for position = (+ bit offset)
                                                sum (* (ldb (byte 1 (- 7 (mod position 8))) (aref bytes (floor position 8)))
                                                       (expt 2 (- 4 offset)))))) 'string))))

(defparameter +base64url-alphabet+ "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
(defun base64url-encode (text)
  (with-output-to-string (out)
    (let ((bits 0) (value 0))
      (loop for c across text do
        (setf value (logior (ash value 8) (char-code c))) (incf bits 8)
        (loop while (>= bits 6) do (decf bits 6) (write-char (char +base64url-alphabet+ (ldb (byte 6 bits) value)) out)))
      (when (plusp bits) (write-char (char +base64url-alphabet+ (logand 63 (ash value (- 6 bits)))) out)))))
(defun base64url-decode (text)
  (when (> (length text) 1000) (error "proof too long"))
  (with-output-to-string (out)
    (let ((bits 0) (value 0))
      (loop for c across text for digit = (position c +base64url-alphabet+) do
        (unless digit (error "invalid proof encoding"))
        (setf value (logior (ash value 6) digit)) (incf bits 6)
        (when (>= bits 8) (decf bits 8) (write-char (code-char (ldb (byte 8 bits) value)) out))))))
(defun response-proof-mac (payload)
  (let ((mac (ironclad:make-hmac (sb-ext:string-to-octets (setting-value-at-use "links.secret") :external-format :utf-8) :sha256)))
    (ironclad:update-hmac mac (sb-ext:string-to-octets payload :external-format :utf-8))
    (ironclad:byte-array-to-hex-string (ironclad:hmac-digest mac))))
(defun sign-response-proof (quote-id revision)
  (let ((payload (format nil "~a|~d|~d" quote-id revision (- (+ (now) 900) 2208988800))))
    (base64url-encode (format nil "~a|~a" payload (response-proof-mac payload)))))
(defun verify-response-proof (proof quote-id)
  "Return revision and expiry only for a genuine, canonical subject proof."
  (handler-case
      (let* ((text (base64url-decode proof)) (parts (cl-ppcre:split "\\|" text)))
        (when (and (= (length parts) 4) (equal (first parts) quote-id)
                   (equal (base64url-encode text) proof)
                   (constant-time-string= (fourth parts) (response-proof-mac (format nil "~a|~a|~a" (first parts) (second parts) (third parts)))))
          (values (parse-integer (second parts)) (+ 2208988800 (parse-integer (third parts))))))
    (error () nil)))

(define-operation settings-list () (:entity setting :kind :read :policy :admin :title "Settings")
  (jobj "items" (jarr (settings-description))))
(define-operation settings-get ((key :type (string :max 200) :required t))
    (:entity setting :kind :read :policy :employee :title "Get a setting")
  (when (equal "secret" (setting-declaration-type (declared-setting key)))
    (reject :forbidden "A secret cannot be read"))
  (jobj "key" key "value" (setting-public-value (declared-setting key))))

(define-operation settings-set ((key :type (string :max 200) :required t) (value :type json :schema-required t))
    (:entity setting :kind :update :policy :admin :title "Change a setting")
  (unless (or (input-provided-p :value) (input-null-p :value)) (fail :invalid-input "Give a value"))
  (let ((decl (declared-setting key)) (value (if (input-null-p :value) :null value)))
    (when (setting-declaration-env decl)
      (fail :invalid-input "The setting ~a is read from the environment variable ~a and cannot be changed here"
            key (setting-declaration-env decl)))
    (validate-setting-value decl value)
    (when (and (equal key "locale.currency") (not (equal value (setting-value-at-use key)))
               (money-records-exist-p *application*))
      (fail :conflict "The currency cannot change while amounts are stored in ~a"
            (setting-value-at-use key)))
    (write-setting key value)
    (write-system-audit "settings_set" "ok" :entity-type "setting" :entity-id key)
    (setting-json decl)))
