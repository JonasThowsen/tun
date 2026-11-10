;;;; graph.lisp -- /graph: a project's steps as the factory's dashboard shows
;;;; them, with where agents work and the items tied to each, the shape of a
;;;; real plan of 30 components, and a graph of 48 steps, all drawn by GRAPH
;;;; (spec/ui.md 6.3).

(in-package #:showcase)

(defparameter +pilot-steps+
  '(("brief" "Brief and estimate" :done "8 Nov")
    ("model" "Bookings and stock" :done "Factory 2")
    ("catalog" "Rental catalogue" :done)
    ("calendar" "Booking calendar" :active "Factory 3" ("Claude i tun" :agent) ("#12" :ref))
    ("payments" "Card payments" :waiting "Stripe" ("1 question" :ref :warning))
    ("mail" "Order confirmations" :planned)
    ("review" "Review the calendar" :active nil ("Reviewer" :agent))
    ("fix" "Fix the double bookings" :failed nil ("#15" :ref :destructive))
    ("staging" "Deploy to staging" :blocked nil ("#14" :ref :destructive))
    ("demo" "Demo for the customer" :planned)
    ("launch" "Launch on moatless.store" :planned)
    ("docs" "Customer guide" :planned "No dependencies"
            ("Claude i tunworks, the orchestrator's builder" :agent))
    ("photos" "Product photos" :active "Many hands" ("Kari" :agent) ("Ola" :agent)
              ("#21" :ref) ("#22" :ref) ("#23" :ref) ("2 questions" :ref :warning)))
  "The pilot's steps: id, title, state, the line under it, and badges as
(TEXT KIND [TONE]).")

(defparameter +pilot-edges+
  '(("brief" "model") ("model" "catalog") ("model" "calendar") ("model" "payments")
    ("catalog" "mail") ("calendar" "review") ("review" "fix") ("fix" "review")
    ("review" "staging") ("payments" "staging") ("mail" "staging") ("staging" "demo")
    ("demo" "launch") ("catalog" "photos"))
  "What each step comes after; review and fix wait on each other.")

(defun pilot-nodes ()
  (loop for (id title state meta . badges) in +pilot-steps+
        collect (list :id id :title title :state state :meta meta
                      :href (format nil "/graph/~a" id)
                      :badges (loop for (text kind tone) in badges
                                    collect (list :text text :kind kind :tone tone
                                                  :href (when (eq kind :ref) "/graph"))))))

(defun edges-of (pairs)
  (mapcar (lambda (pair) (list :from (first pair) :to (second pair))) pairs))

(defun large-graph-nodes ()
  "48 steps in eight strands of six, each strand a chain."
  (loop for i below 48
        collect (list :id (format nil "s~d" i) :title (format nil "Step ~d" (1+ i))
                      :meta (format nil "Strand ~d" (1+ (floor i 6)))
                      :state (nth (mod (* i 7) 6) '(:done :active :planned :waiting :planned :done))
                      :badges (when (= 5 (mod i 9))
                                (list (list :text "Agent" :kind :agent))))))

(defun large-graph-edges ()
  "Each strand a chain, and every third step also before a step of the next
strand, two further on."
  (append (loop for i below 48
                unless (= 5 (mod i 6))
                  collect (list (format nil "s~d" i) (format nil "s~d" (1+ i))))
          (loop for i below 40 by 3
                collect (list (format nil "s~d" i) (format nil "s~d" (+ i 8))))))

(defparameter +erp-plan+
  '(("module-layout" "Module layout and build path" :infra :done ())
    ("customers-update" "Updating customers in Tun" :module :done ())
    ("company" "Company profile and settings" :module :done ("module-layout"))
    ("pricing" "Prices, discounts and VAT rules" :module :done ("company"))
    ("customers" "Customers and their contacts" :module :done ("company" "customers-update"))
    ("catalogue" "Product and rental catalogue" :module :done ("company"))
    ("staff" "Staff, roles and working hours" :module :active ("company"))
    ("messages" "Messages to customers by mail and SMS" :module :done ("customers"))
    ("accounting-port" "Port to the accounting system" :port :waiting ("company"))
    ("orders" "Orders from quote to delivery" :module :active ("customers" "catalogue" "pricing"))
    ("order-lifecycle" "Order states and their transitions" :module :active ("orders"))
    ("stock-ledger" "Stock ledger per warehouse" :module :done ("catalogue"))
    ("quotes" "Quotes the customer can accept online" :slice :planned
     ("order-lifecycle" "messages"))
    ("quote-timers" "Reminders on quotes about to expire" :slice :planned ("quotes"))
    ("inquiries" "Inquiries from the website form" :slice :failed ("orders" "messages"))
    ("stock-reservations" "Stock reserved for confirmed orders" :module :planned
     ("stock-ledger" "order-lifecycle"))
    ("work-orders" "Work orders for the field crew" :module :planned ("order-lifecycle" "staff"))
    ("calendar" "Crew calendar by week and day" :slice :planned ("work-orders"))
    ("invoices" "Invoices from delivered orders" :module :blocked
     ("order-lifecycle" "accounting-port" "messages"))
    ("invoice-status" "Invoice status from the accounting system" :slice :planned ("invoices"))
    ("work-time" "Hours worked against work orders" :slice :planned
     ("work-orders" "stock-ledger" "invoices"))
    ("payments" "Payments by card and invoice" :port :planned
     ("order-lifecycle" "messages" "accounting-port"))
    ("front-page" "Front page with today's work" :slice :planned
     ("quote-timers" "invoice-status" "stock-reservations" "work-orders" "inquiries"))
    ("reports" "Monthly sales and margin reports" :slice :planned ("invoice-status"))
    ("setup-wizard" "First-run setup for a new company" :slice :active
     ("company" "catalogue" "messages"))
    ("rental-bookings" "Rental bookings by date range" :module :planned
     ("order-lifecycle" "catalogue"))
    ("rental-packing" "Packing lists for rental pickups" :slice :planned
     ("rental-bookings" "stock-reservations"))
    ("rental-handover" "Handover and return of rented items" :slice :planned
     ("rental-bookings" "invoices"))
    ("demo-companies" "Demo companies with realistic data" :slice :planned
     ("front-page" "reports" "setup-wizard" "payments" "calendar" "work-time" "rental-packing"
      "rental-handover"))
    ("parity-map" "Parity map against the old system" :infra :planned ("demo-companies")))
  "The shape of a real 30-component plan (Tun ERP's): key, title, kind,
state and the components it depends on; the titles are made up.")

(defparameter +erp-plan-badges+
  '(("staff" ("Builder 1" :agent))
    ("orders" ("Builder 2" :agent) ("#41" :ref))
    ("order-lifecycle" ("Reviewer" :agent) ("#42" :ref) ("#43" :ref))
    ("setup-wizard" ("Builder 3, the one on the long name" :agent))
    ("accounting-port" ("1 question" :ref :warning) ("Planner" :agent) ("#40" :ref))
    ("inquiries" ("#44" :ref :destructive))
    ("invoices" ("Waits on the port" :ref :warning)))
  "Who works where in the plan, and the items on its components.")

(defun erp-plan-nodes ()
  (loop for (key title kind state) in +erp-plan+
        collect (list :id key :title title :state state
                      :meta (format nil "~:(~a~) · ~a h" kind (1+ (mod (length title) 4)))
                      :href (format nil "/graph/~a" key)
                      :badges (loop for (text badge-kind tone)
                                      in (rest (assoc key +erp-plan-badges+ :test #'string=))
                                    collect (list :text text :kind badge-kind :tone tone
                                                  :href (when (eq badge-kind :ref) "/graph"))))))

(defun erp-plan-edges ()
  (loop for (key nil nil nil requires) in +erp-plan+
        append (mapcar (lambda (required) (list :from required :to key)) requires)))

(define-page graph-page ("graph" :title "Graph" :icon :list-checks :policy :employee
                                 :width :wide)
    (method path form query)
  (declare (ignore form query))
  (if (or (eq method :post) (rest path))
      (values 404 (tr "Graph") (list (ui:alert (:variant :warning
                                                :title (tr "Page not found")))))
      (values 200 (tr "Graph")
              (list (ui:stack (:gap :lg)
                      (ui:card (:title (tr "The pilot"))
                        (ui:graph (:id "pilot" :label (tr "Event rental")
                                   :nodes (pilot-nodes) :edges (edges-of +pilot-edges+))))
                      (ui:card (:title (tr "A plan of 30 components"))
                        (ui:graph (:id "plan" :label (tr "Tun ERP's plan")
                                   :nodes (erp-plan-nodes) :edges (erp-plan-edges))))
                      (ui:card (:title (tr "48 steps"))
                        (ui:graph (:id "large" :label (tr "Eight strands")
                                   :nodes (large-graph-nodes)
                                   :edges (edges-of (large-graph-edges))))))))))
