;;;; files/attachments.lisp -- files attached to records (spec/files.md 1,
;;;; 4, 5): the attachment records and their content, the FILES type's
;;;; input, ATTACH-FILES, the tools, and the deletion of a record's files.
;;;;
;;;; A file belongs to one record, named by its entity's JSON name and its
;;;; id, of an entity defined with :ATTACHMENTS.  Its metadata is an
;;;; internal record; its content is kept by the store apart from it
;;;; (STORE-WRITE-CONTENT), written in the same transaction.  Who may see a
;;;; file is who may see its record: every read here fetches the record as
;;;; the caller, so the entity's record policy decides.

(in-package #:tun.files)

(declaim (optimize (safety 3) (debug 2)))

(define-entity attachment (:label "Vedlegg" :id-prefix "fil" :table "attachments" :internal t
                                  :indexes (("entity" "record_id")))
  ((entity :type (string :min 1 :max 100) :required t :input nil :label "Entitet"
           :description "The JSON name of the record's entity.")
   (record-id :type (string :min 1 :max 64) :required t :input nil :label "Post")
   (filename :type (string :min 1 :max 255) :required t :input nil :label "Filnavn")
   (content-type :type (string :min 1 :max 40) :required t :input nil :label "Type")
   (size :type integer :required t :input nil :label "Størrelse")
   (width :type integer :input nil :label "Bredde")
   (height :type integer :input nil :label "Høyde")
   (sha256 :type (string :max 64) :required t :input nil :label "SHA-256")
   (created-at :type timestamp :input nil :label "Lagt ved")
   (created-by :type (string :max 200) :input nil :label "Lagt ved av"
               :description "The actor that attached it, as the audit records it.")
   (account :type (string :max 64) :input nil :label "Konto"
            :description "The name of the account that attached it, which may remove it;
NIL for the system.")))

(defun new-attachment-id ()
  "An attachment's id: fil_ and 26 random characters, 130 bits (spec/files.md 5.1)."
  (concatenate 'string "fil_" (random-token-string 26)))

;;; ------------------------------------------------------------------
;;; The files a call carries

(defstruct upload
  "A file as a call gives it, checked and with its metadata taken out."
  filename content-type octets width height sha256 path
  (given 0 :type integer))

(defvar *uploads* nil
  "While a page's multipart post is answered: the files it carried, a hash
table from each handle to (FILENAME . OCTETS).  NIL elsewhere, so a handle
means nothing to a call over MCP or /api (spec/files.md 6.2).")

(defun register-upload (filename octets)
  "A new handle for the file FILENAME with OCTETS, in *UPLOADS*."
  (let ((handle (concatenate 'string "upl_" (random-token-string 26))))
    (setf (gethash handle *uploads*) (cons filename octets))
    handle))

;;; A file's data sent in a JSON body is set aside before the body is parsed
;;; (spec/files.md 4.3): each string longer than +SET-ASIDE-OCTETS+ is decoded
;;; from base64 straight out of the body's octets and replaced by a short
;;; placeholder, so its text is never made.  The call's FILES input finds
;;; the octets by the placeholder.

(defparameter +set-aside-octets+ (* 1024 1024)
  "A string in a body that may carry files longer than this, in the body's
octets between its quotes, is set aside as a file's data.")

(defvar *set-aside* nil
  "While a call whose body may carry files is answered: a hash table from
each placeholder SET-ASIDE-FILE-DATA put in the body to the octets the
string it replaced encodes, or the message why they cannot be read.")

(defun json-strings-over (octets most)
  "Where the strings of OCTETS, JSON text, longer than MOST octets between
their quotes are: (START . END) of what is between, in order."
  (declare (type (simple-array (unsigned-byte 8) (*)) octets))
  (let ((found '()) (in-string nil) (escaped nil) (start 0))
    (loop for i from 0 below (length octets)
          for octet = (aref octets i)
          do (cond ((not in-string)
                    (when (= octet 34) (setf in-string t start (1+ i))))
                   (escaped (setf escaped nil))
                   ((= octet 92) (setf escaped t))
                   ((= octet 34)
                    (setf in-string nil)
                    (when (> (- i start) most) (push (cons start i) found)))))
    (nreverse found)))

(defun set-aside-file-data (octets)
  "OCTETS, a JSON body that may carry files, with each string longer than
+SET-ASIDE-OCTETS+ replaced by a placeholder, and the octets it encodes in
base64, or why it does not, in *SET-ASIDE* under it.  OCTETS themselves
when no string is that long."
  (let* ((octets (coerce octets '(simple-array (unsigned-byte 8) (*))))
         (long (json-strings-over octets +set-aside-octets+)))
    (if (null long)
        octets
        (let* ((placeholders (loop for i from 0 below (length long)
                                   collect (format nil "\\u0000data:~d" i)))
               (set-aside (reduce #'+ long :key (lambda (span) (- (cdr span) (car span)))))
               (rest (make-array (+ (- (length octets) set-aside)
                                    (reduce #'+ placeholders :key #'length))
                                 :element-type '(unsigned-byte 8)))
               (from 0) (at 0))
          (loop for (start . end) in long
                for placeholder in placeholders
                for i from 0
                do (replace rest octets :start1 at :start2 from :end2 start)
                   (incf at (- start from))
                   (loop for char across placeholder
                         do (setf (aref rest at) (char-code char)) (incf at))
                   (setf from end
                         (gethash (format nil "~cdata:~d" #\Nul i) *set-aside*)
                         (handler-case (json-base64-octets octets start end)
                           (file-refused (refusal) (file-refused-message refusal)))))
          (replace rest octets :start1 at :start2 from)
          rest))))

(defun set-aside-p (string)
  "True when STRING is a placeholder for a file's data set aside."
  (and *set-aside* (plusp (length string)) (char= (char string 0) #\Nul)
       (nth-value 1 (gethash string *set-aside*))))

(defun upload-handle-size (handle)
  "The octets of the file HANDLE names in this request, or NIL."
  (let ((file (and *uploads* (stringp handle) (gethash handle *uploads*))))
    (and file (length (cdr file)))))

(defun files-parameter-p (parameter)
  "True when PARAMETER, an operation's, carries files."
  (files-type-p (parameter-type parameter)))

(defun operation-takes-files-p (op)
  "True when OP has a parameter of type FILES."
  (and (some #'files-parameter-p (operation-parameters op)) t))

(defmethod type-json-schema ((type files-type))
  (jobj "type" "array" "maxItems" (files-max type)
        "items" (jobj "type" "object"
                      "properties"
                      (jobj "filename" (jobj "type" "string" "maxLength" +most-given-name+
                                             "description" "Filnavnet, som skjermbilde.png.")
                            "data" (jobj "type" "string" "contentEncoding" "base64"
                                         "description" "Filens innhold i base64. Tillatt er PNG,
JPEG, WebP, GIF og PDF, opptil 10 MB per fil. En adresse (url) tas ikke imot."))
                      "required" (jarr '("filename" "data"))
                      "additionalProperties" nil)))

(defun file-content (item path name)
  "The octets ITEM's data or upload holds, or NIL with an input error at PATH
about the file NAME."
  (multiple-value-bind (data has-data) (jget item "data")
    (multiple-value-bind (handle has-handle) (jget item "upload")
      (cond ((and has-data has-handle)
             (file-input-error path name "Send enten data eller upload, ikke begge."))
            ((and has-data (stringp data) (set-aside-p data))
             (let ((entry (gethash data *set-aside*)))
               (if (stringp entry) (refuse-file "~a" entry) entry)))
            ((and has-data (stringp data)) (base64-octets data))
            (has-handle
             (let ((file (and *uploads* (stringp handle) (gethash handle *uploads*))))
               (if file
                   (cdr file)
                   (file-input-error path name "Filen må sendes som base64 i data."))))
            (t (file-input-error path name "Innholdet må sendes som base64 i data."))))))

(defun file-input-error (path name control &rest arguments)
  "An input error at PATH about the file NAME: its message starts with the
name, so a person sees which of several files it is about."
  (let ((message (apply #'format nil control arguments)))
    (if (and (stringp name) (plusp (length (string-trim " " name))))
        (input-error path "«~a»: ~a"
                     (string-trim " " (remove-if #'control-character-p name)) message)
        (input-error path "~a" message))))

(defun checked-upload (name octets path)
  "OCTETS, the file NAME, as an UPLOAD, or NIL with an input error at PATH."
  (cond ((zerop (length octets)) (file-input-error path name "Filen er tom."))
        ((> (length octets) +most-file-octets+)
         (file-input-error path name "Filen er større enn 10 MB."))
        (t (handler-case
               (multiple-value-bind (stored type width height) (examine-file octets)
                 (make-upload :filename (stored-filename name type)
                              :content-type (content-type-of type)
                              :octets stored :width width :height height
                              :sha256 (ironclad:byte-array-to-hex-string
                                       (ironclad:digest-sequence :sha256 stored))
                              :path path :given (length octets)))
             (file-refused (refusal)
               (file-input-error path name "~a" (file-refused-message refusal)))))))

(defun coerce-file (item path)
  "ITEM, one file of a FILES value, as an UPLOAD; NIL with an input error at
PATH when Tun does not take it."
  (let ((unknown (and (hash-table-p item)
                      (set-difference (jkeys item) '("filename" "data" "upload")
                                      :test #'string=)))
        (name (and (hash-table-p item) (jget item "filename" ""))))
    (cond ((not (hash-table-p item))
           (input-error path "må være et objekt med filename og data"))
          ((nth-value 1 (jget item "url"))
           (input-error path "Tun henter ikke filer fra en adresse. Send innholdet som base64 i ~
                              data."))
          (unknown (input-error path "har ukjente felt: ~{~a~^, ~}~@[ og ~d til~]"
                                (mapcar #'shown-name (subseq unknown 0 (min 5 (length unknown))))
                                (and (> (length unknown) 5) (- (length unknown) 5))))
          ((not (stringp name)) (input-error path "filename må være en tekst"))
          ((> (length name) +most-given-name+)
           (input-error path "Filnavnet kan ikke være lengre enn 255 tegn."))
          (t (let ((octets (handler-case (file-content item path name)
                             (file-refused (refusal)
                               (file-input-error path name "~a" (file-refused-message refusal))))))
               (and octets (checked-upload name octets path)))))))

(defmethod coerce-input ((type files-type) value path)
  (cond ((not (json-array-p value)) (input-error path "må være en liste av filer"))
        ((> (length value) (files-max type))
         (input-error path "Du kan legge ved høyst ~d filer om gangen." (files-max type)))
        (t (let ((uploads (loop for item across value
                                for i from 0
                                for upload = (coerce-file item (format nil "~a[~d]" path i))
                                when upload collect upload)))
             ;; The files as they were given, before anything was taken out.
             (when (> (reduce #'+ uploads :key #'upload-given) +most-call-octets+)
               (input-error path "Filene kan ikke være større enn 25 MB til sammen."))
             uploads))))

(defmethod type->json ((type files-type) value)
  (jarr (mapcar (lambda (upload)
                  (jobj "filename" (upload-filename upload)
                        "bytes" (length (upload-octets upload))))
                value)))

(defun recorded-file (item)
  "What a request's record keeps of ITEM, one file as a call gave it: its
name, at most 255 characters, and its size (spec/files.md 4.1)."
  (if (hash-table-p item)
      (let ((name (jget item "filename"))
            (data (jget item "data"))
            (handle (jget item "upload")))
        (jobj "filename" (if (stringp name)
                             (subseq name 0 (min (length name) +most-given-name+))
                             :null)
              "bytes" (cond ((and (stringp data) (set-aside-p data))
                             (let ((entry (gethash data *set-aside*)))
                               (if (stringp entry) :null (length entry))))
                            ((stringp data) (base64-length data))
                            ((upload-handle-size handle))
                            (t :null))))
      :null))

(defmethod recorded-value ((type files-type) value)
  (if (json-array-p value)
      (jarr (map 'list #'recorded-file value))
      :null))

;;; ------------------------------------------------------------------
;;; Attachment records

(defun attachment-json (attachment)
  "ATTACHMENT as the tools give it (spec/files.md 4.2)."
  (flet ((or-null (value) (if (null value) :null value)))
    (jobj "id" (entity-id attachment)
          "entity" (attachment-entity attachment)
          "record_id" (attachment-record-id attachment)
          "filename" (attachment-filename attachment)
          "content_type" (attachment-content-type attachment)
          "size" (attachment-size attachment)
          "width" (or-null (attachment-width attachment))
          "height" (or-null (attachment-height attachment))
          "created_at" (if (attachment-created-at attachment)
                           (format-rfc3339 (attachment-created-at attachment))
                           :null)
          "created_by" (or-null (attachment-created-by attachment))
          "url" (absolute-url (format nil "/files/~a" (entity-id attachment))))))

(defun record-attachments (entity-name record-id)
  "The attachments of the record RECORD-ID of the entity ENTITY-NAME, a JSON
name, in the order they were added."
  (select 'attachment :where `(:and (:= "entity" ,entity-name) (:= "record_id" ,record-id))
          :order-by '(("seq" :asc))))

(defun taking-class (entity-name)
  "The entity class ENTITY-NAME, a JSON name, names when it takes files, else NIL."
  (let ((class (and (stringp entity-name) (find-entity-by-json-name entity-name))))
    (and class (not (entity-embedded-p class)) (entity-attachments class) class)))

(defun visible-record (class id)
  "The record ID of CLASS when the caller may see it (spec/files.md 5.2):
its record policy admits it and the entity is readable by the caller."
  (let ((record (and (stringp id) (fetch (class-name class) id))))
    (and record (entity-readable-p record *actor*) record)))

(defun attach-files (record uploads)
  "Store UPLOADS, the value of a FILES parameter, as attachments of RECORD,
inside the current write, and return them (spec/files.md 4.1).  RECORD is a
stored record of an entity that takes files.  Fails invalid_input when the
record would hold more files than its entity's :MAX allows; then none is
stored."
  (assert-writable)
  (let* ((class (class-of record))
         (option (entity-attachments class)))
    (unless option
      (fail :invalid-input "~a tar ikke imot filer" (entity-label class)))
    (unless (entity-id record)
      (error "ATTACH-FILES needs a stored record; insert ~a first" (entity-json-name class)))
    (when uploads
      (let ((held (length (record-attachments (entity-json-name class) (entity-id record))))
            (most (getf option :max)))
        (when (> (+ held (length uploads)) most)
          (fail-fields (list (cons (let ((path (upload-path (first uploads))))
                                     (subseq path 0 (or (position #\[ path) (length path))))
                                   (format nil "Høyst ~d filer per ~(~a~)."
                                           most (entity-label class)))))))
      (mapcar (lambda (upload) (store-attachment class record upload)) uploads))))

(defun store-attachment (class record upload)
  (let ((attachment (make-instance 'attachment
                                   :entity (entity-json-name class)
                                   :record-id (entity-id record)
                                   :filename (upload-filename upload)
                                   :content-type (upload-content-type upload)
                                   :size (length (upload-octets upload))
                                   :width (upload-width upload)
                                   :height (upload-height upload)
                                   :sha256 (upload-sha256 upload)
                                   :created-at (now)
                                   :created-by (and *actor* (actor-string *actor*))
                                   :account (and *actor* (not (eq (actor-role *actor*) :system))
                                                 (actor-name *actor*)))))
    (setf (entity-id attachment) (new-attachment-id))
    (insert attachment)
    (store-write-content *store* (entity-id attachment) (upload-octets upload))
    attachment))

(defun delete-attachment (attachment)
  (store-delete-content *store* (entity-id attachment))
  (delete-entity attachment))

;;; Deleting a record deletes its files, in the same transaction, whichever
;;; code deleted it (spec/files.md 5.1).
(defmethod store-delete :after ((store store) class-name id)
  (let ((class (find-entity-class class-name nil)))
    (when (and class (entity-attachments class))
      (dolist (attachment (record-attachments (entity-json-name class) id))
        (delete-attachment attachment)))))

;;; ------------------------------------------------------------------
;;; Serving (spec/files.md 5.2, 5.4)

(defparameter +content-part-octets+ (* 1024 1024)
  "The most octets of a file read and sent at once.")

(defun servable-attachment (id)
  "The attachment ID when the caller may see its record, else NIL: an
attachment whose entity the code no longer defines, or that no longer takes
files, is no one's.  Call it in a read transaction."
  (let* ((attachment (and (stringp id) (fetch 'attachment id)))
         (class (and attachment (taking-class (attachment-entity attachment)))))
    (and class (visible-record class (attachment-record-id attachment)) attachment)))

(defun attachment-content-part (id start)
  "Up to +CONTENT-PART-OCTETS+ octets of the content of ID from START, read in
a read transaction of its own; NIL when the file is gone."
  (with-transaction (:read)
    (store-read-content *store* id start +content-part-octets+)))

;;; ------------------------------------------------------------------
;;; The tools (spec/files.md 4.2)

(defun record-class-or-fail (entity)
  (or (taking-class entity)
      (fail-fields (list (cons "entity" (format nil "~a tar ikke imot filer" entity))))))

(defun check-attachment-policy (class)
  "Refuse the caller when the entity's :POLICY needs a role above theirs."
  (let ((policy (getf (entity-attachments class) :policy)))
    (unless (actor-permits-p *actor* policy)
      (reject :forbidden "Filer på ~(~a~) kan bare legges ved og fjernes av en ~
                          administrator" (entity-label class)))))

(define-operation attachments-add ((entity :type (string :min 1 :max 100) :required t
                                           :label "Entitet"
                                           :description "Entiteten posten hører til, som item.")
                                   (record-id :type (string :min 1 :max 64) :required t
                                              :label "Post" :description "Postens id.")
                                   (files :type (files :max 10) :required t :label "Filer"))
    (:entity attachment :kind :update :policy :employee :title "Legg ved filer"
             :description "Legger filer ved en post: skjermbilder, bilder og PDF, sendt som
base64. Høyst 10 filer og 25 MB om gangen.")
  (let* ((class (record-class-or-fail entity))
         (record (or (visible-record class record-id)
                     (record-not-found (class-name class) record-id))))
    (check-attachment-policy class)
    (unless files
      (fail-fields (list (cons "files" "Velg minst én fil å legge ved."))))
    (audit-target (entity-json-name class) record-id)
    (jobj "items" (jarr (mapcar #'attachment-json (attach-files record files))))))

(define-operation attachments-list ((entity :type (string :min 1 :max 100) :required t
                                            :label "Entitet")
                                    (record-id :type (string :min 1 :max 64) :required t
                                               :label "Post"))
    (:entity attachment :kind :read :policy :viewer :title "Filer ved en post"
             :description "Filene som er lagt ved en post, i den rekkefølgen de ble lagt ved.")
  (let* ((class (record-class-or-fail entity))
         (items (progn (or (visible-record class record-id)
                           (record-not-found (class-name class) record-id))
                       (mapcar #'attachment-json
                               (record-attachments (entity-json-name class) record-id)))))
    (jobj "items" (jarr items) "returned" (length items) "has_more" nil)))

(define-operation attachments-remove ((id :type (id attachment) :required t :label "Fil"))
    (:entity attachment :kind :update :policy :employee :title "Fjern en fil"
             :description "Fjerner en fil fra posten den er lagt ved. Den som la den ved, eller
en administrator, kan fjerne den.")
  (let ((attachment (servable-attachment id)))
    (unless attachment
      (fail :not-found "Fant ikke filen ~a" id))
    (let ((class (taking-class (attachment-entity attachment))))
      (check-attachment-policy class)
      (unless (or (actor-permits-p *actor* :admin)
                  (and (attachment-account attachment)
                       (equal (attachment-account attachment) (actor-name *actor*))))
        (reject :forbidden "Bare den som la ved filen, eller en administrator, kan fjerne den"))
      (audit-target (attachment-entity attachment) (attachment-record-id attachment))
      (delete-attachment attachment)
      (jobj "id" id "removed" t))))

;;; ------------------------------------------------------------------
;;; The nightly sweep (spec/files.md 5.1)

(defun sweep-attachments ()
  "Delete, in the current write, the attachments whose record no longer
exists, of entities the running code defines and that take files.  Returns
how many it deleted."
  (let ((deleted 0))
    (dolist (attachment (select 'attachment :order-by '(("seq" :asc))) deleted)
      (let ((class (taking-class (attachment-entity attachment))))
        (when (and class (null (fetch (class-name class) (attachment-record-id attachment))))
          (delete-attachment attachment)
          (incf deleted))))))

(define-job attachments-sweep () (:max-attempts 3)
            "Delete the files whose record is gone (spec/files.md 5.1)."
            (sweep-attachments))

(define-schedule attachments-sweep "30 3 * * *" attachments-sweep)
