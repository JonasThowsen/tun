;;;; cli/typescript.lisp -- tun typescript FOLDER (spec/cli.md 5.1,
;;;; spec/typescript.md 2): load the client as tun preview does and write the
;;;; TypeScript module its registry gives into FOLDER.

(in-package #:tun.cli)

(declaim (optimize (safety 3) (debug 2)))

(defun typescript-forms (client folder)
  "The forms that load CLIENT and write its module into FOLDER, a directory's
name, saying what it wrote on a line of its own."
  (list (lisp-form "(let ((*compile-verbose* nil) (*load-verbose* nil)) (handler-bind ((warning #'muffle-warning)) (asdf:load-system ~s)))"
                   client)
        (lisp-form "(multiple-value-bind (path operations exact) (uiop:symbol-call \"TUN.CORE\" \"WRITE-TYPESCRIPT-MODULE\" ~s ~s) (format t \"~~&tun typescript: wrote ~~a: ~~d operations, ~~d with an exact output~~%\" (namestring path) operations exact))"
                   folder client)))

(defun write-typescript (folder &key (directory "."))
  "Write FOLDER/api.ts, the TypeScript module of the client in DIRECTORY
(spec/typescript.md 2), from a process that loads the client as tun
preview does.  Returns the line saying what it wrote."
  (let ((directory (absolute-directory directory))
        (folder (namestring (absolute-directory folder))))
    (unless (and (uiop:directory-exists-p directory)
                 (directory (merge-pathnames "*.asd" directory)))
      (refuse "~a holds no client: no .asd at its top" (namestring directory)))
    (let* ((client (client-name directory))
           (command (client-lisp-command client directory (uiop:getenv "TUN_WORKTREE")
                                         (typescript-forms client folder)
                                         :fasl "typescript-fasl")))
      (multiple-value-bind (output error-output status)
          (uiop:run-program command :output :string :error-output :string :ignore-error-status t)
        (let ((line (find-if (lambda (line) (eql 0 (search "tun typescript: wrote" line)))
                             (uiop:split-string output :separator '(#\Newline)))))
          (unless (and (eql status 0) line)
            (fail-step "the client ~a did not load, or wrote no module (exit ~a):~%~{~a~%~}"
                       client status
                       (last (remove "" (uiop:split-string (concatenate 'string output error-output)
                                                           :separator '(#\Newline))
                                     :test #'string=)
                             20)))
          (subseq line (length "tun typescript: ")))))))

(defun typescript-command (arguments &key dir)
  "tun typescript FOLDER [--dir DIR] (spec/cli.md 5.1)."
  (cond ((null arguments) (refuse "tun typescript needs the FOLDER to write api.ts into"))
        ((rest arguments) (refuse "tun typescript takes one FOLDER, not ~{~a~^ ~}" arguments)))
  (format t "~&~a~%" (write-typescript (first arguments) :directory (or dir "."))))
