;;;; Summarise Mallet's JSON findings without loading the inspected source.

(load (merge-pathnames "setup.lisp" *load-truename*))
(tun-build:load-quietly "com.inuoe.jzon")

(defpackage #:tun-lint-report
  (:use #:cl))
(in-package #:tun-lint-report)

(defun sorted-keys (table)
  (sort (loop for key being the hash-keys of table collect key) #'string<))

(defun count-rules (violations)
  (let ((counts (make-hash-table :test #'equal)))
    (loop for violation across violations
          do (incf (gethash (gethash "rule" violation) counts 0)))
    counts))

(defun markdown-text (text)
  ;; Paths can contain table delimiters or line breaks.
  (with-output-to-string (out)
    (loop for character across text
          do (case character
               (#\| (write-string "&#124;" out))
               (#\< (write-string "&lt;" out))
               (#\& (write-string "&amp;" out))
               ((#\Newline #\Return) (write-string " " out))
               (otherwise (write-char character out))))))

(defun write-baseline (findings stream version revision)
  (let ((total (loop for file across findings sum (length (gethash "violations" file)))))
    (format stream "# Lint baseline~%~%")
    (format stream "Tool: ~a. Parent Git revision: `~a`.~%~%" version revision)
    (format stream "Regenerate with `bin/lint --baseline`. Full locations: `.build/lint.json`.~%~%")
    (format stream "Advisory findings: ~d in ~d files.~%~%" total (length findings))
    (format stream "| File | Findings | Rules |~%|---|---:|---|~%")
    (loop for file across (sort findings #'string< :key (lambda (file) (gethash "file" file)))
          for violations = (gethash "violations" file)
          for counts = (count-rules violations)
          do (format stream "| ~a | ~d | ~{~a~^, ~} |~%"
                     (markdown-text (gethash "file" file))
                     (length violations)
                     (loop for rule in (sorted-keys counts)
                           collect (format nil "~a (~d)" rule (gethash rule counts)))))))

(destructuring-bind (json report version revision) (uiop:command-line-arguments)
  (let ((findings (com.inuoe.jzon:parse (uiop:read-file-string json))))
    (with-open-file (stream report :direction :output :if-exists :supersede
                            :if-does-not-exist :create :external-format :utf-8)
      (write-baseline findings stream version revision))))
