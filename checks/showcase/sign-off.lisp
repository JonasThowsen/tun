;;;; sign-off.lisp -- a single-page screen of the showcase's own
;;;; (spec/typescript.md 4): a person signs off with a note, through an
;;;; operation only a person signed in on the page may call, from a screen
;;;; in TypeScript that calls it through its generated module (screen/).

(in-package #:showcase)

(define-entity sign-off (:label "Sign-off" :id-prefix "sof" :table "sign_offs")
  ((note :type (string :min 1 :max 200) :required t :label "Note")
   (signed-by :type (string :max 200) :input nil :label "Signed by")
   (credential :type (string :max 20) :input nil :label "Signed in with")))

(define-operation sign-offs-create ((:draft sign-off))
    (:entity sign-off :kind :create :policy :employee :session-only t :returns sign-off
             :title "Sign off"
             :description "Signs off with a note, as the person signed in on the page: never with an
access token.")
  (setf (sign-off-signed-by sign-off) (actor-string *actor*)
        (sign-off-credential sign-off) (string-downcase (symbol-name (credential-kind))))
  (insert sign-off))

(define-operation sign-offs-list ()
    (:entity sign-off :kind :read :policy :employee :returns (:page sign-off)
             :title "Sign-offs" :description "The latest sign-offs, newest first.")
  (let* ((limit 20)
         (found (select 'sign-off :order-by '(("seq" :desc)) :limit (1+ limit)))
         (shown (subseq found 0 (min limit (length found)))))
    (jobj "items" (jarr (mapcar #'entity->json shown))
          "returned" (length shown)
          "has_more" (> (length found) limit))))

(define-single-page sign-off-screen ("sign-off" :title "Sign off" :icon :circle-check
                                                :policy :employee :navigation nil)
  :files ("showcase" "screen/public/"))
