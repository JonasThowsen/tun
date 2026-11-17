;;;; tests/session-api-tests.lisp -- /api in the signed-in person's session,
;;;; from the application's own single-page screen, and what proves a call
;;;; came from there (spec/typescript.md 5); the screen itself, served
;;;; behind its page's policy (4).

(in-package #:tun.tests)

(def-suite session-api :in core)
(in-suite session-api)

(defun person-session (name role)
  "Values a session cookie of a new person NAME with ROLE and the session's id."
  (make-account name "person" role (format nil "~a@example.no" name))
  (session-for name))

(defun proof-of (cookie)
  "The proof of a session whose cookie is COOKIE, as spec/typescript.md 5.1
writes it."
  (sha256-hex (concatenate 'string "tun-api-proof:" cookie)))

(defun session-api (port tool arguments &key cookie (cookie-name "tun_session") proof
                                          (site "same-origin") origin
                                          (content-type "application/json") token)
  "POST ARGUMENTS, a JSON object, to /api/TOOL as a browser would: COOKIE as
the session's (COOKIE-NAME), PROOF as Tun-Api-Proof, SITE as
Sec-Fetch-Site and ORIGIN as Origin (each left out when NIL), the body as
CONTENT-TYPE (none when NIL), and TOKEN as a bearer token.  Values the
status and the parsed body."
  (multiple-value-bind (bytes status)
      (drakma:http-request (format nil "http://127.0.0.1:~d/api/~a" port tool)
                           :method :post
                           :content-type content-type
                           :content (sb-ext:string-to-octets (to-json-string arguments)
                                                             :external-format :utf-8)
                           :additional-headers
                           (remove nil
                                   (list (and cookie
                                              (cons "Cookie" (format nil "~a=~a" cookie-name cookie)))
                                         (and proof (cons "Tun-Api-Proof" proof))
                                         (and site (cons "Sec-Fetch-Site" site))
                                         (and origin (cons "Origin" origin))
                                         (and token (cons "Authorization"
                                                          (format nil "Bearer ~a" token)))))
                           :force-binary t)
    (let ((text (if bytes (sb-ext:octets-to-string bytes :external-format :utf-8) "")))
      (values status (and (plusp (length text)) (ignore-errors (parse-json text)))))))

(defun own-origin (port) (format nil "http://127.0.0.1:~d" port))

(defun account-named-p (name)
  (and (find name (admin-items "accounts_list") :key (lambda (a) (jget a "name")) :test #'equal)
       t))

(defun refused-tool-entries (tool)
  "The audit entries of TOOL's refused calls, newest first."
  (remove-if-not (lambda (entry) (and (equal tool (jget entry "tool"))
                                      (equal "rejected" (jget entry "outcome"))))
                 (admin-items "audit_list" "limit" 100)))

(defun session-last-seen (id)
  (with-application (*app*)
    (with-transaction (:read)
      (tun.auth::session-last-seen-at (fetch 'tun.auth::session id)))))

;;; ------------------------------------------------------------------
;;; Admitted (criterion 10)

(test a-session-call-from-the-page-runs-as-the-person
  (with-test-server (port :identity :authenticated)
    (multiple-value-bind (cookie id) (person-session "kari" "employee")
      (let ((proof (proof-of cookie)))
        (multiple-value-bind (status json)
            (session-api port "accounts_whoami" (jobj) :cookie cookie :proof proof)
          (is (= 200 status))
          (is (equal "employee:kari" (jget json "actor")))
          (is (equal "session" (jget json "credential"))))
        (is (= 200 (session-api port "accounts_whoami" (jobj) :cookie cookie :proof proof
                                :content-type "Application/JSON; charset=utf-8"))
            "the media type is compared without its parameters and its case")
        (is (= 200 (session-api port "accounts_whoami" (jobj) :cookie cookie :proof proof
                                :site nil :origin (own-origin port)))
            "a browser without Sec-Fetch-Site: the server's own Origin")
        (is (= 200 (session-api port "accounts_whoami" (jobj) :cookie cookie :proof proof
                                :origin (own-origin port)))
            "both")
        (is (string-prefix-p "ses_" id))))
    (multiple-value-bind (cookie id) (person-session "ada" "admin")
      (let ((proof (proof-of cookie)))
        (multiple-value-bind (status json)
            (session-api port "session_test_approve" (jobj) :cookie cookie :proof proof)
          (is (= 200 status) "a session-only operation runs in the session")
          (is (equal "session" (jget json "credential"))))
        (multiple-value-bind (status json)
            (session-api port "accounts_create"
                         (jobj "name" "robot" "kind" "agent" "role" "viewer")
                         :cookie cookie :proof proof)
          (is (= 200 status))
          (is (equal "robot" (jget json "name"))))
        (let ((entry (find "accounts_create" (admin-items "audit_list" "entity_type" "account")
                           :key (lambda (e) (jget e "tool")) :test #'equal)))
          (is (equal "admin:ada" (jget entry "actor")))
          (is (equal id (jget entry "credential")) "the audit names the session"))
        ;; The error document in the tenant's language, as a form shows it;
        ;; a token's call keeps source text.
        (call-ok "settings_set" "admin:root" "key" "locale.language" "value" "nb")
        (let ((token (make-token (make-account "erp" "agent" "admin")))
              (bad (jobj "name" "Ikke Gyldig" "kind" "agent" "role" "viewer")))
          (multiple-value-bind (status json)
              (session-api port "accounts_create" bad :cookie cookie :proof proof)
            (is (= 422 status))
            (multiple-value-bind (token-status token-json)
                (api-request port "accounts_create" (to-json-string bad) :token token)
              (is (= 422 token-status))
              (let ((nb (handler-case (progn (call-tool "accounts_create" bad :application *app*
                                                        :actor (parse-actor "admin:root"))
                                             nil)
                          (operation-error (e) (with-language ("nb") (operation-error-json e)))))
                    (message (lambda (j) (jget (aref (jget (jget j "error") "fields") 0) "message"))))
                (is (equal (funcall message nb) (funcall message json))
                    "the session's field message is the page's: ~a" (funcall message json))
                (is (not (equal (funcall message token-json) (funcall message json)))
                    "and the token's is source text: ~a" (funcall message token-json))))))))))

;;; ------------------------------------------------------------------
;;; Refused and audited (criterion 11)

(test a-session-call-another-site-sends-is-refused-and-audited
  (with-test-server (port :identity :authenticated)
    (multiple-value-bind (cookie id) (person-session "ada" "admin")
      (let* ((proof (proof-of cookie))
             (other (proof-of (person-session "kari" "employee")))
             (cases `(("no proof" :proof nil)
                      ("another session's proof" :proof ,other)
                      ("cross-site" :site "cross-site")
                      ("same-site, another origin on the host" :site "same-site")
                      ("Sec-Fetch-Site none" :site "none")
                      ("neither Sec-Fetch-Site nor Origin" :site nil)
                      ("another site's Origin" :site "cross-site" :origin "https://evil.example")
                      ("a body as text/plain" :content-type "text/plain")
                      ("no Content-Type" :content-type nil))))
        (loop for (what . keys) in cases
              for n from 1
              for name = (format nil "forged~d" n)
              do (multiple-value-bind (status json)
                     (apply #'session-api port "accounts_create"
                            (jobj "name" name "kind" "agent" "role" "viewer")
                            :cookie cookie (append keys (list :proof proof)))
                   (is (eql 403 status) "~a: refused, not ~a" what status)
                   (is (equal "forbidden" (and json (error-code-of json))) "~a: forbidden" what)
                   (is (not (account-named-p name)) "~a: no account made" what)))
        (let ((entries (refused-tool-entries "accounts_create")))
          (is (= (length cases) (length entries)) "each refusal is audited once: ~a"
              (length entries))
          (is (every (lambda (e) (and (equal "admin:ada" (jget e "actor"))
                                      (equal id (jget e "credential"))))
                     entries)
              "as the person, with the session's credential"))
        (is (<= (length cases)
                (length (remove-if-not (lambda (r) (equal "accounts_create" (jget r "tool")))
                                       (admin-items "introspect_recent" "kind" "rejected"
                                                    "request_kind" "api"))))
            "each kept as a rejected request of kind api")))))

(test a-refused-session-call-does-not-keep-the-session-alive
  (with-test-server (port :identity :authenticated)
    (multiple-value-bind (cookie id) (person-session "kari" "employee")
      (let ((before (session-last-seen id)))
        (advance-clock (* 2 3600))
        (is (= 403 (session-api port "accounts_whoami" (jobj) :cookie cookie :site "cross-site"
                                :proof (proof-of cookie))))
        (is (= before (session-last-seen id)) "a refused call is no use of the session")
        (is (= 200 (session-api port "accounts_whoami" (jobj) :cookie cookie
                                :proof (proof-of cookie))))
        (is (< before (session-last-seen id)) "an admitted one is")))))

;;; ------------------------------------------------------------------
;;; Nothing weaker for a token (criterion 12)

(test a-token-call-is-as-before-beside-a-session
  (with-test-server (port :identity :authenticated)
    (multiple-value-bind (cookie id) (person-session "ada" "admin")
      (let ((token (make-token (make-account "erp" "agent" "employee")))
            (admin-token (make-token (make-account "ops" "agent" "admin")))
            (proof (proof-of cookie)))
        (multiple-value-bind (status json)
            (session-api port "accounts_whoami" (jobj) :cookie cookie :proof proof :token token)
          (is (= 200 status))
          (is (equal "employee:erp" (jget json "actor")) "the token decides, not the cookie")
          (is (equal "token" (jget json "credential"))))
        (multiple-value-bind (status json)
            (session-api port "accounts_create" (jobj "name" "x" "kind" "agent" "role" "viewer")
                         :cookie cookie :proof proof :token token)
          (is (= 403 status) "the token's role, not the admin's session")
          (is (equal "forbidden" (error-code-of json))))
        (multiple-value-bind (status json)
            (session-api port "session_test_approve" (jobj) :cookie cookie :proof proof
                         :token admin-token)
          (is (= 403 status) "a session-only operation stays refused for a token")
          (is (search "signed in on the page" (jget (jget json "error") "message"))))
        (is (= 403 (session-api port "accounts_whoami" (jobj) :token token :site "cross-site"
                                :origin "https://evil.example"))
            "another site's Origin, as before")
        (is (= 200 (session-api port "accounts_whoami" (jobj) :token token :site nil))
            "a token needs no proof and no Sec-Fetch-Site")
        (is (= 401 (session-api port "accounts_whoami" (jobj))) "no token and no session")
        (is (= 401 (session-api port "accounts_whoami" (jobj) :cookie (make-string 64 :initial-element #\a)
                                :proof (proof-of (make-string 64 :initial-element #\a))))
            "a cookie that names no session")
        (expire-session id)
        (is (= 401 (session-api port "accounts_whoami" (jobj) :cookie cookie :proof proof))
            "an expired session")))))

;;; ------------------------------------------------------------------
;;; Claimed identity (criterion 13)

(test claimed-identity-takes-the-actor-cookie-with-its-proof
  (with-test-server (port)
    (let ((cookie (hunchentoot:url-encode "employee:anna" :utf-8)))
      (multiple-value-bind (status json)
          (session-api port "accounts_whoami" (jobj) :cookie cookie :cookie-name "tun_actor"
                       :proof (proof-of cookie))
        (is (= 200 status))
        (is (equal "employee:anna" (jget json "actor")))
        (is (equal "claimed" (jget json "credential"))))
      (is (= 403 (session-api port "accounts_whoami" (jobj) :cookie cookie :cookie-name "tun_actor"))
          "without its proof")
      (is (= 200 (api-request port "accounts_whoami" "{}" :headers '(("X-Tun-Actor" . "viewer:vera"))))
          "X-Tun-Actor names the caller as before"))))

;;; ------------------------------------------------------------------
;;; A single-page screen (spec/typescript.md 4; criteria 14, 15)

(tun.web:define-single-page ts-screen ("ts-screen" :title "TS screen" :policy :employee
                                                   :navigation nil)
  :files ("tun" "tests/typescript/screen/"))

(tun.web:define-single-page ts-unbuilt-screen ("ts-unbuilt" :title "Unbuilt screen" :policy :employee
                                                            :navigation nil)
  :files ("tun" "tests/typescript/"))

(defun jar-cookie (jar name)
  "The value of the cookie NAME in the cookie jar JAR."
  (let ((cookie (find name (drakma:cookie-jar-cookies jar) :key #'drakma:cookie-name
                      :test #'string=)))
    (and cookie (drakma:cookie-value cookie))))

(defun header-of (headers name) (cdr (assoc name headers)))

(defun screen-file-text (name)
  (uiop:read-file-string (asdf:system-relative-pathname "tun" (format nil "tests/typescript/screen/~a"
                                                                      name))))

(test a-single-page-screen-is-behind-its-page-s-policy
  (with-test-server (port)
    (multiple-value-bind (status body headers) (web-request port "/ts-screen")
      (declare (ignore body))
      (is (= 303 status) "signed out, to sign in")
      (is (equal "/login?next=%2Fts-screen" (location headers))))
    (is (= 403 (web-request port "/ts-screen" :jar (web-login port "viewer:vera")))
        "a role its policy refuses")
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (status body headers) (web-request port "/ts-screen" :jar jar)
        (is (= 200 status))
        (is (equal "text/html; charset=utf-8" (header-of headers :content-type)))
        (is (equal "no-store" (header-of headers :cache-control)))
        (is (search (format nil "<head><meta name=\"tun-api-proof\" content=\"~a\">"
                            (proof-of (jar-cookie jar "tun_actor")))
                    body)
            "the proof of the session's cookie, right after <head>")
        (is (search "<main id=\"screen\"></main>" body) "and the rest as built")
        (is (equal (header-of (nth-value 2 (web-request port "/access" :jar jar)) :content-security-policy)
                   (header-of headers :content-security-policy))
            "the page's own policy"))
      (is (= 200 (web-request port "/ts-screen/" :jar jar)) "with a slash too")))
  (with-test-server (port :identity :authenticated)
    (let ((cookie (person-session "kari" "employee")))
      (multiple-value-bind (status body)
          (web-request port "/ts-screen" :headers (list (cons "Cookie" (format nil "tun_session=~a" cookie))))
        (is (= 200 status))
        (is (search (format nil "content=\"~a\"" (proof-of cookie)) body)
            "a person's session: the proof of its cookie")))))

(test a-single-page-screen-is-in-the-menu-of-those-its-policy-admits
  (unwind-protect
       (progn
         (eval '(tun.web:define-single-page ts-menu-screen ("ts-menu" :title "TS menu screen" :policy :employee)
                 :files ("tun" "tests/typescript/screen/")))
         (with-test-server (port)
           (is (search "href=\"/ts-menu\"" (nth-value 1 (web-request port "/access"
                                                                     :jar (web-login port "employee:anna"))))
               "in an employee's menu")
           (is (not (search "href=\"/ts-menu\"" (nth-value 1 (web-request port "/access"
                                                                          :jar (web-login port "viewer:vera")))))
               "not in a viewer's")))
    (remhash "ts-menu" tun.web::*staff-pages*)))

(test a-single-page-screen-answers-its-files-and-nothing-else
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (status body headers) (web-request port "/ts-screen/app.js" :jar jar)
        (is (= 200 status))
        (is (equal (screen-file-text "app.js") body))
        (is (equal "text/javascript; charset=utf-8" (header-of headers :content-type)))
        (is (equal "nosniff" (header-of headers :x-content-type-options)))
        (is (equal "no-cache" (header-of headers :cache-control)))
        (is (header-of headers :content-security-policy) "under the page's policy too"))
      (multiple-value-bind (status body headers) (web-request port "/ts-screen/assets/style.css" :jar jar)
        (is (= 200 status) "a file in a folder of the screen's")
        (is (equal (screen-file-text "assets/style.css") body))
        (is (equal "text/css; charset=utf-8" (header-of headers :content-type))))
      (dolist (path '("/ts-screen/%2e%2e/screen.ts" "/ts-screen/assets/%2e%2e/%2e%2e/screen.ts"
                      "/ts-screen/.hidden.js" "/ts-screen/notes.md" "/ts-screen/missing.js"
                      "/ts-screen/index.html" "/ts-screen/assets"))
        (is (= 404 (web-request port path :jar jar)) "~a is not one of its files" path))
      (is (= 404 (web-request port "/ts-unbuilt" :jar jar)) "a screen without its index.html")
      (multiple-value-bind (status body headers)
          (web-request port "/ts-screen" :method :post :jar jar)
        (declare (ignore body))
        (is (= 405 status))
        (is (equal "GET" (header-of headers :allow))))
      (multiple-value-bind (status body headers)
          (web-request port "/ts-screen" :jar jar :headers '(("HX-Request" . "true")))
        (is (= 200 status) "htmx, from a menu entry")
        (is (equal "" body))
        (is (equal "/ts-screen" (header-of headers :hx-redirect)) "loads the screen whole"))
      (multiple-value-bind (status body headers)
          (web-request port "/ts-screen" :jar jar :headers '(("Tun-Preload" . "true")))
        (declare (ignore body))
        (is (= 204 status) "a preload")
        (is (equal "declined" (header-of headers :tun-preload)))))))

(test a-screen-s-file-must-be-in-its-folder
  (let* ((outside (uiop:ensure-directory-pathname
                   (format nil "~atypescript-client-out-~36r/" (uiop:temporary-directory)
                           (random (expt 36 8)))))
         (folder (merge-pathnames "screen/" outside)))
    (ensure-directories-exist folder)
    (unwind-protect
         (progn
           (with-open-file (out (merge-pathnames "secret.js" outside) :direction :output)
             (write-string "// outside" out))
           (with-open-file (out (merge-pathnames "own.js" folder) :direction :output)
             (write-string "// inside" out))
           (sb-posix:symlink (namestring (merge-pathnames "secret.js" outside))
                             (namestring (merge-pathnames "link.js" folder)))
           (is (equal "text/javascript; charset=utf-8"
                      (nth-value 1 (tun.web::single-page-file folder '("own.js")))))
           (is (null (tun.web::single-page-file folder '("link.js")))
               "a link out of the folder is not followed")
           (is (null (tun.web::single-page-file folder '(".." "secret.js")))))
      (uiop:delete-directory-tree outside :validate t))))

(test a-screen-without-its-index-says-where-it-looked
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply))
        (*error-output* (make-string-output-stream)))
    (let ((folder (asdf:system-relative-pathname "tun" "tests/typescript/")))
      (is (= 404 (tun.web::serve-single-page-index folder)))
      (is (search (namestring folder) (get-output-stream-string *error-output*))))))
