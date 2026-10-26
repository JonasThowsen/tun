;;;; web/ui.lisp -- the generated UI: server-rendered HTML with plain forms.
;;;;
;;;; Every page is a projection of the registry and every submission calls
;;;; the same operations as MCP (CALL-TOOL with the logged-in actor): there
;;;; are no parallel handlers, so policy, confirmation, idempotency, rules and
;;;; audit are identical.  A module registers a resource (path, entity, its
;;;; list and create operations, screens); lists and create forms are
;;;; generated from the operations, and each page body is a screen,
;;;; RENDER-SCREEN, which a client overrides with a method on its application.
;;;;
;;;; Every page is built from the design system's components (TUN.UI, here
;;;; UI:, spec/ui.md 8): a staff page is an app-shell with the menu, a page
;;;; for someone not logged in the same frame without it.

(defpackage #:tun.web
  (:use #:cl #:tun.core #:tun.html)
  (:local-nicknames (#:ui #:tun.ui))
  (:export #:render-screen #:section #:json-table #:entity-detail #:web-resources
           #:define-page #:web-call #:error-alert #:timestamp-text #:htmx-request-p
           #:staff-page-extras #:preload-request-p #:decline-preload
           #:check-http-route-conflicts #:escape-html #:register-public-page #:register-staff-page #:render-resource-extras #:staff-navigation-title
           #:register-json-endpoint #:register-web-resource #:resource-path #:resource-entity))

(in-package #:tun.web)

(declaim (optimize (safety 3) (debug 2)))

(defun register-json-endpoint (path handler)
  "Register a bounded JSON POST port. HANDLER receives JSON and the inbound secret,
returning status and JSON; it calls the same guarded operations as MCP."
  (tun.http:register-json-endpoint path handler))

(defparameter +actor-cookie+ "tun_actor")
(defvar *public-pages* (make-hash-table :test 'equal))
(defvar *staff-pages* (make-hash-table :test 'equal))

(defstruct staff-page
  "A page under /PREFIX for logged-in staff, registered by the kernel or a module.
GROUP is :WORK for the business's work, :SYSTEM for the system's own pages.
REMEMBERS lists the query keys it keeps for each account."
  handler policy title icon (navigation t) (group :work) (width :default) remembers module
  (sequence 0))

(defvar *staff-page-sequence* 0 "Counts registrations, so the menu keeps their order.")

(defun register-staff-page (prefix handler &key (policy :employee) (title prefix) (icon :file)
                                             (navigation t) (group :work) (width :default)
                                             remembers)
  "Staff page port: HANDLER (method, path parts, form, query) returns status,
title and body, and is guarded by POLICY before it is called.  TITLE and ICON
(a design system icon name) are its entry in the menu; NAVIGATION nil keeps
it out of the menu, for a page that only answers posts.  GROUP :SYSTEM puts
it under «System» at the end of the menu, for a page about the system rather
than the business's work (spec/ui.md 8).  WIDTH :WIDE gives the page the
whole width beside the menu, for a board.  REMEMBERS, a list of query keys,
keeps what the page was last opened with for each account (spec/ui.md 8,
REMEMBER-QUERY).  A HANDLER that is a function's
name may register its prefix again, which replaces the page and keeps its
place in the menu (DEFINE-PAGE evaluated again)."
  (check-type group (member :work :system))
  (check-type width (member :default :wide))
  (unless (and (listp remembers) (every #'stringp remembers))
    (extension-error "Staff page ~a remembers ~s, which is not a list of query keys"
                     prefix remembers))
  (let ((previous (gethash prefix *staff-pages*)))
    (when (and previous (not (and (symbolp handler) (eq handler (staff-page-handler previous)))))
      (extension-error "Staff page ~a is already registered" prefix))
    (setf (gethash prefix *staff-pages*)
          (make-staff-page :handler handler :policy policy :title title :icon icon
                           :navigation navigation :group group :width width
                           :remembers remembers :module (current-definition-module)
                           :sequence (if previous
                                         (staff-page-sequence previous)
                                         (incf *staff-page-sequence*))))))

(defmacro define-page (name (prefix &key (title prefix) (icon :file) (policy :employee)
                                         (navigation t) (group :work) (width :default)
                                         remembers)
                       (method path form query) &body body)
  "Define NAME, the page at /PREFIX and the paths under it, for logged-in
people POLICY admits (spec/ui.md 8): a function of the request's METHOD
(:GET or :POST), PATH (the parts after the prefix), FORM and QUERY (JSON
objects) that returns (values STATUS TITLE BODY [HEADER]), HEADER a plist of
:DESCRIPTION, :ACTIONS, :BREADCRUMBS and :TRIGGER, or (values 303 PATH), or
(values STATUS :FRAGMENT BODY [HEADER]) to answer htmx with BODY alone
(spec/ui.md 8.1).  TITLE and ICON are its menu entry; NAVIGATION nil keeps
it out of the menu, GROUP :SYSTEM puts it under «System», WIDTH :WIDE
gives it the whole width beside the menu, and REMEMBERS, a list of query
keys, keeps what the page was last opened with for each account."
  `(progn
     (defun ,name (,method ,path ,form ,query)
       (declare (ignorable ,method ,path ,form ,query))
       ,@body)
     (register-staff-page ,prefix ',name :policy ,policy :title ,title :icon ,icon
                                         :navigation ,navigation :group ,group :width ,width
                                         :remembers ,remembers)
     ',name))

(defgeneric render-resource-extras (application entity record)
  (:documentation "Sections a module or client adds to the detail page of RECORD, an
ENTITY's JSON, after its screen.  The default adds none.")
  (:method (application entity record) (declare (ignore application entity record)) nil))
(register-extension-protocol
 'render-resource-extras "screen" :point "resource_sections"
 :description "Dependent modules add sections to a resource's detail page.")
(defgeneric staff-navigation-title (application prefix title)
  (:documentation "The menu title of the staff page at PREFIX, registered as TITLE.  A
method may add a count in parentheses, Varsler (3), which the menu shows as a
count.  The default is TITLE.")
  (:method (application prefix title) (declare (ignore application prefix)) title))
(register-extension-protocol
 'staff-navigation-title "screen" :point "navigation_title"
 :description "A module adds its own navigation count without exposing another employee's rows.")
(defgeneric staff-page-extras (application)
  (:documentation "Components a client adds to every staff page, after its content:
a dialog that opens from anywhere with a shortcut, such as a search
(spec/ui.md 8).  The default adds none.")
  (:method (application) (declare (ignore application)) nil))
(register-extension-protocol
 'staff-page-extras "screen" :point "page_extras"
 :description "A client adds components to every staff page, such as a search dialog.")

(defun page-available-p (page)
  "True when PAGE belongs to the running application: core's and the
client's always, a module's only when the application enables the module."
  (let ((module (staff-page-module page)))
    (or (member module '("core" "client") :test #'string=)
        (find module (enabled-modules *application*) :key (lambda (entry) (module-name (first entry)))
                                                 :test #'string=))))

;;; ------------------------------------------------------------------
;;; What a page remembers for each account (spec/ui.md 8)

(define-entity saved-query (:label "Husket søk" :id-prefix "sq" :table "saved_queries" :internal t
                            :unique (("account" "page")))
  ((account :type (string :max 64) :required t :input nil :label "Konto")
   (page :type (string :max 200) :required t :input nil :label "Side")
   (query :type json :input nil :label "Søk"
          :description "The keys the page remembers that have a value, as an object.")))

(defun remembered-pairs (page query)
  "The keys PAGE remembers that QUERY, a JSON object, gives a value, with
those values, in the order PAGE names them."
  (loop for key in (staff-page-remembers page)
        for value = (jget query key)
        when (and (stringp value) (plusp (length value)))
          collect (cons key value)))

(defun pairs-object (pairs)
  "PAIRS, (KEY . VALUE) conses, as a JSON object."
  (apply #'jobj (loop for (key . value) in pairs append (list key value))))

(defun remember-query (page prefix query)
  "Keep what QUERY gives PAGE's remembered keys for the person signed in, when
it names any of them; else the address of PREFIX with what they kept, to
send them to, or NIL when they kept nothing.  A key QUERY names without a
value is kept as cleared, so a link that clears a filter is remembered.  A
preload that would change what is kept is :DECLINED instead, so the click
after it keeps it (spec/ui.md 4.1)."
  (let ((account (actor-name *actor*)))
    (if (some (lambda (key) (nth-value 1 (jget query key))) (staff-page-remembers page))
        (let ((pairs (remembered-pairs page query)))
          (with-transaction (:write)
            (let* ((row (select-one 'saved-query :where `(:and (:= "account" ,account)
                                                               (:= "page" ,prefix))))
                   (kept (and row (remembered-pairs page (saved-query-query row)))))
              (cond ((equal pairs kept) nil)
                    ((preload-request-p) :declined)
                    (row
                     (setf (saved-query-query row) (pairs-object pairs))
                     (save row)
                     nil)
                    (t
                     (insert (make-instance 'saved-query :account account :page prefix
                                                         :query (pairs-object pairs)))
                     nil)))))
        (let* ((row (with-transaction (:read)
                      (select-one 'saved-query :where `(:and (:= "account" ,account)
                                                             (:= "page" ,prefix)))))
               (pairs (and row (remembered-pairs page (saved-query-query row)))))
          (when pairs
            (format nil "/~a?~@[~a&~]~{~a~^&~}" prefix
                    (let ((given (hunchentoot:query-string*)))
                      (and (plusp (length given)) given))
                    (loop for (key . value) in pairs
                          collect (format nil "~a=~a" (hunchentoot:url-encode key :utf-8)
                                          (hunchentoot:url-encode value :utf-8)))))))))

(defun dispatch-staff-page (method parts)
  (let ((page (gethash (first parts) *staff-pages*)))
    (when (and page (page-available-p page))
      (unless (and *actor* (actor-permits-p *actor* (staff-page-policy page)))
        (return-from dispatch-staff-page
          (respond 403 "Ingen tilgang"
                   (list (ui:alert (:variant :warning :title "Denne siden er ikke for deg")
                                   "Siden krever en ansatt med en annen rolle enn din.")))))
      (let ((form (jobj)) (query (jobj)))
        (when (eq method :post)
          (dolist (pair (hunchentoot:post-parameters*))
            (setf (gethash (car pair) form) (cdr pair))))
        (dolist (pair (hunchentoot:get-parameters*))
          (setf (gethash (car pair) query) (cdr pair)))
        ;; Only the page's own address, as a page: a record's page under it,
        ;; a post and a part htmx refreshes neither keep nor follow it.
        (when (and (eq method :get) (null (rest parts)) (staff-page-remembers page)
                   (not (htmx-request-p)))
          (let ((kept (remember-query page (first parts) query)))
            (cond ((eq kept :declined)
                   (return-from dispatch-staff-page (answer-declined-preload)))
                  (kept
                   (return-from dispatch-staff-page (see-other kept))))))
        (multiple-value-bind (status title body header)
            (handler-case (funcall (staff-page-handler page) method (rest parts) form query)
              ;; An error the page does not catch: its alert, alone to htmx.
              (operation-error (e)
                (values (error-status (operation-error-code e))
                        (if (htmx-request-p) :fragment (staff-page-title page))
                        (list (error-alert (operation-error-json e))))))
          (destructuring-bind (&key description actions breadcrumbs trigger) header
            (when trigger
              (setf (hunchentoot:header-out "HX-Trigger") trigger))
            (cond ((eql status 303) (see-other title))
                  ((eq title :declined) (answer-declined-preload))
                  ((eq title :fragment) (respond-fragment status body))
                  (t (respond status title body :description description :actions actions
                                                :breadcrumbs breadcrumbs
                                                :width (staff-page-width page))))))))))

(defvar *public-sessions* (make-hash-table :test 'equal))
(defvar *public-sessions-lock* (sb-thread:make-mutex :name "public sessions"))
(defvar *public-session-sequence* 0)
(defstruct public-session (sequence 0) (created-at (now)) last-used-at (values (jobj)) (lock (sb-thread:make-mutex :name "public session")))
(defun register-public-page (prefix handler)
  "A public HTML port: handler(method, path parts, form JSON, session JSON)
returns status, heading and an escaped HTML tree. Duplicate prefixes fail."
  (when (gethash prefix *public-pages*) (extension-error "Public page ~a is already registered" prefix))
  (setf (gethash prefix *public-pages*) handler))
(defparameter +public-session-limit+ 10000)
(defparameter +public-session-lifetime+ 3600)
(defun prune-public-sessions (time)
  "Expire one-hour entries; caller holds the session table lock."
  (maphash (lambda (key session)
             (when (>= (- time (or (public-session-last-used-at session) (public-session-created-at session))) +public-session-lifetime+)
               (remhash key *public-sessions*))) *public-sessions*))
(defun find-public-session (cookie create &optional (time (now)))
  "Return a stored session only for an offer unlock, expiring and bounding the table."
  (sb-thread:with-mutex (*public-sessions-lock*)
    (prune-public-sessions time)
    (let ((session (and cookie (gethash cookie *public-sessions*))) (new-cookie nil))
      (when (and create (null session))
        (when (>= (hash-table-count *public-sessions*) +public-session-limit+)
          (let ((oldest nil) (oldest-time most-positive-fixnum) (oldest-sequence most-positive-fixnum))
            (maphash (lambda (key entry)
                       (when (or (< (public-session-created-at entry) oldest-time)
                                 (and (= (public-session-created-at entry) oldest-time)
                                      (< (public-session-sequence entry) oldest-sequence)))
                         (setf oldest key oldest-time (public-session-created-at entry) oldest-sequence (public-session-sequence entry)))) *public-sessions*)
            (remhash oldest *public-sessions*)))
        (setf new-cookie (new-secret-token) session (make-public-session :created-at time :sequence (incf *public-session-sequence*))
              (gethash new-cookie *public-sessions*) session))
      (when session (setf (public-session-last-used-at session) time))
      (values (or session (make-public-session :created-at time)) new-cookie))))
(defun public-session-for-request (&optional create)
  (multiple-value-bind (session cookie) (find-public-session (hunchentoot:cookie-in "tun_public") create)
    (when cookie (hunchentoot:set-cookie "tun_public" :value cookie :path "/" :http-only t))
    session))

(defun dispatch-public-page (method parts)
  "A page for customers (a quote, a feedback form): the frame without the
menu, its title linking back to the page itself."
  (let ((handler (gethash (first parts) *public-pages*)))
    (when handler
      (setf (hunchentoot:header-out "Referrer-Policy") "no-referrer")
      (let ((form (jobj))
            (session (public-session-for-request (and (eq method :post) (= (length parts) 3)
                                                      (equal (first parts) "tilbud")
                                                      (equal (third parts) "apne")))))
        (when (eq method :post)
          (dolist (pair (hunchentoot:post-parameters*))
            (setf (gethash (car pair) form) (cdr pair))))
        (sb-thread:with-mutex ((public-session-lock session))
          (multiple-value-bind (status heading body)
              (handler-case (funcall handler method (rest parts) form
                                     (public-session-values session))
                (operation-error (e)
                  (values 422 "Meldingen kunne ikke lagres"
                          (list (ui:alert (:variant :destructive)
                                          (operation-error-message e))))))
            (respond status heading body :guest t :home (public-home parts))))))))

(defun public-home (parts)
  "Where the title of the public page at PARTS leads: the page itself, as
/tilbud/ID is for every step of answering an offer."
  (format nil "/~{~a~^/~}" (subseq parts 0 (min 2 (length parts)))))

(defparameter +form-line-rows+ 3 "Empty rows offered for list inputs such as order lines.")

;;; A resource: URL path, entity, list and create tools, Norwegian title, the
;;; list screen, and optionally a detail screen (GET <path>/<id>) whose
;;; record is passed to RENDER-SCREEN as DETAIL-KEY.  ICON is its icon in the
;;; menu.
(defstruct (resource (:constructor %make-resource))
  path entity list-tool create-tool get-tool title list-screen detail-screen detail-key module
  (icon :file-text))

(defvar *resources* '() "Registered resources, in registration (dependency) order.")

(defun check-http-route-conflicts ()
  "Refuse overlapping resource, staff, public and JSON routes before serving requests."
  (let ((routes '(("/mcp" "core MCP") ("/health" "core health") ("/login" "core login")
                  ("/logout" "core login") ("/setup" "core login") ("/auth" "core login")
                  ("/api" "core API") ("/manifest.webmanifest" "core web app")
                  ("/sw.js" "core web app") ("/offline" "core web app") ("/push" "core push"))))
    (flet ((add (path owner)
             (push (list (if (string-prefix-p "/" path) path (concatenate 'string "/" path)) owner) routes)))
      (dolist (resource *resources*) (add (resource-path resource) (resource-module resource)))
      (maphash (lambda (path handler) (add path (format nil "public ~a" handler))) *public-pages*)
      (maphash (lambda (path page) (add path (format nil "staff ~a" (staff-page-handler page)))) *staff-pages*)
      (maphash (lambda (path handler) (add path (format nil "JSON ~a" handler))) tun.http::*json-endpoints*))
    (loop for rest on routes for left = (first rest)
          do (dolist (right (rest rest))
               (when (or (string-prefix-p (first left) (first right))
                         (string-prefix-p (first right) (first left)))
                 (extension-error "Refusing to start; HTTP routes overlap: ~a (~a) and ~a (~a)"
                                  (first left) (second left) (first right) (second right)))))
    t))

(defun register-web-resource (&key path entity list-tool create-tool get-tool title list-screen
                                detail-screen (detail-key :record) (icon :file-text)
                                (module (current-definition-module)))
  "Serve ENTITY at PATH: a list (LIST-SCREEN) with a create form, and with
DETAIL-SCREEN a detail page per record read through GET-TOOL.  TITLE and
ICON (a design system icon name) are its entry in the menu."
  (let ((previous (find path *resources* :key #'resource-path :test #'equal)))
    (when (and previous (not (equal module (resource-module previous))))
      (extension-error "HTTP resource ~a is claimed by ~a and ~a"
                       path (resource-module previous) module)))
  (let ((resource (%make-resource :path path :entity entity :list-tool list-tool
                                  :create-tool create-tool :get-tool get-tool :title title
                                  :list-screen list-screen :detail-screen detail-screen
                                  :detail-key detail-key :icon icon :module module)))
    (setf *resources* (append (remove path *resources* :key #'resource-path :test #'string=)
                              (list resource)))
    (register-screen list-screen module)
    (when detail-screen (register-screen detail-screen module))
    resource))

(defun web-resources ()
  "The registered resources, in registration order."
  *resources*)

;;; ------------------------------------------------------------------
;;; Request context

(defvar *web-app* nil)

(defun web-actor ()
  "Values the actor of this request and its credential (spec/auth.md 3.3):
the session cookie's, else, with claimed identity, the X-Tun-Actor header's
or the tun_actor cookie's."
  (multiple-value-bind (actor session)
      (tun.auth:authenticate-session (hunchentoot:cookie-in tun.auth:+session-cookie+))
    (cond (actor (values actor session))
          ((claimed-identity-p *web-app*)
           (let ((actor (or (parse-actor (tun.http:header-utf-8 :x-tun-actor))
                            (let ((raw (hunchentoot:cookie-in +actor-cookie+)))
                              (and raw (parse-actor (hunchentoot:url-decode raw :utf-8)))))))
             (values actor (and actor "claimed"))))
          (t (values nil nil)))))

(defun htmx-request-p ()
  "True while answering a request htmx sent for part of a page (spec/ui.md
8.1): HX-Request-Type: partial.  A boosted link or form, a page restored
through history and HX-Location ask for the whole page (full)."
  (and (hunchentoot:header-in* :hx-request)
       (string-equal (hunchentoot:header-in* :hx-request-type) "partial")))

(defun preload-request-p ()
  "True while answering a page the browser loads before it is clicked
(spec/ui.md 4.1): Tun-Preload: true.  A page records nothing for it."
  (string-equal (hunchentoot:header-in* :tun-preload) "true"))

(defun decline-preload ()
  "What a page returns for a preload when it would record something for the
GET: the browser drops the preload, and the click asks again."
  (values 204 :declined))

(defun answer-declined-preload ()
  (setf (hunchentoot:return-code*) 204
        (hunchentoot:header-out "Tun-Preload") "declined")
  "")

(defun see-other (path)
  "Answer 303 to PATH, or, to htmx asking for part of a page, 200 with
HX-Location: PATH, so htmx loads PATH as a boosted link would rather than
swap the whole page into the part (spec/ui.md 8.1).  Unlike
HUNCHENTOOT:REDIRECT it returns normally, so the request's record ends as ok
rather than as aborted."
  (if (htmx-request-p)
      (setf (hunchentoot:header-out "HX-Location") path)
      (setf (hunchentoot:return-code*) 303
            (hunchentoot:header-out :location) path))
  "")

(defun screen (name &rest arguments)
  "Render screen NAME (extension output: confirm tools cannot be asked for)."
  (let ((*inside-operation* t))
    (untrusted (apply #'render-screen *web-app* name arguments))))

(defun web-call (tool arguments)
  "Call TOOL as the logged-in actor. Values: JSON result and the error code (or NIL)."
  (handler-case (values (call-tool tool arguments :application *web-app* :actor *actor*) nil)
    (operation-error (e) (values (operation-error-json e) (operation-error-code e)))))

;;; ------------------------------------------------------------------
;;; The page: a document around an app-shell

(defparameter +navigation-count+ "^(.*\\S)\\s*\\(([0-9]+\\+?)\\)$"
  "A menu title that ends in a count in parentheses, such as Varsler (3).")

(defun navigation-label (text)
  "TEXT, a menu title that may end in a count in parentheses (\"Varsler (3)\",
from STAFF-NAVIGATION-TITLE), as values the label and the count, or NIL for
no count or a count of zero."
  (multiple-value-bind (match groups) (cl-ppcre:scan-to-strings +navigation-count+ text)
    (if match
        (values (aref groups 0) (unless (string= (aref groups 1) "0") (aref groups 1)))
        (values text nil))))

(defun owner-rank (page)
  "Where PAGE comes in its part of the menu, by who registered it: the
client's pages first, then the modules', then the kernel's own."
  (let ((module (staff-page-module page)))
    (cond ((equal module "client") 0)
          ((equal module "core") 2)
          (t 1))))

(defun menu-pages (group)
  "The staff pages of GROUP (:WORK or :SYSTEM) in the menu that the actor may
see, as (PREFIX . PAGE), by OWNER-RANK and then in the order registered."
  (let ((pages '()))
    (maphash (lambda (prefix page)
               (when (and (staff-page-navigation page)
                          (eq (staff-page-group page) group)
                          (page-available-p page)
                          (actor-permits-p *actor* (staff-page-policy page)))
                 (push (cons prefix page) pages)))
             *staff-pages*)
    (sort pages (lambda (a b)
                  (let ((a-rank (owner-rank (cdr a))) (b-rank (owner-rank (cdr b))))
                    (or (< a-rank b-rank)
                        (and (= a-rank b-rank)
                             (< (staff-page-sequence (cdr a)) (staff-page-sequence (cdr b))))))))))

(defun page-entry (entry)
  "The nav-list item of ENTRY, a (PREFIX . PAGE) of MENU-PAGES."
  (destructuring-bind (prefix . page) entry
    (multiple-value-bind (label count)
        (navigation-label (staff-navigation-title *web-app* prefix (staff-page-title page)))
      (list :label label :href (format nil "/~a" prefix)
            :icon (staff-page-icon page) :count count))))

(defun resource-entry (resource)
  (list :label (resource-title resource) :href (resource-path resource)
        :icon (resource-icon resource)))

(defun navigation ()
  "The staff menu as nav-list groups (spec/ui.md 8): first the business's
work, which is the client's own pages, every resource, then the modules' and
the kernel's pages; then, under «System», the pages about the system."
  (let* ((work (menu-pages :work))
         (clients-p (lambda (entry) (zerop (owner-rank (cdr entry)))))
         (items (append (mapcar #'page-entry (remove-if-not clients-p work))
                        (mapcar #'resource-entry (reverse *resources*))
                        (mapcar #'page-entry (remove-if clients-p work))))
         (system (mapcar #'page-entry (menu-pages :system))))
    (remove nil (list (and items (list :items items))
                      (and system (list :heading "System" :items system))))))

(defun navigation-items ()
  "Every entry of the staff menu, in its order."
  (loop for group in (navigation) append (getf group :items)))

(defun page-frame (body &key guest (home "/") (width :default))
  "BODY inside the app-shell, WIDTH wide: with the menu and the actor for
staff, without for someone not logged in or a GUEST page (whose title links
to HOME).  A staff page's links and forms go through htmx (spec/ui.md 4.1);
another page's do not, so signing in leaves for the provider's page."
  (let ((title (application-title *web-app*)))
    (if (and *actor* (not guest))
        (apply #'ui:app-shell* (list :title title :home "/" :nav-groups (navigation)
                                     :current (hunchentoot:script-name*)
                                     :user (actor-string *actor*) :logout-action "/logout"
                                     :width width
                                     ;; Inherited by every link and form in it.
                                     :attributes (list :hx-boost\:inherited "true"
                                                       :hx-headers\:inherited
                                                       (format nil "{\"Tun-Assets\": \"~a\"}"
                                                               (ui:asset-hashes))))
               (append body (staff-page-extras *web-app*)))
        (apply #'ui:app-shell* (list :title title :home home :width width) body))))

(defun page-document (title frame)
  "The whole HTML document of a page titled TITLE around FRAME."
  (list (trusted "<!doctype html>")
        `(:html (:@ :lang "no")
                (:head (:meta (:@ :charset "utf-8"))
                       (:meta (:@ :name "viewport" :content "width=device-width, initial-scale=1"))
                       (:meta (:@ :name "htmx-config" :content ,(ui:htmx-config)))
                       (:title ,title " – " ,(application-title *web-app*))
                       ,@(web-app-head)
                       (:link (:@ :rel "stylesheet" :href ,(ui:stylesheet-path)))
                       (:script (:@ :defer t :src ,(ui:htmx-path)))
                       (:script (:@ :defer t :src ,(ui:script-path))))
                (:body ,frame))))

(defun respond (status title body &key description actions breadcrumbs guest (home "/")
                                    (width :default))
  "Answer STATUS with the page TITLE: a page header (with DESCRIPTION,
ACTIONS and BREADCRUMBS) and then BODY, a list of nodes, in the frame
PAGE-FRAME chooses, WIDTH wide."
  (setf (hunchentoot:return-code*) status
        (hunchentoot:content-type*) "text/html; charset=utf-8")
  (let ((header (ui:page-header* (list :title title :description description
                                       :actions actions :breadcrumbs breadcrumbs))))
    (sb-ext:string-to-octets
     (render-html (page-document title (page-frame (cons header body)
                                                   :guest guest :home home :width width)))
     :external-format :utf-8)))

(defun respond-fragment (status body)
  "Answer STATUS with BODY, a list of nodes, alone: the part of a page htmx
asked for (spec/ui.md 8.1)."
  (setf (hunchentoot:return-code*) status
        (hunchentoot:content-type*) "text/html; charset=utf-8")
  (sb-ext:string-to-octets (render-html body) :external-format :utf-8))

(defun stale-assets-p ()
  "True for htmx asking for a whole page from a page whose stylesheet or
script is not the current one, sent in Tun-Assets (spec/ui.md 4.1): after a
deploy that changed them, the next page is loaded in full."
  (let ((sent (hunchentoot:header-in* :tun-assets)))
    (and sent
         (string-equal (hunchentoot:header-in* :hx-request-type) "full")
         (string/= sent (ui:asset-hashes)))))

(defun section (title &rest body)
  "A part of a page under the heading TITLE (a design system section)."
  (apply #'ui:section* (list :title title) body))

;;; ------------------------------------------------------------------
;;; Errors

(defparameter +error-titles+
  '((:forbidden . "Du har ikke tilgang til dette")
    (:not-found . "Finnes ikke")
    (:conflict . "Noen andre har endret dette")
    (:idempotency-conflict . "Skjemaet er allerede sendt")
    (:invalid-transition . "Dette kan ikke gjøres nå")
    (:unavailable . "Ikke tilgjengelig")
    (:insufficient-stock . "Ikke nok på lager")
    (:invalid-input . "Noe må rettes"))
  "The heading of an error the page shows, by its code; others get the last.")

(defun error-title (code)
  (or (cdr (assoc code +error-titles+)) "Det gikk ikke"))

(defun error-code-keyword (json)
  "The code of the error document JSON as a keyword, :invalid_input as :INVALID-INPUT."
  (let ((code (jget (jget json "error") "code")))
    (and (stringp code) (intern (string-upcase (substitute #\- #\_ code)) :keyword))))

(defun sentence (text)
  "TEXT with its first letter in upper case."
  (if (plusp (length text))
      (concatenate 'string (string-upcase (subseq text 0 1)) (subseq text 1))
      text))

(defun error-alert (json)
  "The error document JSON as a destructive alert carrying its code in
data-code: a refusal that belongs to no form, or a form not on this page."
  (let ((err (jget json "error")))
    (ui:alert (:variant :destructive :title (error-title (error-code-keyword json))
                        :attributes (list :data-code (jget err "code")))
              (let ((fields (coerce (or (jget err "fields") #()) 'list)))
                (if fields
                    `(:ul ,@(mapcar (lambda (field)
                                      `(:li ,(field-error-sentence (jget field "field")
                                                                   (jget field "message"))))
                                    fields))
                    (jget err "message"))))))

(defun field-error-sentence (label message)
  "An error MESSAGE about the field LABEL as a sentence for an error summary:
a fragment such as \"må fylles ut\" follows the label, a sentence of its own
stands alone."
  (if (and (plusp (length message)) (lower-case-p (char message 0)))
      (format nil "~a ~a" label message)
      message))

;;; ------------------------------------------------------------------
;;; Showing values

(defparameter +value-labels+
  '(("active" . "Aktiv") ("disabled" . "Deaktivert") ("revoked" . "Trukket tilbake")
    ("expired" . "Utløpt") ("person" . "Person") ("agent" . "Agent")
    ("admin" . "Administrator") ("employee" . "Ansatt") ("viewer" . "Lesetilgang"))
  "Norwegian labels for the kernel's own English values (accounts and tokens).")

(defparameter +status-variants+
  '(("utkast" . :outline) ("tilbud_sendt" . :info) ("akseptert" . :info)
    ("bekreftet" . :success) ("hentet" . :secondary) ("returnert" . :secondary)
    ("send_faktura" . :warning) ("fullført" . :success) ("avbrutt" . :destructive)
    ("ny" . :info) ("behandlet" . :success) ("avvist" . :destructive)
    ("active" . :success) ("disabled" . :outline) ("revoked" . :destructive)
    ("expired" . :outline))
  "The badge variant of the status words Tun's modules and the kernel use;
any other status is secondary.  The badge's text says what it is, so the
colour is never the only difference (spec/ui.md, badge).")

(defun humanize (value)
  "VALUE, a stored word such as tilbud_sendt or active, as a label:
Tilbud sendt, Aktiv."
  (let ((value (princ-to-string value)))
    (or (cdr (assoc value +value-labels+ :test #'string=))
        (sentence (substitute #\Space #\_ value)))))

(defun status-badge (value)
  "A badge for the status VALUE."
  (ui:badge (:variant (or (cdr (assoc value +status-variants+ :test #'equal)) :secondary))
            (humanize value)))

(defun group-thousands (n)
  "The natural number N with a no-break space between each group of three digits."
  (let ((digits (princ-to-string n)))
    (with-output-to-string (out)
      (loop for char across digits
            for left downfrom (length digits)
            do (write-char char out)
            (when (and (> left 1) (zerop (mod (1- left) 3)))
              (write-char #\No-break_space out))))))

(defun kroner-text (ore)
  "An amount in øre as Norwegians write kroner: 12 450,00 kr."
  (multiple-value-bind (kroner rest) (floor (abs ore) 100)
    (format nil "~:[~;−~]~a,~2,'0d kr" (minusp ore) (group-thousands kroner) rest)))

(defun date-text (date)
  "DATE, YYYY-MM-DD, as DD.MM.YYYY; anything else as it is."
  (if (and (stringp date) (valid-date-string-p date))
      (format nil "~a.~a.~a" (subseq date 8 10) (subseq date 5 7) (subseq date 0 4))
      (princ-to-string date)))

(defun timestamp-text (value)
  "The RFC 3339 instant VALUE in Norwegian local time: 13.10.2026 kl. 14:32."
  (let ((ut (parse-rfc3339 value)))
    (if ut
        (format nil "~a kl. ~a" (date-text (local-date-of ut)) (local-time-of ut))
        (princ-to-string value))))

(defun number-text (value)
  "A number with a decimal comma: 12,5."
  (substitute #\, #\. (if (integerp value) (princ-to-string value) (format-quantity value 3))))

(defun money-field-p (type json-name)
  "True for an amount: an integer field whose name ends in _ore (Tun keeps
money as integer øre)."
  (and (typep type 'integer-type)
       (let ((suffix "_ore"))
         (and (> (length json-name) (length suffix))
              (string= suffix json-name :start2 (- (length json-name) (length suffix)))))))

(defun shown-label (label)
  "LABEL as a heading over shown values: an amount shown in kroner drops the
\"(øre)\" it is stored in."
  (let ((suffix " (øre)"))
    (if (and (> (length label) (length suffix))
             (string= suffix label :start2 (- (length label) (length suffix))))
        (subseq label 0 (- (length label) (length suffix)))
        label)))

(defun display-value (value)
  "VALUE of unknown type as text: yes and no, lists by their length or joined."
  (cond ((json-null-p value) "")
        ((eq value t) "Ja")
        ((null value) "Nei")
        ((hash-table-p value) (to-json-string value))
        ((json-array-p value)
         (if (every #'stringp value)
             (format nil "~{~a~^, ~}" (coerce value 'list))
             (format nil "~d element" (length value))))
        ((realp value) (number-text value))
        ((and (stringp value) (valid-date-string-p value)) (date-text value))
        ((and (stringp value) (<= 20 (length value) 35) (parse-rfc3339 value))
         (timestamp-text value))
        (t (princ-to-string value))))

(defvar *reference-labels* nil
  "For this request: entity class name -> ((id . label) ...), read once
through the entity's list operation.")

(defun list-tool-for (class)
  "The operation that lists the records of CLASS: its read tool named *_list."
  (flet ((lists-p (op)
           (let ((tool (operation-tool op)))
             (and (eq (operation-entity op) (class-name class))
                  (eq (operation-kind op) :read)
                  (> (length tool) 5)
                  (string= "_list" tool :start2 (- (length tool) 5))))))
    (find-if #'lists-p (visible-operations *web-app*))))

(defun reference-labels (class)
  "(id . label) of the records of CLASS the actor may list, at most 100:
their name, else their id."
  (let ((cache (or *reference-labels* (setf *reference-labels* (make-hash-table)))))
    (multiple-value-bind (labels found) (gethash (class-name class) cache)
      (if found
          labels
          (setf (gethash (class-name class) cache)
                (let ((op (list-tool-for class)))
                  (when op
                    (map 'list #'record-label
                         (jget (web-call (operation-tool op) (jobj "limit" 100))
                               "items" #())))))))))

(defun record-label (item)
  "(id . label) of the JSON record ITEM: its name, else its id."
  (let ((name (jget item "name")))
    (cons (jget item "id") (if (stringp name) name (jget item "id")))))

(defun record-path (entity id)
  "The detail page of record ID of ENTITY (a class name), or NIL when it has none."
  (let ((resource (find-if (lambda (resource)
                             (and (eq (resource-entity resource) entity)
                                  (resource-detail-screen resource)))
                           *resources*)))
    (and resource (format nil "~a/~a" (resource-path resource) id))))

(defun reference-markup (type id &key link)
  "The record ID that a field of the id TYPE refers to, by its name; with
LINK, a link to its page when it has one."
  (let* ((class (find-entity-class (id-references type) nil))
         (label (or (and class (cdr (assoc id (reference-labels class) :test #'equal))) id))
         (path (and link class (record-path (class-name class) id))))
    (if path (ui:link (:href path) label) label)))

(defun empty-value-p (type value)
  (or (json-null-p value)
      (and (null value) (not (typep type 'boolean-type)))
      (and (stringp value) (zerop (length value)))))

(defun value-markup (type json-name value &key link)
  "VALUE of the field JSON-NAME of TYPE as it is shown: a status as a badge,
amounts in kroner, dates the Norwegian way, a reference by the name of the
record (LINK makes it a link)."
  (cond ((empty-value-p type value) "–")
        ((typep type 'boolean-type) (if (eq value t) "Ja" "Nei"))
        ((and (typep type 'enum-type) (string= json-name "status")) (status-badge value))
        ((typep type 'enum-type) (humanize value))
        ((money-field-p type json-name) (kroner-text value))
        ((typep type 'date-type) (date-text value))
        ((typep type 'timestamp-type) (timestamp-text value))
        ((and (typep type 'id-type) (id-references type) (stringp value))
         (reference-markup type value :link link))
        ((and (typep type 'list-type) (json-array-p value)
              (typep (list-element type) 'enum-type))
         (format nil "~{~a~^, ~}" (map 'list #'humanize value)))
        (t (display-value value))))

;;; ------------------------------------------------------------------
;;; Tables

(defstruct (column (:constructor make-column (name label type)))
  "A column of a table of records: the field's JSON name, its heading and type."
  name label type)

(defun column-spec (column)
  "COLUMN as the table component's column: amounts and numbers to the right."
  (let ((type (column-type column)))
    (if (or (money-field-p type (column-name column))
            (typep type '(or integer-type decimal-type)))
        (list (column-label column) :align :end)
        (column-label column))))

(defun scalar-type-p (type)
  (not (typep type '(or list-type json-type))))

(defun field-column (field)
  (make-column (field-json-name field)
               (shown-label (or (field-label field) (field-json-name field)))
               (field-type field)))

(defun string-length-limit (type)
  "The longest text a field of the string TYPE takes."
  (jget (type-json-schema type) "maxLength"))

(defun long-text-p (type)
  "True for a text field long enough to be written in a text area."
  (and (typep type 'string-type) (not (typep type 'email-type))
       (> (string-length-limit type) 200)))

(defun list-column-rank (field)
  "Where FIELD comes in a generated list, lower first, or NIL to leave it out:
the status, the records it refers to, dates, the total, the required inputs,
then other short inputs."
  (let ((type (field-type field))
        (name (field-json-name field)))
    (cond ((or (null (field-label field)) (not (scalar-type-p type))
               (typep type '(or boolean-type timestamp-type)) (long-text-p type)
               (member name '("name" "revision" "id") :test #'string=))
           nil)
          ((and (typep type 'enum-type) (string= name "status")) 0)
          ((and (typep type 'id-type) (id-references type)) 1)
          ((typep type 'date-type) 2)
          ((money-field-p type name) (when (string= name "total_ore") 3))
          ((and (field-input-p field) (field-required-p field)) 4)
          ((field-input-p field) 5))))

(defun list-columns (class &key (limit 5))
  "The columns of the generated list of CLASS, LIMIT in all: what names a
record (its name, else its id), then the fields LIST-COLUMN-RANK ranks, one
date only."
  (let* ((fields (entity-fields class))
         (name (find "name" fields :key #'field-json-name :test #'string=))
         ;; REMOVE-IF-NOT may share the cached field list's tail, which a
         ;; destructive sort must not touch.
         (ranked (stable-sort (copy-list (remove-if-not #'list-column-rank fields)) #'<
                              :key #'list-column-rank))
         (dated nil))
    (cons (if name
              (field-column name)
              (make-column "id" (entity-label class) nil))
          (loop for field in ranked
                for date-p = (typep (field-type field) 'date-type)
                unless (and date-p dated)
                collect (field-column field) into columns
                and do (when date-p (setf dated t))
                finally (return (subseq columns 0 (min (1- limit) (length columns))))))))

(defun record-table (items columns &key link empty)
  "A table of the JSON records ITEMS in COLUMNS.  LINK, a function of a
record, gives the page each row leads to; EMPTY is shown when there are no
ITEMS."
  (ui:table* (list :columns (mapcar #'column-spec columns)
                   :rows (mapcar (lambda (item)
                                   (mapcar (lambda (column)
                                             (value-markup (column-type column)
                                                           (column-name column)
                                                           (jget item (column-name column))))
                                           columns))
                                 items)
                   :row-href (when link (mapcar link items))
                   :empty (or empty "Ingen."))))

(defun json-table (items &key columns link)
  "A table of JSON objects ITEMS whose keys are the headings.  COLUMNS
defaults to the keys of the first item.  LINK, a function of an item, gives
the page its row leads to.  A list of plain values is shown one per line."
  (let* ((items (coerce items 'list))
         (columns (or columns (and items (hash-table-p (first items)) (jkeys (first items))))))
    (cond ((null items) '(:p "Ingen."))
          ((not (every #'hash-table-p items))
           (apply #'ui:stack* (list :gap :xs)
                  (mapcar (lambda (item) `(:p ,(display-value item))) items)))
          (t (ui:table* (list :columns columns
                              :rows (mapcar (lambda (item)
                                              (mapcar (lambda (column)
                                                        (display-value (jget item column)))
                                                      columns))
                                            items)
                              :row-href (when link (mapcar link items))))))))

;;; ------------------------------------------------------------------
;;; A record

(defun summary-columns (class)
  "The labelled fields of CLASS that hold one value or a list of plain values,
then its computed fields that hold one value."
  (append (loop for field in (entity-fields class)
                for type = (field-type field)
                when (and (field-label field) (not (typep type 'json-type)) (not (row-list-p type)))
                collect (field-column field))
          (loop for computed in (entity-computed-fields class)
                for type = (computed-field-type computed)
                when (scalar-type-p type)
                collect (make-column (computed-field-json-name computed)
                                     (shown-label (computed-field-label computed))
                                     type))))

(defun field-has-value-p (field item)
  "True when the JSON record ITEM has a value for FIELD."
  (not (empty-value-p (field-type field) (jget item (field-json-name field)))))

(defun element-columns (class items)
  "The columns of a table of the records ITEMS of CLASS (an order's lines):
the labelled fields that have a value in some item, the records they refer
to first, and not their own ids."
  (stable-sort (loop for field in (entity-fields class)
                     when (and (field-label field) (scalar-type-p (field-type field))
                               (string/= (field-json-name field) "id")
                               (some (lambda (item) (field-has-value-p field item)) items))
                     collect (field-column field))
               #'< :key (lambda (column)
                          (let ((type (column-type column)))
                            (if (and (typep type 'id-type) (id-references type)) 0 1)))))

(defun list-field-view (type value)
  "The value of a list field of TYPE whose items are records, as a table."
  (let ((items (coerce (if (json-array-p value) value #()) 'list)))
    (if items
        (let ((class (find-entity-class (list-element type))))
          (record-table items (element-columns class items)))
        '(:p "Ingen."))))

(defun entity-detail (class json)
  "Generic detail view of an entity's JSON: the fields that have a value in
a summary list (each value marked with data-field), lists of records as
tables, and computed JSON folded away below."
  (let ((class (if (symbolp class) (find-entity-class class) class)))
    (list
     (section "Opplysninger"
              (ui:summary-list
               (:rows (loop for column in (summary-columns class)
                            for type = (column-type column)
                            for value = (jget json (column-name column))
                            unless (or (empty-value-p type value)
                                       (and (json-array-p value) (zerop (length value))))
                            collect (list (column-label column)
                                          `(:span (:@ :data-field ,(column-name column))
                                                  ,(value-markup type (column-name column)
                                                                 value :link t)))))))
     (loop for field in (entity-fields class)
           when (row-list-p (field-type field))
           collect (section (or (field-label field) (field-json-name field))
                            (list-field-view (field-type field)
                                             (jget json (field-json-name field)))))
     (let ((derived (loop for computed in (entity-computed-fields class)
                          for value = (jget json (computed-field-json-name computed))
                          when (and (typep (computed-field-type computed) 'json-type)
                                    (json-value-shown-p value))
                          collect (list :title (computed-field-label computed)
                                        :content (json-view value)))))
       ;; Folded away: what the record's modules work out from it, which
       ;; matters now and then rather than every time.
       (when derived
         (section "Mer om posten" (ui:accordion (:items derived))))))))

(defun json-value-shown-p (value)
  (not (or (null value) (json-null-p value))))

(defun json-view (value)
  "A JSON array as a table, an object as a summary list, a scalar as text."
  (cond ((json-array-p value) (json-table value))
        ((hash-table-p value)
         (ui:summary-list (:rows (mapcar (lambda (key)
                                           (let ((text (display-value (jget value key))))
                                             (list key (if (zerop (length text)) "–" text))))
                                         (jkeys value)))))
        (t `(:p ,(display-value value)))))

;;; ------------------------------------------------------------------
;;; Forms generated from an operation's input

(defstruct (input-spec (:conc-name spec-)) name label type required description)

(defun field-input-spec (field)
  (make-input-spec :name (field-json-name field) :label (field-label field)
                   :type (field-type field) :required (field-required-p field)
                   :description (field-description field)))

(defun parameter-input-spec (parameter)
  (let ((label (or (parameter-label parameter) (parameter-json-name parameter)))
        (text (parameter-text parameter)))
    (make-input-spec :name (parameter-json-name parameter) :label label
                     :type (parameter-type parameter) :required (parameter-required-p parameter)
                     ;; PARAMETER-TEXT falls back to the label, which is no hint.
                     :description (unless (member text (list label (parameter-json-name parameter))
                                                  :test #'equal)
                                    text))))

(defun operation-inputs (op)
  "The inputs of OP in form order: its draft entity's input fields, then its
parameters.  A parameter named like a draft field takes that field's place
(orders_create's lines, which must have at least one line)."
  (let ((parameters (mapcar #'parameter-input-spec (operation-parameters op))))
    (flet ((parameter (name) (find name parameters :key #'spec-name :test #'string=)))
      (let ((draft (when (operation-draft-p op)
                     (mapcar (lambda (field)
                               (or (parameter (field-json-name field)) (field-input-spec field)))
                             (entity-input-fields (find-entity-class (operation-entity op)))))))
        (append draft (remove-if (lambda (spec) (member spec draft)) parameters))))))

(defun element-inputs (list-type)
  (mapcar #'field-input-spec (entity-input-fields (find-entity-class (list-element list-type)))))

(defun row-list-p (type)
  "True for a list input whose items are records, entered as rows."
  (and (typep type 'list-type) (symbolp (list-element type))))

(defun reference-options (type)
  "(id . label) choices for an id field that references an entity, read through its list operation."
  (let ((class (and (id-references type) (find-entity-class (id-references type) nil))))
    (and class (reference-labels class))))

(defun control-id (form-id name)
  "The id of the control NAME in the form FORM-ID: lines[0][quantity] in
orders_create is orders_create-lines-0-quantity."
  (format nil "~a-~a" form-id
          (string-right-trim "-" (substitute-if #\- (lambda (c) (find c "[]")) name))))

(defun error-path-name (path)
  "The form name of the field PATH in an error: lines[0].quantity is
lines[0][quantity]."
  (cl-ppcre:regex-replace-all "\\.([^.\\[]+)" path "[\\1]"))

(defun field-errors (error-json)
  "The field errors of ERROR-JSON as (form name . message), each name once."
  (let ((errors '()))
    (map nil (lambda (field)
               (let ((name (error-path-name (jget field "field"))))
                 (unless (assoc name errors :test #'string=)
                   (push (cons name (jget field "message")) errors))))
         (jget (jget error-json "error") "fields" #()))
    (nreverse errors)))

(defun field-error-message (name errors)
  "The error message for the control NAME among ERRORS, or NIL: its own, or
one about an item of it (tags[0] for the checkboxes tags), as a sentence."
  (let ((message (field-error-fragment name errors)))
    (and message (sentence message))))

(defun field-error-fragment (name errors)
  (cdr (find-if (lambda (error-name)
                  (or (string= error-name name)
                      (and (> (length error-name) (length name))
                           (string= name error-name :end2 (length name))
                           (cl-ppcre:scan "^\\[[0-9]+\\]$" (subseq error-name (length name))))))
                errors :key #'car)))

(defun posted (name values)
  "The posted value of NAME in VALUES, an alist of form parameters."
  (cdr (assoc name values :test #'string=)))

(defun posted-all (name values)
  "Every posted value of NAME in VALUES (a group of checkboxes sends several)."
  (loop for (key . value) in values when (string= key name) collect value))

(defun text-width (type)
  "The width in characters of a text field for a value of TYPE, or NIL for
the full width."
  (cond ((typep type '(or integer-type decimal-type)) 10)
        ((and (typep type 'string-type) (not (typep type 'email-type)))
         (let ((max (string-length-limit type)))
           (cond ((<= max 10) 10) ((<= max 20) 20) (t nil))))))

(defun enum-choices (type)
  (mapcar (lambda (value) (list value (humanize value))) (enum-values type)))

(defun nothing-yet (class)
  "The hint of an input that refers to CLASS, of which there are no records yet."
  (format nil "Det finnes ingen ~(~a~) ennå." (entity-label class)))

(defun form-control (spec name id &key values error options (required (spec-required spec))
                                    (optional (not (spec-required spec))))
  "The control for the input SPEC, posted as NAME with the id ID: chosen
from its type, labelled, with its description as the hint, its value from
VALUES (the posted form) and its ERROR.  OPTIONS, (id . label) pairs, are
when given the only choices an id input offers, and one must be made.
REQUIRED marks the control required; OPTIONAL labels it «(valgfritt)»."
  (let* ((type (spec-type spec))
         (label (or (spec-label spec) (spec-name spec)))
         (hint (spec-description spec))
         (value (posted name values))
         (common (list :label label :name name :id id :hint hint :error error
                       :optional optional)))
    (flet ((choose (choices &key (prompt "Velg"))
             (ui:select* (append common (list :options choices :selected value :prompt prompt
                                              :required required))))
           (text (&rest more)
             (ui:text-input* (append common (list :value value :required required) more))))
      (cond (options
             ;; The keys before COMMON win: these choices must be made.
             (ui:select* (append (list :options (mapcar (lambda (option)
                                                          (list (car option) (cdr option)))
                                                        options)
                                       :selected value :prompt "Velg" :required t :optional nil)
                                 common)))
            ((typep type 'boolean-type)
             (ui:checkbox (:label label :name name :id id :hint hint :error error
                                  :checked (and value t))))
            ((typep type 'enum-type)
             (let ((choices (enum-choices type)))
               (if (and required (<= (length choices) 4))
                   (ui:radios* (list :legend label :name name :id id :hint hint :error error
                                     :choices choices :selected value :required t
                                     :inline (<= (length choices) 3)))
                   (choose choices))))
            ((and (typep type 'list-type) (typep (list-element type) 'enum-type))
             (ui:checkboxes* (list :legend label :name name :id id :hint hint :error error
                                   :optional optional :choices (enum-choices (list-element type))
                                   :selected (posted-all name values))))
            ((typep type 'id-type)
             (let ((choices (reference-options type)))
               (cond (choices
                      (choose (mapcar (lambda (choice) (list (car choice) (cdr choice))) choices)))
                     ((and (id-references type) (find-entity-class (id-references type) nil))
                      ;; Nothing to choose from yet: the id can still be typed.
                      (let ((class (find-entity-class (id-references type))))
                        (ui:text-input* (append (list :value value :required required :width 30
                                                      :hint (nothing-yet class))
                                                common))))
                     (t (text :width 30)))))
            ((typep type 'integer-type) (text :type :number :inputmode "numeric" :width 10))
            ((typep type 'decimal-type) (text :inputmode "decimal" :width 10))
            ((typep type 'date-type) (text :type :date))
            ((typep type 'email-type) (text :type :email :autocomplete "off"))
            ((or (long-text-p type) (typep type 'json-type))
             (ui:textarea* (append common (list :value value :rows 3 :required required))))
            (t (text :width (text-width type)))))))

(defun row-count (name values)
  "How many rows of the list input NAME to offer: the empty rows, or as many
as were posted."
  (max +form-line-rows+
       (loop for row from 0 below 100
             while (find-if (lambda (pair)
                              (string-prefix-p (format nil "~a[~d]" name row) (car pair)))
                            values)
             finally (return row))))

(defun row-fieldset (spec form-id row &key values errors)
  "Row ROW (from 0) of the list input SPEC: the required inputs of an item,
and its other inputs folded away unless one of them has a value or an error."
  (let* ((element-class (find-entity-class (list-element (spec-type spec))))
         (inputs (element-inputs (spec-type spec)))
         (controls (mapcar (lambda (input)
                             (let ((name (format nil "~a[~d][~a]" (spec-name spec) row
                                                 (spec-name input))))
                               (cons input
                                     (form-control input name (control-id form-id name)
                                                   :values values
                                                   :error (field-error-message name errors)
                                                   :required nil :optional nil))))
                           inputs))
         (main (remove-if-not #'spec-required controls :key #'car))
         (more (remove-if #'spec-required controls :key #'car))
         (open (some (lambda (control)
                       (let ((name (format nil "~a[~d][~a]" (spec-name spec) row
                                           (spec-name (car control)))))
                         (or (not (blank-p (posted name values)))
                             (field-error-message name errors))))
                     more)))
    (ui:card (:size :sm)
             (ui:fieldset (:legend (row-legend element-class row))
               (apply #'ui:grid* (list :min :sm) (mapcar #'cdr main))
               (when more
                 (ui:accordion (:items (list (list :title "Flere valg" :open (and open t)
                                                   :content (apply #'ui:stack* (list :gap :lg)
                                                                   (mapcar #'cdr more)))))))))))

(defun row-legend (element-class row)
  "The heading of row ROW (from 0) of a list of ELEMENT-CLASS records: Ordrelinje 1."
  (format nil "~a ~d" (or (entity-label element-class) "Rad") (1+ row)))

(defun row-input-label (name specs)
  "The label of the control NAME among the inputs SPECS, as an error summary
names it: Kunde, or for a row of a list, Antall i ordrelinje 1."
  (let* ((top (subseq name 0 (or (position #\[ name) (length name))))
         (spec (find top specs :key #'spec-name :test #'string=))
         (label (or (and spec (spec-label spec)) name)))
    (cl-ppcre:register-groups-bind ((#'parse-integer row) input)
        ("^[^\\[]+\\[([0-9]+)\\]\\[([^\\]]+)\\]$" name)
      (when (and spec (row-list-p (spec-type spec)))
        (let ((element (find input (element-inputs (spec-type spec)) :key #'spec-name
                             :test #'string=))
              (class (find-entity-class (list-element (spec-type spec)))))
          (return-from row-input-label
            (format nil "~a i ~(~a~)" (or (and element (spec-label element)) input)
                    (row-legend class row))))))
    label))

(defun form-error-summary (error-json form-id specs)
  "The error summary at the top of a form whose submission ERROR-JSON
refused: each field error links to its control, with the field's label."
  (let ((err (jget error-json "error"))
        (errors (field-errors error-json)))
    (flet ((label-of (name)
             (row-input-label name specs)))
      (ui:error-summary* (list :title (if errors
                                          "For å gå videre må du rette opp følgende feil:"
                                          (error-title (error-code-keyword error-json)))
                               :errors (mapcar (lambda (entry)
                                                 (list (control-id form-id (car entry))
                                                       (field-error-sentence (label-of (car entry))
                                                                             (cdr entry))))
                                               errors)
                               :attributes (list :data-code (jget err "code")))
                         (unless errors `(:p ,(jget err "message")))))))

(defun form-inputs (op omit)
  "The inputs of OP but those named in OMIT, in the order a form asks for
them: yes-or-no questions last, after what the record is."
  (stable-sort (remove-if (lambda (spec) (member (spec-name spec) omit :test #'string=))
                          (operation-inputs op))
               (lambda (a b)
                 (and (not (typep (spec-type a) 'boolean-type))
                      (typep (spec-type b) 'boolean-type)))))

(defun operation-form (op action &key (title (operation-title op)) (submit title) omit choices
                                   values error-json id cancel description)
  "A card with a <form> for OP, generated from its input schema (client
fields included), without the inputs named in OMIT.  CHOICES, an alist of
input name to (id . label) pairs, limits what those id inputs offer.
VALUES, the posted form, fills the controls, and ERROR-JSON, the refusal of
that submission, puts an error summary on top and each field's error at the
field.  ID is the card's id; CANCEL a link back without saving."
  (let ((form-id (operation-tool op))
        (specs (form-inputs op omit))
        (errors (and error-json (field-errors error-json))))
    (ui:card (:title title :description description :heading-level 2 :id id)
             `(:form (:@ :method "post" :action ,action :data-tool ,(operation-tool op)
                         :novalidate t)
                     ,(apply #'ui:stack* (list :gap :lg)
                             (when error-json (form-error-summary error-json form-id specs))
                             (append
                              (mapcar (lambda (spec)
                                        (input-control spec form-id :values values :errors errors
                                                       :choices choices))
                                      specs)
                              (list (ui:form-actions (:cancel cancel)
                                      (ui:button (:type "submit") submit)))))
                     (:input (:@ :type "hidden" :name "request_key" :value ,(new-id "web")))))))

(defun input-control (spec form-id &key values errors choices)
  "The control of the input SPEC in the form FORM-ID: a fieldset of rows for
a list of records, else FORM-CONTROL's.  CHOICES as for OPERATION-FORM."
  (let ((name (spec-name spec)))
    (if (row-list-p (spec-type spec))
        (apply #'ui:fieldset*
               (list :legend (or (spec-label spec) name) :legend-size :section
                     :hint (spec-description spec) :error (field-error-message name errors)
                     :id (control-id form-id name))
               (loop for row below (row-count name values)
                     collect (row-fieldset spec form-id row :values values :errors errors)))
        (form-control spec name (control-id form-id name)
                      :values values :error (field-error-message name errors)
                      :options (cdr (assoc name choices :test #'string=))))))

(defun parse-decimal (text)
  "TEXT, a decimal number with a comma or a point (12,5), as the exact
rational, or NIL."
  (let ((text (remove #\Space (substitute #\. #\, (trim text)))))
    (when (cl-ppcre:scan "^-?[0-9]+(\\.[0-9]+)?$" text)
      (let* ((negative (char= (char text 0) #\-))
             (digits (remove #\- text))
             (dot (position #\. digits))
             (decimals (if dot (- (length digits) dot 1) 0)))
        (* (if negative -1 1)
           (/ (parse-integer (remove #\. digits)) (expt 10 decimals)))))))

(defun row-value (list-type name row params)
  "Row ROW of the list input NAME, of LIST-TYPE, decoded from PARAMS into a
JSON object of the values that were filled in."
  (let ((object (jobj)))
    (dolist (input (element-inputs list-type) object)
      (let ((value (form-value input (format nil "~a[~d][~a]" name row (spec-name input))
                               params)))
        (unless (eq value :absent) (setf (gethash (spec-name input) object) value))))))

(defun form-value (spec name params)
  "Decode the posted value of SPEC (form field NAME) into JSON, or :ABSENT."
  (let ((type (spec-type spec))
        (raw (posted name params)))
    (cond ((typep type 'boolean-type) (and raw t))
          ((row-list-p type)
           (let ((rows (loop for row below 100
                             for object = (row-value type name row params)
                             while (or (< row +form-line-rows+)
                                       (assoc (format nil "~a[~d]" name row) params
                                              :test (lambda (a b) (string-prefix-p a b))))
                             when (plusp (hash-table-count object)) collect object)))
             (if rows (jarr rows) :absent)))
          ((and (typep type 'list-type) (typep (list-element type) 'enum-type))
           (let ((chosen (posted-all name params)))
             (if chosen (jarr chosen) :absent)))
          ((or (null raw) (zerop (length (trim raw)))) :absent)
          ((typep type 'integer-type)
           (handler-case (parse-integer (remove #\Space (trim raw))) (error () raw)))
          ((typep type 'decimal-type) (or (parse-decimal raw) raw))
          ((typep type 'json-type)
           ;; Invalid JSON goes on as text, for the operation to refuse.
           (handler-case (parse-json raw) (error () raw)))
          (t raw))))

(defun form-arguments (op params)
  (let ((args (jobj)))
    (dolist (spec (operation-inputs op))
      (let ((v (form-value spec (spec-name spec) params)))
        (unless (eq v :absent) (setf (gethash (spec-name spec) args) v))))
    (let ((key (posted "request_key" params)))
      (when (and key (operation-mutating-p op)) (setf (gethash "request_key" args) key)))
    (let ((token (posted "confirmation_token" params)))
      (when (and token (operation-confirm-p op)) (setf (gethash "confirmation_token" args) token)))
    args))

;;; ------------------------------------------------------------------
;;; Screens

(defgeneric render-screen (application screen &key &allow-other-keys)
  (:documentation "The body (HTML as data) of the named SCREEN. Core provides
generated defaults; a client overrides a screen with a method specialized on
its application class (and may include the default via CALL-NEXT-METHOD)."))

(register-extension-protocol 'render-screen "screen" :point "screen"
                             :description "Bodies of the generated pages; a module or client overrides one by name.")

(defun screen-resource (screen)
  (find-if (lambda (r) (or (eq (resource-list-screen r) screen) (eq (resource-detail-screen r) screen)))
           *resources*))

(defun empty-list (resource)
  "What the list of RESOURCE shows when it has no records yet."
  (let ((create (and (resource-create-tool resource)
                     (not (eq (actor-role *actor*) :viewer))
                     (find-operation-by-tool (resource-create-tool resource)))))
    (ui:empty-state (:icon (resource-icon resource)
                           :title (format nil "Ingen ~(~a~) ennå" (resource-title resource))
                           :description (if create
                                            "Det du oppretter, vises her."
                                            "Det som blir opprettet, vises her."))
                    (when create
                      (ui:button (:href "#ny" :icon :plus) (operation-title create))))))

(defmethod render-screen (app screen &rest arguments &key items &allow-other-keys)
  ;; The generated default of every registered screen, least specific of
  ;; all: a module's or client's method for the screen comes first.
  (declare (ignore app))
  (let* ((resource (or (screen-resource screen) (error "No resource renders screen ~s" screen)))
         (class (find-entity-class (resource-entity resource))))
    (cond ((not (eq screen (resource-list-screen resource)))
           (entity-detail class (getf arguments (resource-detail-key resource))))
          ((null items) (empty-list resource))
          (t (record-table items (list-columns class)
                           :link (and (resource-detail-screen resource)
                                      (lambda (item)
                                        (format nil "~a/~a" (resource-path resource)
                                                (jget item "id")))))))))

(defun transition-tool-p (op resource)
  "A status operation of RESOURCE's entity that a button can call: a
transition whose only required input is the id."
  (and (eq (operation-entity op) (resource-entity resource))
       (eq (operation-kind op) :transition)
       (equal '("id") (mapcar #'parameter-json-name (remove-if-not #'parameter-required-p (operation-parameters op))))))

(defparameter +menu-threshold+ 2
  "More status operations than this go in a menu instead of a row of buttons.")

(defun record-actions (resource id)
  "The record's status operations, each posting to <path>/<id>/<tool>.
Values the page header's actions (buttons, or a menu when there are many)
and the forms a menu's items submit, which must be on the page too."
  (let ((ops (remove-if-not (lambda (op) (transition-tool-p op resource))
                            (visible-operations *web-app*))))
    (flet ((url (op) (format nil "~a/~a/~a" (resource-path resource) id (operation-tool op))))
      (if (<= (length ops) +menu-threshold+)
          (values (mapcar (lambda (op)
                            `(:form (:@ :method "post" :action ,(url op))
                                    ,(action-button op)))
                          ops)
                  nil)
          (values (list (ui:dropdown-menu (:label "Handlinger" :align :end
                                                  :items (action-menu-items ops))))
                  `(:div (:@ :hidden t)
                         ,@(mapcar (lambda (op)
                                     `(:form (:@ :id ,(action-form-id op) :method "post"
                                                 :action ,(url op))))
                                   ops)))))))

(defun action-button (op)
  "The button that submits the status operation OP."
  (ui:button (:type "submit" :variant :outline
                    :attributes (list :data-tool (operation-tool op)))
             (operation-title op)))

(defun action-form-id (op)
  "The id of the hidden form a menu item for the status operation OP submits."
  (format nil "handling-~a" (operation-tool op)))

(defun action-menu-items (ops)
  "The menu items of the status operations OPS: what ends or removes the
record comes last, apart and marked."
  (flet ((item (op)
           (let ((tool (operation-tool op)))
             (list :label (operation-title op)
                   :variant (when (destructive-tool-p tool) :destructive)
                   :attributes (list :type "submit" :form (action-form-id op)
                                     :data-tool tool)))))
    (let ((ending (remove-if-not #'destructive-tool-p ops :key #'operation-tool)))
      (append (mapcar #'item (remove-if (lambda (op) (member op ending)) ops))
              (when ending (list :separator))
              (mapcar #'item ending)))))

;;; ------------------------------------------------------------------
;;; Handlers

(defparameter +claimed-login-text+
  "Denne serveren lar deg velge hvem du er: /login?actor=rolle:navn, med rollen admin,
employee eller viewer."
  "What the login page says on a server with claimed identity.")

(defun claimed-login-hint ()
  "On a server with claimed identity: how to log in as anyone, and links that do."
  (when (claimed-identity-p *web-app*)
    (flet ((as (actor label)
             (ui:button (:href (format nil "/login?actor=~a" actor) :variant :outline) label)))
      (ui:card (:title "Testinnlogging" :heading-level 2
                       :description +claimed-login-text+)
               (ui:cluster ()
                           (as "admin:demo" "Som administrator")
                           (as "employee:demo" "Som ansatt")
                           (as "viewer:demo" "Med lesetilgang"))))))

(defun require-login ()
  "A 401 page when no one is logged in, else NIL."
  (unless *actor*
    (respond 401 "Logg inn"
             (list (ui:alert (:variant :info :title "Du er ikke innlogget")
                             "Logg inn for å se denne siden.")
                   (ui:cluster () (ui:button (:href "/login" :icon :log-in) "Logg inn"))
                   (claimed-login-hint)))))

(defun resource-page (resource &key error-json values (status 200))
  "The list of RESOURCE and, unless the actor only views, its create form;
after a refused submission, the form with VALUES and ERROR-JSON."
  (let* ((list-json (web-call (resource-list-tool resource) (jobj "limit" 100)))
         (create-op (find-operation-by-tool (resource-create-tool resource)))
         (viewer (eq (actor-role *actor*) :viewer))
         (form-p (and create-op (not viewer))))
    (respond status (resource-title resource)
             (list (when (and error-json (not form-p)) (error-alert error-json))
                   (when viewer
                     (ui:alert (:variant :info :title "Du har lesetilgang")
                               "Du er innlogget som lesetilgang (viewer); innsending blir avvist."))
                   (if (jget list-json "error")
                       (error-alert list-json)
                       (screen (resource-list-screen resource)
                               :items (coerce (jget list-json "items") 'list)))
                   (when form-p
                     (operation-form create-op (resource-path resource) :id "ny"
                                     :values values :error-json error-json)))
             ;; An empty list offers the same button itself.
             :actions (when (and form-p (plusp (length (jget list-json "items" #()))))
                        (list (ui:button (:href "#ny" :icon :plus) (operation-title create-op)))))))

(defun handle-resource (resource method)
  (or (require-login)
      (if (eq method :post)
          (let* ((op (find-operation-by-tool (resource-create-tool resource)))
                 (params (hunchentoot:post-parameters*))
                 (args (form-arguments op params)))
            (multiple-value-bind (json code) (web-call (resource-create-tool resource) args)
              (if code
                  (resource-page resource :error-json json :values params
                                 :status (error-status code))
                  (see-other (if (resource-detail-screen resource)
                                 (format nil "~a/~a" (resource-path resource) (jget json "id"))
                                 (resource-path resource))))))
          (resource-page resource))))

(defun record-title (class record id)
  "What a record's page is called: its name, else its kind and id."
  (let ((name (jget record "name")))
    (if (and (stringp name) (plusp (length name)))
        name
        (format nil "~a ~a" (entity-label class) id))))

(defun record-breadcrumbs (resource title)
  (list (list :label (resource-title resource) :href (resource-path resource))
        (list :label title)))

(defun detail-page (resource id &key error-json (status 200))
  (multiple-value-bind (record code) (web-call (resource-get-tool resource) (jobj "id" id))
    (if code
        (respond (error-status code) (resource-title resource) (list (error-alert record))
                 :breadcrumbs (record-breadcrumbs resource id))
        (let* ((class (find-entity-class (resource-entity resource)))
               (title (record-title class record id))
               (status-value (jget record "status")))
          (multiple-value-bind (actions forms) (record-actions resource id)
            (respond status title
                     (append (list (when error-json (error-alert error-json))
                                   forms
                                   (screen (resource-detail-screen resource)
                                           (resource-detail-key resource) record))
                             (render-resource-extras *web-app* (resource-entity resource) record))
                     :description (when (stringp status-value) (status-badge status-value))
                     :breadcrumbs (record-breadcrumbs resource title)
                     :actions actions))))))

(defparameter +destructive-tool-suffixes+ '("_cancel" "_erase" "_delete" "_revoke")
  "Tools whose confirmation is drawn as a warning: they end or remove something.")

(defun destructive-tool-p (tool)
  (some (lambda (suffix)
          (and (> (length tool) (length suffix))
               (string= suffix tool :start2 (- (length tool) (length suffix)))))
        +destructive-tool-suffixes+))

(defun confirmation-page (resource id op json)
  "What a :confirm operation shows before it runs: its summary and a form
that posts the confirmation token back."
  (let ((path (format nil "~a/~a" (resource-path resource) id))
        (title (format nil "~a ~a" (entity-label (find-entity-class (resource-entity resource)))
                       id))
        (expires (jget json "expires_at"))
        (destructive (destructive-tool-p (operation-tool op)))
        (token (jget json "confirmation_token")))
    (respond 200 title
             (list (ui:confirm-panel (:title (format nil "~a?" (operation-title op))
                                             :action (format nil "~a/~a" path (operation-tool op))
                                             :confirm-label (operation-title op)
                                             :cancel-href path :cancel-label "Gå tilbake"
                                             :variant (if destructive :destructive :primary)
                                             :icon (if destructive :triangle-alert :circle-check)
                                             :hidden (list (list "confirmation_token" token)))
                                     `(:p ,(jget json "summary"))
                                     (when (stringp expires)
                                       `(:p ,(format nil "Bekreftelsen utløper ~a."
                                                     (timestamp-text expires))))))
             :breadcrumbs (list (list :label (resource-title resource)
                                      :href (resource-path resource))
                                (list :label title :href path)
                                (list :label (operation-title op))))))

(defun handle-record-action (resource id tool)
  (let ((op (find-operation-by-tool tool))
        (path (resource-path resource)))
    (unless (and op (operation-visible-p op *web-app*) (transition-tool-p op resource))
      (return-from handle-record-action
        (respond 404 "Ukjent handling"
                 (list (ui:alert (:variant :warning) "Denne handlingen finnes ikke for posten.")))))
    (let ((args (jobj "id" id))
          (token (hunchentoot:post-parameter "confirmation_token")))
      (when (and token (operation-confirm-p op)) (setf (gethash "confirmation_token" args) token))
      (multiple-value-bind (json code) (web-call tool args)
        (cond (code (detail-page resource id :error-json json :status (error-status code)))
              ((eq t (jget json "confirmation_required"))
               (confirmation-page resource id op json))
              (t (see-other (format nil "~a/~a" path id))))))))

(defun home-path ()
  "Where / and a login lead: the first resource with detail pages (the work
list), else the first resource, else the first page in the menu."
  (let ((home (or (find-if #'resource-detail-screen *resources*) (first *resources*))))
    (cond (home (resource-path home))
          ((and *actor* (navigation-items)) (getf (first (navigation-items)) :href))
          (t "/login-info"))))

(defun cross-origin-post-p ()
  "True for a POST a browser sent from another origin (spec/auth.md 3.3).
A browser that sends Sec-Fetch-Site is judged by it alone: on a page with
Referrer-Policy: no-referrer its Origin is \"null\".  Otherwise an Origin
must be this server's own scheme://host:port (ports matter: two tenants on
one host are two origins, although the browser shares their cookies)."
  (let ((fetch-site (hunchentoot:header-in* :sec-fetch-site))
        (origin (hunchentoot:header-in* :origin))
        (host (hunchentoot:header-in* :host)))
    (cond (fetch-site
           (not (member fetch-site '("same-origin" "none") :test #'string-equal)))
          (origin
           (not (and host
                     (member origin (list (format nil "http://~a" host) (format nil "https://~a" host))
                             :test #'string-equal))))
          (t nil))))

(defun serve-asset (path)
  "The design system's stylesheet or script at PATH (spec/ui.md 4), or NIL.
The current version is cached for good; an older hash gets today's content,
uncached, so a page rendered before a deploy still gets styles."
  (multiple-value-bind (content type current) (ui:asset-content path)
    (when content
      (setf (hunchentoot:content-type*) type
            (hunchentoot:header-out "Cache-Control") (if current
                                                         "public, max-age=31536000, immutable"
                                                         "no-store"))
      (sb-ext:string-to-octets content :external-format :utf-8))))

(defun serve-specimen (parts)
  "/ui and /ui/NAME: the design system's specimen (spec/ui.md 7), or NIL."
  (let ((component (and (second parts) (ui:find-component (second parts)))))
    (when (and (null (cddr parts))
               (or (null (second parts))
                   (and component (not (ui:component-internal-p component)))))
      (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
      (sb-ext:string-to-octets (ui:specimen-html :component component) :external-format :utf-8))))

(defun split-path (path)
  (remove "" (cl-ppcre:split "/" path) :test #'string=))

(defmethod tun.http:dispatch-web ((acceptor tun.http:tun-acceptor) method path)
  (let ((*web-app* (tun.http:acceptor-application acceptor))
        (*reference-labels* nil))
    (with-application (*web-app*)
      (multiple-value-bind (actor credential) (web-actor)
        (let ((*actor* actor)
              (*credential* credential)
              (parts (split-path path))
              (resource (find path *resources* :key #'resource-path :test #'string=))
              (detail (find-if (lambda (r) (and (resource-detail-screen r)
                                                (string= (resource-path r) (format nil "/~a" (first (split-path path))))))
                               *resources*)))
          (cond ((and (eq method :post) (cross-origin-post-p))
                 (respond 403 "Avvist"
                          (list (ui:alert (:variant :destructive :title "Skjemaet ble avvist")
                                          "Skjemaet kom fra et annet nettsted og ble avvist."))))
                ((and (eq method :get) (equal (first parts) "assets"))
                 (or (serve-asset path) (serve-icon path)))
                ((and (eq method :get) (web-app-path-p path))
                 (serve-web-app path))
                ((push-path-p path) (serve-push method path))
                ((and (eq method :get) (stale-assets-p))
                 (setf (hunchentoot:header-out "HX-Redirect") (hunchentoot:request-uri*))
                 "")
                ((and (eq method :get) (equal (first parts) "ui")) (serve-specimen parts))
                ((dispatch-public-page method parts))
                ((dispatch-staff-page method parts))
                ((string= path "/") (see-other (home-path)))
                ;; Logging in and out, and the first admin: access.lisp.
                ((string= path "/login") (handle-login method))
                ((string= path "/logout") (handle-logout method))
                ((and (= 2 (length parts)) (string= (first parts) "setup"))
                 (handle-setup method (second parts)))
                ((and (<= 2 (length parts) 3) (string= (first parts) "auth"))
                 (handle-sign-in method (second parts) (third parts)))
                ((string= path "/login-info") (or (require-login) (see-other (home-path))))
                (resource (handle-resource resource method))
                ((and detail (= 2 (length parts)) (eq method :get))
                 (or (require-login) (detail-page detail (second parts))))
                ((and detail (= 3 (length parts)) (eq method :post))
                 (or (require-login) (handle-record-action detail (second parts) (third parts))))
                (t nil)))))))

;;; ------------------------------------------------------------------
;;; Settings: admin edits through settings_set, with its audit and masking

(defun setting-value-text (item)
  (let ((value (jget item "value")))
    (cond ((json-null-p value) "Ikke satt")
          ((stringp value) value)
          (t (to-json-string value)))))

(defun setting-control (item id)
  "The control for a new value of the setting ITEM: yes and no for a bool, a
number for an int, a password field for a secret, else text."
  (let ((type (jget item "type"))
        (value (jget item "value")))
    (cond ((equal type "bool")
           (ui:select (:label "Ny verdi" :name "value" :id id
                              :options '(("true" "Ja") ("false" "Nei"))
                              :selected (if (eq value t) "true" "false"))))
          ((jget item "secret")
           (ui:text-input (:label "Ny hemmelighet" :name "value" :id id :type :password
                                  :autocomplete "new-password"
                                  :hint "Den gamle vises aldri. Feltet er tomt med vilje.")))
          ((equal type "int")
           (ui:text-input (:label "Ny verdi" :name "value" :id id :type :number :width 10
                                  :inputmode "numeric"
                                  :value (if (integerp value) (princ-to-string value) nil))))
          (t
           (ui:text-input (:label "Ny verdi" :name "value" :id id
                                  :type (if (member type '("url" "email") :test #'equal)
                                            (intern (string-upcase type) :keyword)
                                            :text)
                                  :value (if (stringp value) value nil)
                                  :hint (when (member type '("url" "email" "actor") :test #'equal)
                                          "Skriv null for å fjerne verdien.")))))))

(defun setting-card (item)
  "A setting: its key, what it is for, its value now and the form that changes
it; for one read from the environment, the variable instead of the form."
  (let* ((key (jget item "key"))
         (env (jget item "env"))
         (now (ui:summary-list (:rows (list* (list "Nå" (setting-value-text item))
                                             (when env
                                               (list (list "Leses fra" (format nil "miljøvariabelen ~a"
                                                                               env)))))))))
    (ui:card (:title key :description (jget item "description") :heading-level 2
                     :action (ui:badge (:variant :outline) (jget item "type")))
             (if env
                 now
                 (ui:stack (:gap :lg)
                           now
                           `(:form (:@ :method "post" :action "/settings" :novalidate t)
                                   (:input (:@ :type "hidden" :name "key" :value ,key))
                                   ,(ui:stack (:gap :md)
                                              (setting-control item (format nil "setting-~a"
                                                                            (substitute #\- #\. key)))
                                              (ui:cluster ()
                                                          (ui:button (:type "submit" :variant :outline)
                                                                     "Lagre")))))))))

(defun staff-settings-page (method parts form query)
  (declare (ignore parts query))
  (let ((saved
         (when (eq method :post)
           (let* ((key (jget form "key"))
                  (item (find key (coerce (jget (call-tool "settings_list" (jobj)) "items") 'list)
                              :key (lambda (s) (jget s "key")) :test #'equal))
                  (raw (jget form "value"))
                  (value (if (or (member (jget item "type") '("int" "bool") :test #'equal)
                                 (and (not (member (jget item "type") '("string" "secret")
                                                   :test #'equal))
                                      (equal raw "null")))
                             (handler-case (parse-json raw)
                               (error () (fail :invalid-input "Ugyldig innstillingsverdi")))
                             raw)))
             (call-tool "settings_set" (jobj "key" key "value" value))
             key))))
    (values 200 "Innstillinger"
            (list (when saved (ui:flash () (format nil "Innstillingen ~a er lagret." saved)))
                  (apply #'ui:grid* (list :min :md)
                         (map 'list #'setting-card
                              (jget (call-tool "settings_list" (jobj)) "items")))))))

(register-staff-page "settings" #'staff-settings-page :policy :admin :title "Innstillinger"
                     :icon :settings :group :system)
