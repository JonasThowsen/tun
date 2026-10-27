;;;; files/package.lisp -- TUN.FILES: files attached to records (spec/files.md).
;;;;
;;;; formats.lisp decides what Tun takes of a file: its type by its bytes,
;;;; its structure walked to its end, its metadata taken out.  multipart.lisp
;;;; reads a page's multipart/form-data post, in memory and within bounds.
;;;; attachments.lisp has the attachment records, the FILES type's input,
;;;; ATTACH-FILES, the tools, the deletion of a record's files and the sweep.

(defpackage #:tun.files
  (:use #:cl #:tun.core)
  (:import-from #:tun.jobs #:define-job #:define-schedule)
  (:export
   ;; formats.lisp
   #:file-refused #:file-refused-message #:examine-file #:file-type #:content-type-of
   #:stored-filename #:base64-octets #:control-character-p
   #:+most-file-octets+ #:+most-call-octets+ #:+most-side+ #:+most-pixels+
   #:+most-given-name+ #:+most-stored-name+
   ;; multipart.lisp
   #:parse-multipart #:multipart-boundary #:multipart-refused #:multipart-refused-status
   #:multipart-refused-message #:+most-parts+ #:+most-file-parts+ #:+most-part-header-octets+
   #:+most-text-part-octets+ #:+most-text-octets+
   ;; attachments.lisp
   #:attachment #:attachment-entity #:attachment-record-id #:attachment-filename
   #:attachment-content-type #:attachment-size #:attachment-width #:attachment-height
   #:attachment-sha256 #:attachment-created-at #:attachment-created-by #:attachment-account
   #:attachment-json #:upload #:upload-filename #:upload-content-type #:upload-octets
   #:upload-width #:upload-height #:*uploads* #:register-upload #:upload-handle-size
   #:*set-aside* #:set-aside-file-data #:set-aside-p #:+set-aside-octets+
   #:attach-files #:attachments-of #:record-attachments #:servable-attachment #:attachment-content-part
   #:+content-part-octets+ #:sweep-attachments #:attachments-sweep
   #:attachments-add #:attachments-list #:attachments-remove
   #:files-parameter-p #:operation-takes-files-p))
