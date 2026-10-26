;;;; scripts/ui-specimen.lisp -- write the design system's specimen as
;;;; standalone files (spec/ui.md 7).
;;;; Usage: bin/ui-specimen [DIR]   (default .build/ui/specimen/)

(load (merge-pathnames "setup.lisp" *load-truename*))
(in-package #:tun-build)

(load-quietly "alexandria" "bordeaux-threads" "cl-base64" "cl-ppcre" "closer-mop" "com.inuoe.jzon"
              "hunchentoot" "ironclad" "sqlite" "cl-postgres" "swank")

(let ((*compile-verbose* nil) (*compile-print* nil) (*load-verbose* nil))
  (handler-bind ((warning #'muffle-warning))
    (asdf:load-system "tun")))

(let* ((argument (second sb-ext:*posix-argv*))
       (directory (uiop:ensure-directory-pathname
                   (if argument
                       (merge-pathnames argument (uiop:getcwd))
                       (merge-pathnames ".build/ui/specimen/" *root*))))
       (files (funcall (find-symbol "WRITE-SPECIMEN" "TUN.UI") directory)))
  (format t "~&;; wrote ~d specimen pages to ~a~%" (length files) (namestring directory)))
