;;;; web/search.lisp -- the application's one search over the web and MCP
;;;; (spec/ui.md 6.4): the `search` tool, which asks every contributor
;;;; (SEARCH-RECORDS) and keeps what the caller may open, and the /search
;;;; page, a whole page or the dialog's results, which asks the tool.

(in-package #:tun.web)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; What the actor may open

(defun resource-of-path (first-part)
  "The resource whose path is /FIRST-PART, or NIL."
  (find (format nil "/~a" first-part) *resources* :key #'resource-path :test #'string=))

(defun tool-opens-p (tool actor)
  "True when ACTOR's role may call TOOL, a tool's name."
  (let ((op (and tool (find-operation-by-tool tool))))
    (and op (actor-permits-p actor (operation-policy op)))))

(defun search-href-opens-p (href actor)
  "True when HREF, a result's page, is one ACTOR's role opens (spec/ui.md 6.4):
a path on this site whose first segment is a staff page that admits ACTOR,
or a resource whose list, or for a path under it whose record, ACTOR may
read."
  (when (and (site-path-p href) (not (root-path-p href)))
    (let* ((bare (subseq href 0 (position-if (lambda (c) (member c '(#\? #\#))) href)))
           (parts (split-path bare))
           (page (and parts (gethash (first parts) *staff-pages*)))
           (resource (and parts (resource-of-path (first parts)))))
      (cond (page (and (page-available-p page)
                       (actor-permits-p actor (staff-page-policy page))))
            (resource (tool-opens-p (if (rest parts)
                                        (resource-get-tool resource)
                                        (resource-list-tool resource))
                                    actor))
            (t nil)))))

(defun openable-results (results actor)
  "RESULTS that ACTOR may open; each one dropped is written to the error
output, since it is a mistake of the contributor that made it."
  (remove-if-not (lambda (result)
                   (or (search-href-opens-p (search-result-href result) actor)
                       (progn
                         (format *error-output* "~&;; tun search: dropped the ~a result ~s, ~
                                                 whose page ~s ~a cannot open~%"
                                 (search-result-kind result) (search-result-title result)
                                 (search-result-href result) (actor-string actor))
                         nil)))
                 results))

;;; ------------------------------------------------------------------
;;; The tool

(defun search-result->json (result)
  (jobj "kind" (search-result-kind result)
        "kind_label" (search-result-label result)
        "icon" (string-downcase (symbol-name (search-result-icon result)))
        "title" (search-result-title result)
        "meta" (jarr (search-result-meta result))
        "href" (search-result-href result)
        "score" (search-result-score result)
        "id" (or (search-result-id result) :null)))

(defun application-search-results (text &key kinds (limit 20))
  "What the application's one search finds for TEXT among KINDS (all when
NIL), for *ACTOR*, in the order it shows them and at most LIMIT."
  (let* ((query (make-search-query text :kinds kinds))
         (found (search-records *application* query *actor*))
         (kept (remove-if-not (lambda (result) (search-query-wants-p query
                                                                     (search-result-kind result)))
                              (openable-results found *actor*))))
    (let ((ordered (search-order kept)))
      (subseq ordered 0 (min limit (length ordered))))))

(define-operation application-search
    ((query :type (string :min 2 :max 120) :required t :label "Search"
            :description "What to look for: words, a number, an email or a phone number.")
     (kinds :type (list-of (string :min 1 :max 40) :max-items 20) :label "Kinds"
            :description "Only results of these kinds, such as customer or order; every kind when left out.")
     (limit :type (integer :min 1 :max 20) :default 20 :label "Most results"))
    (:tool "search" :kind :read :policy :viewer :title "Search"
     :description "The application's one search, as a person's Ctrl K finds: every record the modules and the client let it find that the caller may open, best first, at most five of a kind. Each result has its kind, the kind's word, its title, a few facts (meta), its page (href), its score and its id.")
  (jobj "items" (jarr (mapcar #'search-result->json
                              (application-search-results query :kinds kinds :limit limit)))))

;;; ------------------------------------------------------------------
;;; The page

(defun search-items (text)
  "The results for TEXT as SEARCH-RESULTS takes them, from the search tool,
or NIL under two characters."
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) text)))
    (when (>= (length trimmed) 2)
      (multiple-value-bind (json code)
          (web-call "search" (jobj "query" (subseq trimmed 0 (min 120 (length trimmed)))))
        (if code
            (values nil json)
            (map 'list (lambda (item)
                         (list :kind (jget item "kind") :label (jget item "kind_label")
                               :icon (intern (string-upcase (jget item "icon")) :keyword)
                               :title (jget item "title")
                               :meta (coerce (jget item "meta") 'list)
                               :href (jget item "href")))
                 (jget json "items")))))))

(defun search-page-form (text)
  "The search page's own form: the field and «Search»."
  `(:form (:@ :class "tun-search-page-form" :method "get" :action "/search" :role "search")
          ,(ui:stack (:gap :sm)
             (ui:text-input (:label (tr "Search") :label-hidden t :name "q" :type :search
                             :value text :autocomplete "off"))
             (ui:cluster () (ui:button (:type "submit" :icon :search) (tr "Search"))))))

(define-page search-page ("search" :title "Search" :icon :search :policy :viewer
                                   :navigation nil)
    (method path form query)
  (let ((text (or (first (query-values query "q")) "")))
    (cond ((or path (eq method :post) (not (search-contributors-p *web-app*)))
           (values 404 (tr "Search")
                   (list (ui:alert (:variant :warning
                                    :title (tr "There is nothing to search here."))))))
          (t
           (multiple-value-bind (items refused) (search-items text)
             (let ((results (if refused
                                (error-alert refused)
                                (ui:search-results (:query text :items items
                                                    :listbox (htmx-request-p))))))
               (if (htmx-request-p)
                   (values (if refused 422 200) :fragment (list results))
                   (values 200 (tr "Search")
                           (list (ui:stack (:gap :lg) (search-page-form text) results))))))))))
