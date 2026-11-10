;;;; graph.lisp -- /graph: a project's steps as the factory's dashboard shows
;;;; them, with where agents work and the items tied to each, and a graph of
;;;; 48 steps, both drawn by GRAPH (spec/ui.md 6.3).

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
                      (ui:card (:title (tr "48 steps"))
                        (ui:graph (:id "large" :label (tr "Eight strands")
                                   :nodes (large-graph-nodes)
                                   :edges (edges-of (large-graph-edges))))))))))
