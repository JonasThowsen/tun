;;; .dir-locals.el --- Emacs settings for this checkout

;; Indent Lisp the way bin/indent does: Emacs's own indenter with the hints
;; in scripts/indent.el (spec/tooling.md). Emacs asks once before running
;; the eval form; answer ! to remember the answer.
((lisp-mode
  . ((eval . (progn
               (unless (featurep 'tun-indent)
                 (load (expand-file-name
                        "scripts/indent.el"
                        (locate-dominating-file default-directory ".dir-locals.el"))
                       nil t))
               (tun-indent-mode-setup))))))
