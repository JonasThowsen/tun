;;; indent.el --- Tun's Common Lisp indentation hints and batch entry point -*- lexical-binding: t; -*-

(require 'cl-indent)

;; The integer is the number of header arguments before the two-space body.
(dolist (hint '((define-entity . 2)
                (define-operation . 3)
                (define-query . 3)
                (define-page . 3)
                (define-rule . 3)
                (define-computed-field . 4)
                (define-workflow . 3)
                (define-message-template . 3)
                (define-module . 1)
                (define-application . 2)
                (extend-entity . 2)
                (define-setting . 2)
                (with-actor . 1)
                (with-application . 1)
                (with-deadline . 1)
                (with-transaction . 1)
                (with-step . 1)
                (with-request-state . 1)
                (with-backtrace-capture . 1)
                (with-request-record . 1)
                (with-audit-scope . 0)
                (with-constraint-mapping . 0)
                (with-test-app . 1)
                (with-test-server . 1)
                (with-sqlite-app . 1)
                (with-deadline-ms . 1)
                (with-decide-plan-wrapped . 2)
                (with-each-store . 1)
                (with-minimal . 1)
                (with-fjord . 1)
                (with-client . 1)
                (with-communication-templates . 0)
                (with-scratch-modules . 0)
                ;; FiveAM's (test name &body body).
                (test . 1)
                ;; CL-PPCRE's binding and iteration macros.
                (register-groups-bind . 2)
                (do-register-groups . 2)
                (do-matches . 1)
                (do-matches-as-strings . 1)
                (do-scans . 1)
                ;; Design system components that hold other components:
                ;; (NAME (OPTIONS...) CHILD...).
                (alert . 1)
                (badge . 1)
                (button . 1)
                (button-group . 1)
                (card . 1)
                (cluster . 1)
                (empty-state . 1)
                (error-summary . 1)
                (field . 1)
                (fieldset . 1)
                (flash . 1)
                (form-actions . 1)
                (grid . 1)
                (link . 1)
                (section . 1)
                (stack . 1)))
  (put (car hint) 'common-lisp-indent-function (cdr hint)))

(defun tun-indent-mode-setup ()
  "Use Common Lisp indentation without tabs in this Lisp buffer."
  (setq-local lisp-indent-function #'common-lisp-indent-function)
  (setq-local indent-tabs-mode nil))

(defun tun-indent-file (file check)
  "Return non-nil if FILE needs indentation; with CHECK, report without writing."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((original (buffer-string))
          (coding-system-for-write last-coding-system-used))
      (lisp-mode)
      (tun-indent-mode-setup)
      (let ((inhibit-message t))
        (check-parens)
        (indent-region (point-min) (point-max)))
      (unless (equal original (buffer-string))
        (if check
            (princ (concat file "\n"))
          (write-region (point-min) (point-max) file nil 'silent))
        t))))

(defun tun-indent-main ()
  "Indent batch arguments, returning 1 for check differences and 2 for errors."
  (let ((files command-line-args-left)
        (check (equal (getenv "TUN_INDENT_CHECK") "1"))
        (changed nil))
    (setq command-line-args-left nil)
    (condition-case err
        (progn
          (dolist (file files)
            (when (tun-indent-file file check)
              (setq changed t)))
          (kill-emacs (if (and check changed) 1 0)))
      (error
       (princ (format "bin/indent: %s\n" (error-message-string err))
              #'external-debugging-output)
       (kill-emacs 2)))))

(provide 'tun-indent)
;;; indent.el ends here
