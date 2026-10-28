;;;; tests/files-tests.lisp -- files attached to records (spec/files.md):
;;;; the :ATTACHMENTS option, the types decided by their bytes, damaged
;;;; files, sizes, what is taken out of a file, names, the FILES type and
;;;; its input, the tools, what a request keeps, fetching a file, storage,
;;;; deleting and the sweep.  The request bounds are in safety-tests.lisp.

(in-package #:tun.tests)

(def-suite files :in core)
(in-suite files)

;;; ------------------------------------------------------------------
;;; Entities that take files

(define-entity file-note (:label "Notat" :id-prefix "fnt" :table "test_file_notes"
                                 :attachments (:max 3))
  ((title :type (string :min 1 :max 200) :required t :label "Tittel")))

(define-operation file-notes-create ((:draft file-note)
                                     (screenshots :type (files :max 3) :label "Skjermbilder"))
    (:entity file-note :kind :create :policy :employee :title "Nytt notat")
  (insert file-note)
  (tun.files:attach-files file-note screenshots)
  file-note)

(define-operation file-notes-get ((id :type (id file-note) :required t))
    (:entity file-note :kind :read :policy :viewer :title "Notat")
  (fetch! 'file-note id))

(define-operation file-notes-explode ((screenshots :type (files :max 3) :label "Skjermbilder"))
    (:entity file-note :kind :update :policy :employee :title "Feiler med filer")
  (error "Noe gikk galt med ~d filer" (length screenshots)))

(define-entity locked-note (:label "Låst notat" :id-prefix "lnt" :table "test_locked_notes"
                                   :attachments (:max 5 :policy :admin))
  ((title :type (string :min 1 :max 200) :required t)))

(define-operation locked-notes-get ((id :type (id locked-note) :required t))
    (:entity locked-note :kind :read :policy :viewer :title "Låst notat")
  (fetch! 'locked-note id))

(define-entity plain-note (:label "Notat uten filer" :id-prefix "pnt" :table "test_plain_notes")
  ((title :type (string :min 1 :max 200) :required t)))

;;; Records only an admin reads, without a record policy: entity-readable-p
;;; keeps them from others.
(define-entity admin-note (:label "Adminnotat" :id-prefix "ant" :table "test_admin_notes"
                                  :attachments t)
  ((title :type (string :min 1 :max 200) :required t)))

(define-operation admin-notes-create ((:draft admin-note))
    (:entity admin-note :kind :create :policy :admin :title "Nytt adminnotat")
  (insert admin-note))

(define-operation admin-notes-get ((id :type (id admin-note) :required t))
    (:entity admin-note :kind :read :policy :admin :title "Adminnotat")
  (fetch! 'admin-note id))

;;; Each employee's own records (spec/store.md 6), on Postgres.
(define-entity own-note (:label "Eget notat" :id-prefix "ont" :table "test_own_notes"
                                :attachments t
                                :record-policy ((:admin t) (:employee "author = :actor_name")))
  ((title :type (string :min 1 :max 200) :required t)
   (author :type (string :max 64) :input nil)))

(define-operation own-notes-create ((:draft own-note))
    (:entity own-note :kind :create :policy :employee :title "Nytt eget notat")
  (setf (own-note-author own-note) (actor-name *actor*))
  (insert own-note))

(define-operation own-notes-get ((id :type (id own-note) :required t))
    (:entity own-note :kind :read :policy :employee :title "Eget notat")
  (fetch! 'own-note id))

;;; ------------------------------------------------------------------
;;; Files to attach

(defun fixture (name)
  "The octets of the test file NAME in tests/fixtures/files/."
  (coerce (alexandria:read-file-into-byte-vector
           (asdf:system-relative-pathname "tun" (format nil "tests/fixtures/files/~a" name)))
          '(simple-array (unsigned-byte 8) (*))))

(defun bytes (&rest parts)
  "PARTS joined as octets: each an octet vector, a list of octets, a string
of ASCII, or an integer for one octet."
  (let* ((parts (mapcar (lambda (part)
                          (etypecase part
                            (integer (list part))
                            (string (map 'list #'char-code part))
                            (sequence part)))
                        parts))
         (octets (make-array (reduce #'+ parts :key #'length) :element-type '(unsigned-byte 8)))
         (at 0))
    (dolist (part parts octets)
      (replace octets part :start1 at)
      (incf at (length part)))))

(defun base64 (octets)
  (cl-base64:usb8-array-to-base64-string octets))

(defun file-json (name octets)
  (jobj "filename" name "data" (base64 octets)))

(defun files-json (&rest names-and-octets)
  (jarr (loop for (name octets) on names-and-octets by #'cddr collect (file-json name octets))))

(defun contains-p (octets pattern)
  "True when OCTETS holds PATTERN (octets or ASCII) anywhere."
  (and (search (bytes pattern) octets) t))

(defun examined (octets)
  "Values of EXAMINE-FILE for OCTETS, or the refusal's message."
  (handler-case (tun.files:examine-file octets)
    (tun.files:file-refused (e) (tun.files:file-refused-message e))))

(defun file-refusal-of (octets)
  "The message Tun refuses OCTETS with, or NIL when it takes them."
  (let ((result (multiple-value-list (examined octets))))
    (and (stringp (first result)) (first result))))

(defparameter +damaged+ "The image is damaged or incomplete.")
(defparameter +type-refused+ "This type of file is not allowed. Use PNG, JPEG, WebP, GIF or PDF.")

;;; PNG

(defun png-chunk (name data)
  (let ((data (bytes data)))
    (bytes (list (ldb (byte 8 24) (length data)) (ldb (byte 8 16) (length data))
                 (ldb (byte 8 8) (length data)) (ldb (byte 8 0) (length data)))
           name data
           (ironclad:digest-sequence :crc32 (bytes name data)))))

(defun u32 (n) (list (ldb (byte 8 24) n) (ldb (byte 8 16) n) (ldb (byte 8 8) n) (ldb (byte 8 0) n)))

(defun png-chunks (octets)
  "The chunks of the PNG OCTETS, each as (NAME START END)."
  (loop with at = 8
        while (< at (length octets))
        collect (let* ((length (tun.files::u32be octets at))
                       (end (+ at 12 length)))
                  (prog1 (list (map 'string #'code-char (subseq octets (+ at 4) (+ at 8))) at end)
                    (setf at end)))))

(defun png-with (octets &key before-idat after-iend (ihdr nil))
  "The PNG OCTETS with chunks BEFORE-IDAT put before its first IDAT, AFTER-IEND
appended, and its IHDR replaced by IHDR when given."
  (let* ((chunks (png-chunks octets))
         (first-idat (second (find "IDAT" chunks :key #'first :test #'string=)))
         (ihdr-end (third (first chunks))))
    (bytes (subseq octets 0 8)
           (or ihdr (subseq octets 8 ihdr-end))
           (subseq octets ihdr-end first-idat)
           (apply #'bytes before-idat)
           (subseq octets first-idat)
           (or after-iend #()))))

(defun png-of-size (width height)
  "The screenshot fixture with its IHDR saying WIDTH × HEIGHT."
  (let ((png (fixture "skjermbilde.png")))
    (png-with png :ihdr (png-chunk "IHDR" (bytes (u32 width) (u32 height)
                                                 (subseq png 24 29))))))

;;; JPEG

(defun jpeg-segment (marker payload)
  (let ((payload (bytes payload)))
    (bytes #xFF marker
           (ldb (byte 8 8) (+ 2 (length payload))) (ldb (byte 8 0) (+ 2 (length payload)))
           payload)))

(defun exif-payload (&key (orientation 1) (gps t))
  "An Exif APP1's content, big-endian: IFD0 with the orientation and a GPS
pointer, and a GPS IFD holding a latitude."
  (bytes "Exif" 0 0 "MM" 0 #x2A (u32 8)
         ;; IFD0: two entries
         0 2
         #x01 #x12 0 3 (u32 1) 0 orientation 0 0
         #x88 #x25 0 4 (u32 1) (u32 38)
         (u32 0)
         ;; the GPS IFD at 38: GPSLatitudeRef "N" and a text that names it
         0 1
         0 1 0 2 (u32 2) "N" 0 0 0
         (u32 0)
         (if gps "GPS 59.9139 N 10.7522 E" "")))

(defun jpeg-with (octets &rest segments)
  "The JPEG OCTETS with SEGMENTS put right after its SOI and its JFIF APP0."
  (let ((after-app0 (if (= (aref octets 3) #xE0)
                        (+ 4 (tun.files::u16be octets 4))
                        2)))
    (bytes (subseq octets 0 after-app0) (apply #'bytes segments) (subseq octets after-app0))))

(defun jfif-with-thumbnail ()
  "A JFIF APP0 carrying a 2 × 1 thumbnail."
  (jpeg-segment #xE0 (bytes "JFIF" 0 1 2 0 0 1 0 1 2 1 255 0 0 0 255 0)))

;;; WebP

(defun riff-chunk (name data)
  (let ((data (bytes data)))
    (bytes name (ldb (byte 8 0) (length data)) (ldb (byte 8 8) (length data))
           (ldb (byte 8 16) (length data)) (ldb (byte 8 24) (length data))
           data (if (oddp (length data)) (list 0) '()))))

(defun webp-of (&rest chunks)
  (let ((body (apply #'bytes "WEBP" chunks)))
    (bytes "RIFF" (ldb (byte 8 0) (length body)) (ldb (byte 8 8) (length body))
           (ldb (byte 8 16) (length body)) (ldb (byte 8 24) (length body)) body)))

(defun webp-chunks (octets)
  "The top-level chunks of the WebP OCTETS, as (NAME DATA)."
  (loop with at = 12
        while (< at (length octets))
        collect (let* ((length (tun.files::u32le octets (+ at 4)))
                       (data (subseq octets (+ at 8) (+ at 8 length))))
                  (prog1 (list (map 'string #'code-char (subseq octets at (+ at 4))) data)
                    (setf at (+ at 8 length (logand length 1)))))))

(defun vp8x (flags width height)
  (bytes flags 0 0 0 (ldb (byte 8 0) (1- width)) (ldb (byte 8 8) (1- width))
         (ldb (byte 8 16) (1- width)) (ldb (byte 8 0) (1- height)) (ldb (byte 8 8) (1- height))
         (ldb (byte 8 16) (1- height))))

(defun anmf (width height frame)
  (bytes 0 0 0 0 0 0
         (ldb (byte 8 0) (1- width)) (ldb (byte 8 8) (1- width)) (ldb (byte 8 16) (1- width))
         (ldb (byte 8 0) (1- height)) (ldb (byte 8 8) (1- height)) (ldb (byte 8 16) (1- height))
         100 0 0 0 frame))

(defun fixture-vp8 ()
  "The lossy image data of the WebP fixture."
  (second (find "VP8 " (webp-chunks (fixture "foto.webp")) :key #'first :test #'string=)))

(defun lossless-vp8l (width height)
  "A VP8L chunk's start: its signature and size; enough for Tun, which never decodes it."
  (let ((bits (logior (1- width) (ash (1- height) 14))))
    (bytes #x2F (ldb (byte 8 0) bits) (ldb (byte 8 8) bits) (ldb (byte 8 16) bits)
           (ldb (byte 8 24) bits) 0 0 0)))

;;; GIF

(defun gif-image (width height)
  (bytes #x2C 0 0 0 0 (ldb (byte 8 0) width) (ldb (byte 8 8) width)
         (ldb (byte 8 0) height) (ldb (byte 8 8) height) 0
         2 2 #x4C #x01 0))

(defun gif-of (width height &rest blocks)
  (apply #'bytes "GIF89a" (ldb (byte 8 0) width) (ldb (byte 8 8) width)
         (ldb (byte 8 0) height) (ldb (byte 8 8) height) #x80 0 0
         0 0 0 255 255 255 blocks))

(defparameter +gif-control+ (bytes #x21 #xF9 4 0 10 0 0 0))
(defparameter +gif-looping+ (bytes #x21 #xFF 11 "NETSCAPE2.0" 3 1 0 0 0))
(defparameter +gif-comment+ (bytes #x21 #xFE 10 "Kari, Oslo" 0))
(defparameter +gif-xmp+ (bytes #x21 #xFF 11 "XMP DataXMP" 6 "<x:gps" 0))
(defparameter +gif-text+ (bytes #x21 #x01 12 0 0 0 0 10 0 10 0 8 8 1 0 4 "Hemm" 0))

;;; PDF

(defparameter +minimal-pdf+ (bytes "%PDF-1.4" 10 "%%EOF" 10))

;;; ------------------------------------------------------------------
;;; 1. Opting in (spec/files.md 1)

(test the-attachments-option-is-checked-when-compiled
  (dolist (option '((:max 0) (:max 101) (:max "3") (:policy :viewer) (:policy :owner) (:size 3)
                    (:max) 7 "t"))
    (is (eq :refused (handler-case (progn (macroexpand-1 `(define-entity refused-note
                                                              (:attachments ,option)
                                                            ((title))))
                                          :defined)
                       (error () :refused)))
        "~s is refused" option))
  (is (eq :refused (handler-case (progn (macroexpand-1 '(define-entity refused-line
                                                         (:embedded t :attachments t)
                                                         ((title))))
                                        :defined)
                     (error () :refused)))
      "an embedded entity takes no files")
  (is (equal '(:max 20 :policy :employee) (tun.core::parse-attachments-option 'x t)))
  (is (equal '(:max 7 :policy :admin)
             (tun.core::parse-attachments-option 'x '(:max 7 :policy :admin))))
  (is (eq :refused (handler-case (progn (macroexpand-1 '(define-entity refused-field
                                                         ()
                                                         ((shots :type (files :max 2)))))
                                        :defined)
                     (error () :refused)))
      "a stored field of type files"))

(test registry-describe-lists-each-entitys-attachments
  (with-test-app ()
    (let ((entities (jget (call-ok "registry_describe" "viewer:vera") "entities")))
      (flet ((attachments (name) (jget (find-by "name" name entities) "attachments")))
        (is (equal 3 (jget (attachments "file_note") "max")))
        (is (equal "employee" (jget (attachments "file_note") "policy")))
        (is (equal "admin" (jget (attachments "locked_note") "policy")))
        (is (eq :null (attachments "plain_note")))))))

;;; ------------------------------------------------------------------
;;; 2, 3. Types by their bytes, and damaged files (spec/files.md 2.1)

(test each-type-is-recognised-by-its-bytes
  (dolist (case '(("skjermbilde.png" :png 640 400) ("foto.jpg" :jpeg 480 320)
                  ("foto.webp" :webp 480 320) ("gjennomsiktig.webp" :webp 200 120)
                  ("kvittering.pdf" :pdf nil nil)))
    (destructuring-bind (name type width height) case
      (multiple-value-bind (stored found w h) (tun.files:examine-file (fixture name))
        (is (eq type found) "~a" name)
        (is (eql width w) "~a's width" name)
        (is (eql height h) "~a's height" name)
        (is (typep stored '(simple-array (unsigned-byte 8) (*)))))))
  (is (eq :webp (nth-value 1 (examined (webp-of (riff-chunk "VP8L" (lossless-vp8l 30 20))))))
      "a lossless WebP")
  (is (eq :gif (nth-value 1 (examined (gif-of 2 2 (gif-image 2 2) #x3B)))))
  (is (eq :pdf (nth-value 1 (examined +minimal-pdf+)))))

(test other-types-are-refused-whatever-their-name
  (dolist (octets (list (bytes "<svg xmlns=\"http://www.w3.org/2000/svg\">"
                               "<script>alert(1)</script></svg>")
                        (bytes "<!doctype html><script>alert(1)</script>")
                        (bytes "Dette er tekst, ikke et bilde.")
                        (bytes "PK" 3 4 20 0 0 0 0 0)
                        (bytes #xFF #xD8)))
    (is (equal +type-refused+ (file-refusal-of octets)))))

(test damaged-files-are-refused
  (let ((png (fixture "skjermbilde.png"))
        (jpeg (fixture "foto.jpg"))
        (webp (fixture "foto.webp")))
    (flet ((damaged-p (octets) (equal +damaged+ (file-refusal-of octets))))
      ;; PNG
      (is (damaged-p (subseq png 0 20)) "cut off inside IHDR")
      (is (damaged-p (bytes (subseq png 0 (- (length png) 30)))) "a chunk running past the end")
      (is (damaged-p (bytes (subseq png 0 (- (length png) 12)))) "no IEND")
      (is (damaged-p (bytes (subseq png 0 33) (png-chunk "IEND" ""))) "no IDAT")
      (is (damaged-p (png-with png :before-idat (list (png-chunk "ABCD" "x"))))
          "an unknown critical chunk")
      ;; JPEG
      (is (damaged-p (bytes (subseq jpeg 0 4) 0 200 (subseq jpeg 6)))
          "a segment running past the end")
      (is (damaged-p (bytes #xFF #xD8 (jpeg-segment #xDA (bytes 1 1 0 0 63 0)) 1 2 3 #xFF #xD9))
          "a scan before any frame header")
      (let ((frame (jpeg-segment #xC0 (bytes 8 0 4 0 4 1 1 #x11 0))))
        (is (damaged-p (jpeg-with jpeg frame)) "a second frame header"))
      (is (damaged-p (jpeg-with jpeg (jpeg-segment #xDC (bytes 0 4)))) "DNL")
      (is (damaged-p (bytes (subseq jpeg 0 (- (length jpeg) 2)))) "no EOI")
      (let ((sof (search (bytes #xFF #xC0) jpeg)))
        (is (damaged-p (let ((copy (copy-seq jpeg)))
                         (setf (aref copy (+ sof 5)) 0 (aref copy (+ sof 6)) 0)
                         copy))
            "a frame of height 0"))
      (is (eq :jpeg (nth-value 1 (examined (bytes (subseq jpeg 0 2) #xFF #xFF (subseq jpeg 2)))))
          "fill bytes before a marker are taken")
      ;; WebP
      (is (damaged-p (bytes "RIFF" 255 255 0 0 (subseq webp 8))) "a RIFF size past the end")
      (is (damaged-p (webp-of (bytes "VP8 " 255 255 0 0 (subseq (fixture-vp8) 0 20))))
          "a chunk running past the end")
      (is (damaged-p (webp-of (riff-chunk "ICCP" "abc"))) "no image data")
      ;; GIF
      (is (damaged-p (bytes "GIF89a" 2 0 2 0 #x80 0 0 0 0)) "a colour table cut off")
      (is (damaged-p (gif-of 2 2 (subseq (gif-image 2 2) 0 6))) "an image descriptor cut off")
      (is (damaged-p (gif-of 2 2 #x2C 0 0 0 0 2 0 2 0 0 2 40 1 2 3)) "a sub-block past the end")
      (is (damaged-p (gif-of 2 2 #x2A (gif-image 2 2) #x3B)) "a block of an unknown kind")
      (is (damaged-p (gif-of 2 2 (gif-image 2 2))) "no trailer")
      (is (damaged-p (gif-of 0 2 (gif-image 2 2) #x3B)) "a logical screen of width 0"))))

;;; ------------------------------------------------------------------
;;; 4. Size and dimensions (spec/files.md 2.2)

(defparameter +too-large+
  "The image is too large: at most 30,000 pixels on each side and 50 megapixels.")

(test dimensions-come-from-the-header-and-are-bounded
  (let ((turned (jpeg-with (fixture "foto.jpg") (jpeg-segment #xE1 (exif-payload :orientation 6)))))
    (multiple-value-bind (stored type width height) (tun.files:examine-file turned)
      (declare (ignore stored type))
      (is (equal '(320 480) (list width height)) "a JPEG turned a quarter is shown tall")))
  (is (equal +too-large+ (file-refusal-of (png-of-size 30001 10))))
  (is (equal +too-large+ (file-refusal-of (png-of-size 10000 5001))) "over 50 megapixels")
  (is (equal '(30000 1600) (multiple-value-bind (s ty w h)
                               (tun.files:examine-file (png-of-size 30000 1600))
                             (declare (ignore s ty))
                             (list w h))))
  (is (equal +too-large+ (file-refusal-of (gif-of 2 2 (gif-image 30001 2) #x3B))) "a GIF frame")
  (is (equal +too-large+
             (file-refusal-of
              (webp-of (riff-chunk "VP8X" (vp8x 2 10 10))
                       (riff-chunk "ANIM" (bytes 0 0 0 0 0 0))
                       (riff-chunk "ANMF" (anmf 30001 10 (riff-chunk "VP8 " (fixture-vp8)))))))
      "a WebP frame"))

(defun call-files (actor &rest files)
  "Create a note titled «Med filer» with FILES (FILE-JSON objects) as ACTOR."
  (call "file_notes_create" actor "title" "Med filer" "screenshots" (jarr files)))

(defun field-message (json)
  "The first field error's message in JSON, an error document."
  (let ((fields (jget (jget json "error") "fields")))
    (and fields (plusp (length fields)) (jget (aref fields 0) "message"))))

(test sizes-are-bounded-per-file-per-call-and-per-record
  (with-test-app ()
    (let* ((png (fixture "skjermbilde.png"))
           (exactly (bytes png (make-array (- (* 10 1024 1024) (length png)) :initial-element 0)))
           (over (bytes exactly 0)))
      ;; Bytes after IEND are dropped, so a file of exactly 10 MiB is taken.
      (is (null (nth-value 1 (call-files "employee:anna" (file-json "stor.png" exactly)))))
      (multiple-value-bind (json code) (call-files "employee:anna" (file-json "for-stor.png" over))
        (is (string= "invalid_input" code))
        (is (equal "“for-stor.png”: The file is larger than 10 MB." (field-message json))))
      (multiple-value-bind (json code) (call-files "employee:anna" (file-json "tom.png" (bytes)))
        (is (string= "invalid_input" code))
        (is (equal "“tom.png”: The file is empty." (field-message json)))))
    (multiple-value-bind (json code)
        (call "attachments_add" "employee:anna" "entity" "file_note" "record_id" "fnt_x"
              "files" (jarr (loop repeat 11
                                  collect (file-json "a.png" (fixture "skjermbilde.png")))))
      (is (string= "invalid_input" code))
      (is (search "at most 10 files" (field-message json))))
    (let* ((padding (make-array (* 9 1024 1024) :initial-element 0))
           (nine (bytes (fixture "skjermbilde.png") padding))
           (id (jget (call-ok "file_notes_create" "employee:anna" "title" "Tom") "id")))
      (multiple-value-bind (json code)
          (call "attachments_add" "employee:anna" "entity" "file_note" "record_id" id
                "files" (files-json "1.png" nine "2.png" nine "3.png" nine))
        (is (string= "invalid_input" code))
        (is (search "25 MB together" (field-message json))))
      (call-ok "attachments_add" "employee:anna" "entity" "file_note" "record_id" id
               "files" (files-json "1.png" (fixture "skjermbilde.png")
                                   "2.png" (fixture "skjermbilde.png")))
      (multiple-value-bind (json code)
          (call "attachments_add" "employee:anna" "entity" "file_note" "record_id" id
                "files" (files-json "3.png" (fixture "skjermbilde.png")
                                    "4.png" (fixture "skjermbilde.png")))
        (is (string= "invalid_input" code))
        (is (equal "At most 3 files per notat." (field-message json))))
      (is (= 2 (length (jget (call-ok "attachments_list" "viewer:vera" "entity" "file_note"
                                      "record_id" id)
                             "items")))
          "none of the refused call's files is stored"))))

;;; ------------------------------------------------------------------
;;; 5. What is taken out (spec/files.md 3)

(test a-jpeg-keeps-its-image-and-loses-its-metadata
  (let* ((jpeg (fixture "foto.jpg"))
         (icc (jpeg-segment #xE2 (bytes "ICC_PROFILE" 0 1 1 "profil")))
         (adobe (jpeg-segment #xEE (bytes "Adobe" 0 100 0 0 0 0 1)))
         (given (bytes (subseq (jpeg-with jpeg
                                          (jpeg-segment #xE1 (exif-payload :orientation 6))
                                          (jpeg-segment #xE1 (bytes "http://ns.adobe.com/xap/1.0/" 0
                                                                    "<x:xmpmeta/>"))
                                          (jpeg-segment #xED (bytes "Photoshop 3.0" 0 "8BIM"))
                                          (jpeg-segment #xFE "Tatt av Kari")
                                          (jpeg-segment #xE0 (bytes "JFXX" 0 #x10 "thumb"))
                                          (jpeg-segment #xE2 (bytes "MPF" 0 "MM" 0 42))
                                          (jpeg-segment #xEF "APP15")
                                          icc adobe)
                               0)
                       (bytes "GPS 59.9139 N" #xFF #xD8 #xFF #xE1 0 4 0 0)))
         (stored (tun.files:examine-file given)))
    (dolist (gone '("GPS" "http://ns.adobe.com/xap" "Photoshop 3.0" "Tatt av Kari" "JFXX" "MPF"
                    "APP15"))
      (is (not (contains-p stored gone)) "no ~a" gone))
    (is (= 1 (count-if (lambda (i) (search (bytes "Exif" 0 0) stored :start2 i :end2 (+ i 6)))
                       (loop for i below (- (length stored) 6) collect i)))
        "only the minimal Exif")
    (is (contains-p stored (tun.files::orientation-segment 6)) "its orientation kept")
    (is (contains-p stored icc) "its ICC profile")
    (is (contains-p stored adobe) "Adobe's colour segment")
    (let ((tables (search (bytes #xFF #xDB) jpeg)))
      (is (contains-p stored (subseq jpeg tables)) "tables, frame and scans byte for byte"))
    (is (equalp (bytes #xFF #xD9) (subseq stored (- (length stored) 2))) "nothing after EOI"))
  (let ((stored (tun.files:examine-file
                 (jpeg-with (fixture "foto.jpg")
                            (jpeg-segment #xE1 (exif-payload :orientation 1))))))
    (is (not (contains-p stored (bytes "Exif" 0 0))) "orientation 1 gets no Exif")))

(test a-jfif-thumbnail-is-taken-out
  (let* ((jpeg (fixture "foto.jpg"))
         (without-app0 (bytes (subseq jpeg 0 2) (subseq jpeg (+ 4 (tun.files::u16be jpeg 4)))))
         (stored (tun.files:examine-file (bytes (subseq without-app0 0 2) (jfif-with-thumbnail)
                                                (subseq without-app0 2)))))
    (is (equalp (bytes #xFF #xE0 0 16 "JFIF" 0 1 2 0 0 1 0 1 0 0) (subseq stored 2 20))
        "JFIF with a 0 × 0 thumbnail")
    (is (not (contains-p stored (bytes 255 0 0 0 255 0))))))

(test a-progressive-jpeg-loses-a-comment-between-its-scans
  (let* ((jpeg (fixture "foto.jpg"))
         (eoi (- (length jpeg) 2))
         (scan (bytes (jpeg-segment #xDA (bytes 1 1 0 0 63 0)) 1 2 3))
         (given (bytes (subseq jpeg 0 eoi) (jpeg-segment #xFE "Mellom skann") scan #xFF #xD9))
         (stored (tun.files:examine-file given)))
    (is (not (contains-p stored "Mellom skann")))
    (is (contains-p stored (subseq jpeg (search (bytes #xFF #xDA) jpeg) eoi)) "the first scan")
    (is (contains-p stored scan) "the second scan")))

(test an-unreadable-exif-gives-no-orientation
  (let ((jpeg (fixture "foto.jpg")))
    (multiple-value-bind (stored type width height)
        (tun.files:examine-file (jpeg-with jpeg (jpeg-segment #xE1 (bytes "Exif" 0 0 "MM" 0 #x2A
                                                                          (u32 9999)))))
      (declare (ignore type))
      (is (not (contains-p stored (bytes "Exif" 0 0))))
      (is (equal '(480 320) (list width height)) "taken upright as stored"))
    (multiple-value-bind (stored type width height)
        (tun.files:examine-file (jpeg-with jpeg (jpeg-segment #xE1 (exif-payload :orientation 6))
                                           (jpeg-segment #xE1 (exif-payload :orientation 8))))
      (declare (ignore type))
      (is (not (contains-p stored (bytes "Exif" 0 0))) "two Exif segments")
      (is (equal '(480 320) (list width height))))))

(test a-png-keeps-only-its-listed-chunks
  (let* ((png (fixture "skjermbilde.png"))
         (kept (list (png-chunk "iCCP" (bytes "sRGB" 0 0 1 2 3))
                     (png-chunk "pHYs" (bytes (u32 3780) (u32 3780) 1))
                     (png-chunk "acTL" (bytes (u32 1) (u32 0)))
                     (png-chunk "fcTL" (bytes (u32 0) (u32 640) (u32 400) (u32 0) (u32 0)
                                              0 1 0 1 0 0))))
         (dropped (list (png-chunk "eXIf" (bytes "MM" 0 42 "GPS"))
                        (png-chunk "tEXt" (bytes "Author" 0 "Kari"))
                        (png-chunk "zTXt" (bytes "Comment" 0 0 "x"))
                        (png-chunk "iTXt" (bytes "XML:com.adobe.xmp" 0 0 0 0 0 "<x/>"))
                        (png-chunk "tIME" (bytes 7 234 10 26 12 0 0))
                        (png-chunk "prVt" "hemmelig")))
         (fdat (png-chunk "fdAT" (bytes (u32 1) "frame")))
         (given (png-with png :before-idat (append kept dropped) :after-iend (bytes fdat "etter")))
         (stored (tun.files:examine-file given)))
    (dolist (chunk kept)
      (is (contains-p stored chunk) "keeps ~a" (map 'string #'code-char (subseq chunk 4 8))))
    (dolist (chunk dropped)
      (is (not (contains-p stored chunk)) "drops ~a" (map 'string #'code-char (subseq chunk 4 8))))
    (is (not (contains-p stored "etter")) "nothing after IEND")
    (is (equalp png (tun.files:examine-file png)) "a PNG without metadata is as given")))

(test a-webp-keeps-only-its-listed-chunks
  (let* ((vp8 (fixture-vp8))
         (given (bytes (webp-of (riff-chunk "VP8X" (vp8x #x2C 480 320))
                                (riff-chunk "ICCP" "profil")
                                (riff-chunk "VP8 " vp8)
                                (riff-chunk "EXIF" (bytes "MM" 0 42 "GPS"))
                                (riff-chunk "XMP " "<x:xmpmeta/>")
                                (riff-chunk "UNKN" "ukjent"))
                       "etter"))
         (stored (tun.files:examine-file given))
         (chunks (webp-chunks stored)))
    (is (equal '("VP8X" "ICCP" "VP8 ") (mapcar #'first chunks)))
    (is (= #x20 (aref (second (first chunks)) 0)) "the Exif and XMP flags cleared, ICC kept")
    (is (= (- (length stored) 8) (tun.files::u32le stored 4)) "the RIFF size matches")
    (is (equalp vp8 (second (third chunks))) "the image byte for byte")))

(test a-gif-loses-comments-text-and-other-applications
  (let* ((image (gif-image 2 2))
         (given (gif-of 2 2 +gif-looping+ +gif-comment+ +gif-xmp+ +gif-control+ image +gif-text+
                        +gif-control+ image #x3B "etter"))
         (stored (tun.files:examine-file given)))
    (is (equalp (gif-of 2 2 +gif-looping+ +gif-control+ image +gif-control+ image #x3B) stored))))

(test a-pdf-is-stored-as-given
  (let ((pdf (fixture "kvittering.pdf")))
    (is (equalp pdf (tun.files:examine-file pdf)))))

(test nothing-decompresses-decodes-or-runs-a-program
  (let ((forbidden '("chipz" "deflate" "zlib" "salza2" "opticl" "pngload" "png-read" "cl-jpeg"
                     "retrospectiff" "skippy")))
    (dolist (system '("tun" "tun/core"))
      (let ((depends (mapcar (lambda (d) (string-downcase (if (consp d) (second d) d)))
                             (asdf:system-depends-on (asdf:find-system system)))))
        (is (null (intersection forbidden depends :test #'string=)) "~a depends on none" system)))
    (dolist (file '("src/files/package.lisp" "src/files/formats.lisp" "src/files/multipart.lisp"
                    "src/files/attachments.lisp" "src/web/files.lisp" "src/web/ui/files.lisp"))
      (let ((text (string-downcase (file-text (asdf:system-relative-pathname "tun" file)))))
        (dolist (word (append forbidden '("run-program" "launch-program")))
          (is (not (search word text)) "~a names ~a" file word))))))

;;; ------------------------------------------------------------------
;;; 6. Names (spec/files.md 2.3)

(test names-are-cleaned
  (flet ((name (given type) (tun.files:stored-filename given type)))
    (is (equal "passwd.png" (name "../../etc/passwd.png" :png)))
    (is (equal "Skjerm 1.png" (name "C:\\Users\\kari\\Skjerm \"1\".png" :png)))
    (is (equal "fakturagnp.pdf" (name (format nil "faktura~cgnp.pdf" (code-char #x202E)) :pdf)))
    (is (equal "abcdefg.png"
               (name (format nil "a~cb~cc~cd~ce~cf~cg.png" #\Tab (code-char 0) (code-char #x200B)
                             (code-char #x200E) (code-char #x2066) (code-char #x2029))
                     :png)))
    (let ((cut (name (concatenate 'string (make-string 246 :initial-element #\a) ".png") :png)))
      (is (= 200 (length cut)))
      (is (alexandria:ends-with-subseq ".png" cut)))
    (let ((cut (name (make-string 198 :initial-element #\b) :pdf)))
      (is (= 200 (length cut)))
      (is (alexandria:ends-with-subseq ".pdf" cut)))
    (is (equal "skjermbilde.png" (name "skjermbilde" :png)))
    (is (equal "faktura.png.pdf" (name "faktura.png" :pdf)))
    (is (equal "bilde.JPEG" (name "bilde.JPEG" :jpeg)))
    (is (equal "file.png" (name "" :png))))
  (with-test-app ()
    (multiple-value-bind (json code)
        (call-files "employee:anna" (file-json (make-string 256 :initial-element #\x)
                                               (fixture "skjermbilde.png")))
      (is (string= "invalid_input" code))
      (is (equal "The filename cannot be longer than 255 characters." (field-message json))))
    (is (null (nth-value 1 (call-files "employee:anna"
                                       (file-json (make-string 255 :initial-element #\x)
                                                  (fixture "skjermbilde.png"))))))))

;;; ------------------------------------------------------------------
;;; 7. An agent's input (spec/files.md 4.1)

(test files-come-as-base64-and-never-as-an-address
  (with-test-app ()
    (let ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "Base64") "id"))
          (encoded (base64 (fixture "skjermbilde.png"))))
      (flet ((add (file)
               (multiple-value-bind (json code)
                   (call "attachments_add" "employee:anna" "entity" "file_note" "record_id" id
                         "files" (jarr (list file)))
                 (values (field-message json) code))))
        (let ((lines (loop for start from 0 below (length encoded) by 76
                           append (list (subseq encoded start (min (length encoded) (+ start 76)))
                                        #\Return #\Newline))))
          (is (null (nth-value 1 (add (jobj "filename" "linjer.png"
                                            "data" (format nil "~{~a~^~c~c~}" lines)))))
              "line breaks are ignored"))
        (is (equal "“a.png”: The content in data is not valid base64."
                   (add (jobj "filename" "a.png"
                              "data" (concatenate 'string "*" (subseq encoded 1))))))
        (is (equal "“a.png”: The content in data is not valid base64."
                   (add (jobj "filename" "a.png" "data" (subseq encoded 0 (1- (length encoded))))))
            "bad padding")
        (is (equal "“a.png”: Send only the base64 content in data, without “data:…;base64,” in front."
                   (add (jobj "filename" "a.png"
                              "data" (concatenate 'string "data:image/png;base64," encoded)))))
        (let ((*http-json-handler* (lambda (&rest arguments)
                                     (declare (ignore arguments))
                                     (error "nothing may be fetched"))))
          (is (equal "Tun does not fetch files from an address. Send the content as base64 in data."
                     (add (jobj "filename" "a.png" "url" "http://127.0.0.1/hemmelig.png")))))
        (is (equal "“a.png”: The file must be sent as base64 in data."
                   (add (jobj "filename" "a.png" "upload" "upl_gjettet")))
            "a page's handle means nothing over MCP")))
    (let* ((tools (with-application (*app*) (tool-definitions *app*)))
           (tool (find "attachments_add" tools :key (lambda (tool) (jget tool "name"))
                       :test #'string=))
           (files (jget (jget (jget tool "inputSchema") "properties") "files")))
      (is (equal "base64" (jget (jget (jget (jget files "items") "properties") "data")
                                "contentEncoding"))))))

;;; ------------------------------------------------------------------
;;; 8. The tools (spec/files.md 4.2)

(defun add-file (actor entity id
                 &optional (name "skjermbilde.png") (octets (fixture "skjermbilde.png")))
  (call "attachments_add" actor "entity" entity "record_id" id "files" (files-json name octets)))

(defun first-file-id (json)
  "The id of the first file in JSON, attachments_add's result."
  (jget (aref (jget json "items") 0) "id"))

(defun note-file-count (id)
  "How many files the file note ID has, as a viewer lists them."
  (length (jget (call-ok "attachments_list" "viewer:vera" "entity" "file_note" "record_id" id)
                "items")))

(test the-tools-add-list-and-remove-files
  (with-test-app ()
    (let* ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "Verktøy") "id"))
           (added (jget (call-ok "attachments_add" "employee:anna" "entity" "file_note"
                                 "record_id" id "request_key" "k1"
                                 "files" (files-json "skjerm.png" (fixture "skjermbilde.png")
                                                     "kvittering" (fixture "kvittering.pdf")))
                        "items"))
           (again (jget (call-ok "attachments_add" "employee:anna" "entity" "file_note"
                                 "record_id" id "request_key" "k1"
                                 "files" (files-json "skjerm.png" (fixture "skjermbilde.png")
                                                     "kvittering" (fixture "kvittering.pdf")))
                        "items"))
           (listed (call-ok "attachments_list" "viewer:vera" "entity" "file_note" "record_id" id))
           (png (aref added 0))
           (pdf (aref added 1)))
      (is (equal (jget png "id") (jget (aref again 0) "id")) "the same request_key adds once")
      (is (= 2 (jget listed "returned")))
      (is (eq nil (jget listed "has_more")))
      (is (equal (list "skjerm.png" "image/png" 640 400 "employee:anna" "file_note" id)
                 (mapcar (lambda (key) (jget png key))
                         '("filename" "content_type" "width" "height" "created_by" "entity"
                           "record_id"))))
      (is (equal (list "kvittering.pdf" "application/pdf" :null :null)
                 (mapcar (lambda (key) (jget pdf key))
                         '("filename" "content_type" "width" "height"))))
      (is (equal (format nil "/files/~a" (jget png "id")) (jget png "url")))
      (is (cl-ppcre:scan "^fil_[0-9a-z]{26}$" (jget png "id")) "130 random bits")
      (is (string= "forbidden" (nth-value 1 (add-file "viewer:vera" "file_note" id))))
      (is (string= "invalid_input" (nth-value 1 (add-file "employee:anna" "plain_note" "pnt_x"))))
      (is (string= "not_found"
                   (nth-value 1 (add-file "employee:anna" "file_note" "fnt_finnes_ikke"))))
      (let ((entry (find-if (lambda (e) (and (equal "attachments_add" (jget e "tool"))
                                             (equal "ok" (jget e "outcome"))))
                            (coerce (jget (call-ok "audit_list" "admin:ada") "items") 'list))))
        (is (equal (list "file_note" id)
                   (list (jget entry "entity_type") (jget entry "entity_id")))
            "audited with the record as its target"))
      (call-ok "attachments_remove" "employee:anna" "id" (jget pdf "id"))
      (is (= 1 (jget (call-ok "attachments_list" "viewer:vera" "entity" "file_note" "record_id" id)
                     "returned"))))))

(test only-the-one-who-attached-a-file-or-an-admin-removes-it
  (with-test-app ()
    (let* ((id (jget (call-ok "file_notes_create" "employee:kari" "title" "Karis") "id"))
           (karis (first-file-id (add-file "employee:kari" "file_note" id)))
           (second (first-file-id (add-file "employee:kari" "file_note" id)))
           (systems (with-application (*app*)
                      (with-actor ((system-actor "test"))
                        (with-transaction (:write)
                          (entity-id (first (tun.files:attach-files
                                             (fetch 'file-note id)
                                             (collecting-input-errors
                                              (coerce-input (parse-field-type '(files))
                                                            (files-json "system.png"
                                                                        (fixture "skjermbilde.png"))
                                                            "files"))))))))))
      (is (string= "forbidden" (nth-value 1 (call "attachments_remove" "employee:ola" "id" karis))))
      (is (= 3 (note-file-count id)) "Kari's file stays")
      (is (string= "forbidden"
                   (nth-value 1 (call "attachments_remove" "employee:kari" "id" systems)))
          "a file the system attached is an admin's to remove")
      (call-ok "attachments_remove" "admin:kari" "id" second)
      (is (null (nth-value 1 (call "attachments_remove" "employee:kari" "id" karis)))
          "her files stay hers when her role changes: the account is compared by name")
      (call-ok "attachments_remove" "admin:ada" "id" systems)
      (is (= 0 (note-file-count id))))))

(test an-entity-with-an-admin-policy-takes-files-from-admins
  (with-test-app ()
    (let ((id (with-application (*app*)
                (with-actor ((system-actor "test"))
                  (with-transaction (:write)
                    (entity-id (insert (make-instance 'locked-note :title "Låst"))))))))
      (is (string= "forbidden" (nth-value 1 (add-file "employee:anna" "locked_note" id))))
      (let ((file (first-file-id (add-file "admin:ada" "locked_note" id))))
        (is (string= "forbidden"
                     (nth-value 1 (call "attachments_remove" "employee:anna" "id" file))))
        (call-ok "attachments_remove" "admin:ada" "id" file)))))

(test a-record-the-caller-may-not-see-is-not-found
  (with-postgres-app ()
    (let* ((karis (jget (call-ok "own_notes_create" "employee:kari" "title" "Karis") "id"))
           (file (first-file-id (add-file "employee:kari" "own_note" karis))))
      (dolist (code (list (nth-value 1 (add-file "employee:ola" "own_note" karis))
                          (nth-value 1 (call "attachments_list" "employee:ola" "entity" "own_note"
                                             "record_id" karis))
                          (nth-value 1 (call "attachments_remove" "employee:ola" "id" file))
                          (nth-value 1 (add-file "employee:ola" "own_note" "ont_finnes_ikke"))
                          (nth-value 1 (call "attachments_remove" "employee:ola"
                                             "id" "fil_finnes_ikke"))))
        (is (string= "not_found" code)))
      (is (= 1 (jget (call-ok "attachments_list" "admin:ada" "entity" "own_note"
                              "record_id" karis)
                     "returned"))))))

(test a-file-of-an-entity-no-longer-taking-files-is-no-ones
  (with-test-app ()
    (let* ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "Snart uten") "id"))
           (file (first-file-id (add-file "employee:anna" "file_note" id)))
           (class (find-class 'file-note))
           (option (entity-attachments class)))
      (unwind-protect
           (progn
             (setf (entity-attachments class) nil)
             (is (string= "not_found"
                          (nth-value 1 (call "attachments_remove" "admin:ada" "id" file))))
             (with-application (*app*)
               (with-actor ((parse-actor "admin:ada"))
                 (is (null (with-transaction (:read) (tun.files:servable-attachment file)))))))
        (setf (entity-attachments class) option))
      (with-application (*app*)
        (with-actor ((system-actor "test"))
          (with-transaction (:write)
            (let ((attachment (fetch 'tun.files:attachment file)))
              (setf (tun.files:attachment-entity attachment) "gone_note")
              (save attachment))))
        (with-actor ((parse-actor "admin:ada"))
          (is (null (with-transaction (:read) (tun.files:servable-attachment file)))
              "an entity the code does not define"))))))

;;; ------------------------------------------------------------------
;;; 9. The FILES type in an operation, and what requests keep (spec/files.md 4.1)

(defun longest-string (value)
  "The length of the longest string anywhere in VALUE, JSON or a list."
  (cond ((stringp value) (length value))
        ((hash-table-p value)
         (loop for v being the hash-values of value maximize (longest-string v)))
        ((consp value) (max (longest-string (car value)) (longest-string (cdr value))))
        ((and (vectorp value) (not (stringp value)))
         (loop for v across value maximize (longest-string v)))
        (t 0)))

(defun record-strings (record)
  "Every string reachable from RECORD's slots."
  (let ((strings '()))
    (labels ((walk (value)
               (cond ((stringp value) (push value strings))
                     ((hash-table-p value) (maphash (lambda (k v) (walk k) (walk v)) value))
                     ((consp value) (walk (car value)) (walk (cdr value)))
                     ((and (vectorp value) (not (stringp value))) (map nil #'walk value))
                     ((typep value 'standard-object)
                      (dolist (slot (closer-mop:class-slots (class-of value)))
                        (let ((name (closer-mop:slot-definition-name slot)))
                          (when (slot-boundp value name) (walk (slot-value value name)))))))))
      (walk record))
    strings))

(test an-operation-stores-a-record-and-its-files-together
  (with-test-app ()
    (multiple-value-bind (json code)
        (call-files "employee:anna" (file-json "ok.png" (fixture "skjermbilde.png"))
                    (file-json "feil.png" (bytes "ikke et bilde")))
      (is (string= "invalid_input" code))
      (is (equal "screenshots[1]" (jget (aref (jget (jget json "error") "fields") 0) "field")))
      (with-application (*app*)
        (with-actor ((system-actor "test"))
          (is (null (with-transaction (:read) (select 'file-note))) "no note")
          (is (null (with-transaction (:read) (select 'tun.files:attachment))) "no file"))))
    (let ((note (call-ok "file_notes_create" "employee:anna" "title" "Med to"
                         "screenshots" (files-json "a.png" (fixture "skjermbilde.png")
                                                   "b.jpg" (fixture "foto.jpg")))))
      (is (= 2 (jget (call-ok "attachments_list" "viewer:vera" "entity" "file_note"
                              "record_id" (jget note "id"))
                     "returned"))))))

(test a-request-record-keeps-a-file-as-its-name-and-size
  (with-test-server (port)
    (let* ((png (fixture "skjermbilde.png"))
           (encoded (base64 png)))
      (multiple-value-bind (result error)
          (http-tool-call port "employee:anna" "file_notes_create"
                          (jobj "title" "Over MCP" "screenshots" (files-json "skjerm.png" png)))
        (declare (ignore result))
        (is (not error)))
      (let ((record (find "file_notes_create" (finished-requests)
                          :key #'request-tool :test #'equal)))
        (is-true record)
        (is (equalp (jarr (list (jobj "filename" "skjerm.png" "bytes" (length png))))
                    (jget (request-input-json record) "screenshots")))
        (is (notany (lambda (s) (search (subseq encoded 0 200) s)) (record-strings record))
            "no string in the record holds the base64")
        (is (not (search (subseq encoded 0 200) (to-json-string (request-input-json record))))
            "nor its kept input")
        (is (< (longest-string (request-input-json record)) 1000))))))

(test a-fault-keeps-no-input-and-no-content
  (with-test-app ()
    (let* ((png (fixture "skjermbilde.png"))
           (encoded (base64 png)))
      (handler-case (call "file_notes_explode" "employee:anna"
                          "screenshots" (files-json "skjerm.png" png))
        (error () nil))
      (with-application (*app*)
        (with-actor ((system-actor "test"))
          (with-transaction (:read)
            (let ((stored (append (select 'tun.errors:error-group)
                                  (select 'tun.errors:error-occurrence))))
              (is-true stored "the fault was recorded")
              (is (notany (lambda (s) (search (subseq encoded 0 100) s))
                          (mapcan (lambda (row) (record-strings (entity->json row))) stored))
                  "nothing of the file"))))))))

;;; ------------------------------------------------------------------
;;; 10. Fetching a file (spec/files.md 5.2, 5.3)

(defun fetch-file (port path &key actor (method :get) headers)
  "Values the status, the body's octets and the headers of METHOD on PATH,
as ACTOR (claimed identity) when given."
  (multiple-value-bind (body status response-headers)
      (drakma:http-request (format nil "http://127.0.0.1:~d~a" port path)
                           :method method :redirect nil :force-binary t
                           :additional-headers (append (and actor (list (cons "X-Tun-Actor" actor)))
                                                       headers))
    (values status body response-headers)))

(defun page-text (octets)
  "OCTETS, a page, as text without its numbered element ids, which differ
from one rendering to the next."
  (cl-ppcre:regex-replace-all "-[0-9]+\\b" (sb-ext:octets-to-string octets :external-format :utf-8)
                              ""))

(defun response-header (name headers)
  (cdr (assoc name headers)))

(defun attach-over-api (actor entity id &rest names-and-octets)
  "Attach NAMES-AND-OCTETS to the record and return the files' JSON."
  (coerce (jget (call-ok "attachments_add" actor "entity" entity "record_id" id
                         "files" (apply #'files-json names-and-octets))
                "items")
          'list))

(test a-file-is-served-inert-to-who-may-see-its-record
  (with-test-server (port)
    (let* ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "Hent") "id"))
           (files (attach-over-api "employee:anna" "file_note" id
                                   "skjermbilde.png" (fixture "skjermbilde.png")
                                   "kvittering ø.pdf" (fixture "kvittering.pdf")))
           (png-url (jget (first files) "url"))
           (pdf-url (jget (second files) "url")))
      (multiple-value-bind (status body headers) (fetch-file port png-url :actor "viewer:vera")
        (is (= 200 status))
        (is (equalp (fixture "skjermbilde.png") body))
        (is (equal "image/png" (response-header :content-type headers)))
        (is (equal (princ-to-string (length body)) (response-header :content-length headers)))
        (is (equal "inline; filename=\"skjermbilde.png\"; filename*=UTF-8''skjermbilde.png"
                   (response-header :content-disposition headers)))
        (is (equal "nosniff" (response-header :x-content-type-options headers)))
        (is (equal "default-src 'none'; style-src 'unsafe-inline'; sandbox; frame-ancestors 'none'"
                   (response-header :content-security-policy headers)))
        (is (equal "same-origin" (response-header :cross-origin-resource-policy headers)))
        (is (equal "no-referrer" (response-header :referrer-policy headers)))
        (is (equal "private, no-cache" (response-header :cache-control headers)))
        (let ((etag (response-header :etag headers)))
          (is (equal (format nil "\"~a\"" (ironclad:byte-array-to-hex-string
                                           (ironclad:digest-sequence :sha256 body)))
                     etag))
          (multiple-value-bind (status body) (fetch-file port png-url :actor "viewer:vera"
                                                         :headers `(("If-None-Match" . ,etag)))
            (is (= 304 status))
            (is (zerop (length body))))))
      (multiple-value-bind (status body headers) (fetch-file port pdf-url :actor "viewer:vera")
        (is (= 200 status))
        (is (equalp (fixture "kvittering.pdf") body))
        (is (equal (concatenate 'string "attachment; filename=\"kvittering _.pdf\"; "
                                "filename*=UTF-8''kvittering%20%C3%B8.pdf")
                   (response-header :content-disposition headers))))
      (multiple-value-bind (status body headers)
          (fetch-file port png-url :actor "viewer:vera" :method :head)
        (is (= 200 status))
        (is (zerop (length body)))
        (is (equal "image/png" (response-header :content-type headers))))
      (is (= 401 (fetch-file port png-url)) "no caller")
      (let ((unknown (fetch-file port "/files/fil_finnes_ikke" :actor "viewer:vera")))
        (is (= 404 unknown)))
      (with-application (*app*)
        (with-actor ((system-actor "test"))
          (with-transaction (:write) (delete-entity (fetch 'file-note id)))))
      (multiple-value-bind (status body) (fetch-file port png-url :actor "viewer:vera")
        (is (= 404 status))
        (is (equal (page-text body)
                   (page-text (nth-value 1 (fetch-file port "/files/fil_finnes_ikke"
                                                       :actor "viewer:vera"))))
            "a deleted record's file and an unknown id get the same answer")))))

(test an-access-token-fetches-a-file
  (with-test-server (port :identity :authenticated)
    (let* ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "Token") "id"))
           (url (jget (first (attach-over-api "employee:anna" "file_note" id
                                              "a.png" (fixture "skjermbilde.png")))
                      "url"))
           (token (make-token (make-account "files-agent" "agent" "employee"))))
      (is (= 401 (fetch-file port url)))
      (is (= 200 (fetch-file port url
                             :headers `(("Authorization" . ,(format nil "Bearer ~a" token)))))))))

(test others-get-the-same-404-as-for-a-file-that-is-not-there
  (if (not (postgres-available-p))
      (skip "no Postgres")
      (with-test-server (port :db (scratch-postgres "files"))
        (let* ((karis (jget (call-ok "own_notes_create" "employee:kari" "title" "Karis") "id"))
               (url (jget (first (attach-over-api "employee:kari" "own_note" karis
                                                  "a.png" (fixture "skjermbilde.png")))
                          "url")))
          (is (= 200 (fetch-file port url :actor "employee:kari")))
          (is (= 200 (fetch-file port url :actor "admin:ada")))
          (multiple-value-bind (status body) (fetch-file port url :actor "employee:ola")
            (is (= 404 status))
            (is (equal (page-text body)
                       (page-text (nth-value 1 (fetch-file port "/files/fil_finnes_ikke"
                                                           :actor "employee:ola"))))))))))

(test a-page-cannot-take-the-files-prefix
  (unwind-protect
       (progn
         (tun.web:register-staff-page "files" (lambda (&rest arguments)
                                                (declare (ignore arguments))
                                                nil))
         (signals extension-error (tun.web:check-http-route-conflicts)))
    (remhash "files" tun.web::*staff-pages*)))

;;; ------------------------------------------------------------------
;;; 14. Sending in parts (spec/files.md 5.4)

(defun content-reads (method id)
  "The content reads the last METHOD request for the file ID made, each as the
store described it, READ CONTENT ID START LENGTH."
  (let ((record (find (format nil "web:~a /files/~a" method id) (finished-requests)
                      :key #'request-tool :test #'equal)))
    (loop for step across (request-steps record)
          for detail = (trace-step-detail step)
          when (and (stringp detail) (string-prefix-p "READ CONTENT" detail))
          collect detail)))

(test a-file-is-read-and-sent-a-part-at-a-time
  (with-test-server (port)
    (let* ((large (large-png (- (* 10 1024 1024) 20000)))
           (stored (tun.files:examine-file large))
           (id (jget (call-ok "file_notes_create" "employee:anna" "title" "Stor") "id"))
           (file (jget (first (attach-over-api "employee:anna" "file_note" id "stor.png" large))
                       "id")))
      (multiple-value-bind (status body headers) (fetch-file port (format nil "/files/~a" file)
                                                             :actor "viewer:vera")
        (is (= 200 status))
        (is (equalp stored body))
        (is (> (length body) (* 9 1024 1024)) "a file kept whole, of about 10 MiB")
        (let ((reads (content-reads :get file)))
          (is (= (ceiling (length stored) (* 1024 1024)) (length reads)))
          (is (every (lambda (read) (search (format nil " ~d" (* 1024 1024)) read)) reads)
              "parts of at most 1 MiB: ~s" reads))
        (let ((etag (response-header :etag headers)))
          (fetch-file port (format nil "/files/~a" file) :actor "viewer:vera" :method :head)
          (is (null (content-reads :head file)) "HEAD reads no content")
          (fetch-file port (format nil "/files/~a" file) :actor "viewer:vera"
                      :headers `(("If-None-Match" . ,etag)))
          (is (null (content-reads :get file)) "nor does a 304"))))))

(test a-file-deleted-while-it-is-sent-ends-short
  (with-test-server (port)
    (let* ((large (large-png (* 5 1024 1024)))
           (id (jget (call-ok "file_notes_create" "employee:anna" "title" "Slettes") "id"))
           (file (jget (first (attach-over-api "employee:anna" "file_note" id "s.png" large)) "id"))
           (socket (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8)))
           (stream (usocket:socket-stream socket)))
      (unwind-protect
           (progn
             (write-sequence (sb-ext:string-to-octets
                              (crlf (format nil "GET /files/~a HTTP/1.1" file) "Host: x"
                                    "X-Tun-Actor: viewer:vera" "")
                              :external-format :latin-1)
                             stream)
             (finish-output stream)
             ;; Read the headers and a little, then delete the record.
             (let ((start (make-array 1000 :element-type '(unsigned-byte 8))))
               (read-sequence start stream))
             (with-application (*app*)
               (with-actor ((system-actor "test"))
                 (with-transaction (:write) (delete-entity (fetch 'file-note id)))))
             (let ((rest 0))
               (handler-case (loop while (read-byte stream nil nil) do (incf rest))
                 (error () nil))
               (is (< (+ rest 1000) (length large)) "the answer ends before its length")))
        (usocket:socket-close socket)))))

(test a-reader-that-stops-is-cut-off
  (let ((limit tun.web::*file-send-seconds*))
    (setf tun.web::*file-send-seconds* 2)          ; global: the server's threads read it
    (unwind-protect
         (with-test-server (port)
           (let* ((large (large-png (* 10 1000 1000)))
                  (id (jget (call-ok "file_notes_create" "employee:anna" "title" "Treg") "id"))
                  (file (jget (first (attach-over-api "employee:anna" "file_note" id "t.png" large))
                              "id"))
                  (socket (usocket:socket-connect "127.0.0.1" port
                                                  :element-type '(unsigned-byte 8)))
                  (stream (usocket:socket-stream socket)))
             (unwind-protect
                  (progn
                    (write-sequence (sb-ext:string-to-octets
                                     (crlf (format nil "GET /files/~a HTTP/1.1" file) "Host: x"
                                           "X-Tun-Actor: viewer:vera" "")
                                     :external-format :latin-1)
                                    stream)
                    (finish-output stream)
                    (sleep 4)               ; reads nothing for longer than the limit
                    (let ((got 0)
                          (start (get-internal-real-time)))
                      (handler-case (loop while (read-byte stream nil nil) do (incf got))
                        (error () nil))
                      (is (< got (length large)) "the connection was closed short of the file")
                      (is (< (/ (- (get-internal-real-time) start) internal-time-units-per-second)
                             3)
                          "and closed at once, not kept for another request")))
               (usocket:socket-close socket))))
      (setf tun.web::*file-send-seconds* limit))))

;;; ------------------------------------------------------------------
;;; 15. Storage, deleting and the sweep (spec/files.md 5.1)

(test every-octet-round-trips-through-postgres
  (with-postgres-app ()
    (with-actor ((system-actor "test"))
      (let ((octets (coerce (loop for i below 512 collect (mod i 256))
                            '(simple-array (unsigned-byte 8) (*)))))
        (with-transaction (:write) (store-write-content *store* "fil_bytes" octets))
        (with-transaction (:read)
          (is (equalp octets (store-read-content *store* "fil_bytes" 0 10000)))
          (is (equalp (subseq octets 100 200) (store-read-content *store* "fil_bytes" 100 100)))
          (is (zerop (length (store-read-content *store* "fil_bytes" 600 10))) "past the end")
          (is (null (store-read-content *store* "fil_ingen" 0 10))))))
    (let ((tables (store-describe-schema *store*)))
      (is (find-by "name" "attachments" tables))
      (let ((contents (find-by "name" "attachment_contents" tables)))
        (is-true contents)
        (is (equal "bytea" (jget (find-by "name" "content" (jget contents "columns")) "type")))))))

(test sqlite-refuses-files
  (with-test-app (:db (scratch-path "files"))
    (with-application (*app*)
      (let ((message (handler-case (with-actor ((system-actor "test"))
                                     (with-transaction (:write)
                                       (store-write-content *store* "fil_x" (bytes "x")))
                                     nil)
                       (error (e) (princ-to-string e)))))
        (is (search "Postgres" (or message "")))))))

(test deleting-a-record-deletes-its-files
  (with-test-app ()
    (let* ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "Slett") "id"))
           (file (jget (first (attach-over-api "employee:anna" "file_note" id
                                               "a.png" (fixture "skjermbilde.png")))
                       "id")))
      (with-application (*app*)
        (with-actor ((system-actor "test"))
          (ignore-errors                ; rolled back: the files stay
            (with-transaction (:write)
              (delete-entity (fetch 'file-note id))
              (error "rull tilbake")))
          (with-transaction (:read)
            (is (fetch 'tun.files:attachment file))
            (is (store-read-content *store* file 0 10)))
          (with-transaction (:write) (delete-entity (fetch 'file-note id)))
          (with-transaction (:read)
            (is (null (fetch 'tun.files:attachment file)))
            (is (null (store-read-content *store* file 0 10)))))))))

(test the-sweep-deletes-files-whose-record-is-gone
  (with-test-app ()
    (let* ((kept-id (jget (call-ok "file_notes_create" "employee:anna" "title" "Blir") "id"))
           (gone-id (jget (call-ok "file_notes_create" "employee:anna" "title" "Borte") "id"))
           (kept (jget (first (attach-over-api "employee:anna" "file_note" kept-id
                                               "a.png" (fixture "skjermbilde.png")))
                       "id"))
           (gone (jget (first (attach-over-api "employee:anna" "file_note" gone-id
                                               "b.png" (fixture "skjermbilde.png")))
                       "id"))
           (unknown (jget (first (attach-over-api "employee:anna" "file_note" kept-id
                                                  "c.png" (fixture "skjermbilde.png")))
                          "id")))
      (with-application (*app*)
        (with-actor ((system-actor "test"))
          (with-transaction (:write)
            ;; Behind the kernel's back: the record goes, its files stay.
            (let ((rows (tun.store.memory::table *store* 'file-note)))
              (setf (tun.store.memory::table *store* 'file-note)
                    (remove gone-id rows :key (lambda (entry) (gethash "id" (cdr entry)))
                            :test #'equal)))
            (let ((attachment (fetch 'tun.files:attachment unknown)))
              (setf (tun.files:attachment-entity attachment) "gone_note")
              (save attachment)))))
      (let ((schedule (find "attachments_sweep"
                            (coerce (jget (call-ok "schedules_list" "admin:ada") "items") 'list)
                            :key (lambda (s) (jget s "name")) :test #'equal)))
        (is-true schedule)
        (is (equal "30 3 * * *" (jget schedule "cron"))))
      (is (eq :succeeded (perform-job 'tun.files:attachments-sweep)))
      (with-application (*app*)
        (with-actor ((system-actor "test"))
          (with-transaction (:read)
            (is (fetch 'tun.files:attachment kept))
            (is (null (fetch 'tun.files:attachment gone)))
            (is (fetch 'tun.files:attachment unknown) "an entity the code does not define")))))))

;;; ------------------------------------------------------------------
;;; Malformed files never fail otherwise than as damaged (spec/files.md 2.1)

(test a-short-exif-segment-is-read-within-its-segment
  ;; An APP1 that states 4 octets, followed by what looks like Exif: the
  ;; walker reads a segment's content only.
  (let ((given (jpeg-with (fixture "foto.jpg")
                          (bytes #xFF #xE1 0 4 0 0 "Exif" 0 0 "MM"))))
    (is (member (file-refusal-of given) (list nil +damaged+ +type-refused+) :test #'equal))))

(defun mutations (octets random-state)
  "Fifty files made from OCTETS: cut off, with octets changed, and with
octets put in, at places RANDOM-STATE chooses."
  (flet ((place () (random (max 1 (length octets)) random-state))
         (octet () (random 256 random-state)))
    (loop repeat 50
          collect (let ((copy (copy-seq octets)))
                    (case (random 3 random-state)
                      (0 (subseq copy 0 (place)))
                      (1 (loop repeat (1+ (random 8 random-state))
                               do (setf (aref copy (place)) (octet)))
                         copy)
                      (t (let ((at (place)))
                           (bytes (subseq copy 0 at)
                                  (loop repeat (1+ (random 6 random-state)) collect (octet))
                                  (subseq copy at)))))))))

(test damaged-files-are-refused-and-never-crash-the-walk
  (let ((random-state (sb-ext:seed-random-state 4711))
        (originals (list (fixture "skjermbilde.png") (fixture "foto.jpg")
                         (jpeg-with (fixture "foto.jpg")
                                    (jpeg-segment #xE1 (exif-payload :orientation 6))
                                    (jfif-with-thumbnail))
                         (fixture "foto.webp") (fixture "gjennomsiktig.webp")
                         (gif-of 2 2 +gif-looping+ +gif-comment+ +gif-control+ (gif-image 2 2)
                                 +gif-text+ #x3B)
                         +minimal-pdf+))
        (unexpected '()))
    (dolist (original originals)
      (dolist (octets (mutations original random-state))
        (handler-case (tun.files:examine-file octets)
          (tun.files:file-refused () nil)
          (error (e) (push (princ-to-string e) unexpected)))))
    (is (null unexpected) "every mutation is taken or refused: ~{~a~^; ~}"
        (subseq unexpected 0 (min 3 (length unexpected))))))

(test a-large-jfif-thumbnail-is-taken-out-with-the-length-right
  (let* ((jpeg (fixture "foto.jpg"))
         (app0-end (+ 4 (tun.files::u16be jpeg 4)))
         (thumbnail (jpeg-segment #xE0 (bytes "JFIF" 0 1 2 0 0 1 0 1 10 10
                                              (make-array 300 :initial-element 128))))
         (stored (tun.files:examine-file (bytes (subseq jpeg 0 2) thumbnail
                                                (subseq jpeg app0-end)))))
    (is (equalp (bytes #xFF #xE0 0 16 "JFIF" 0 1 2 0 0 1 0 1 0 0) (subseq stored 2 20)))
    (is (equalp stored (tun.files:examine-file stored)) "it walks again as it is")))

(test base64-is-decoded-without-copies-and-measured-past-line-breaks
  (let* ((png (fixture "skjermbilde.png"))
         (encoded (base64 png)))
    (is (equalp png (tun.files:base64-octets encoded)))
    (is (equalp png (tun.files:base64-octets (format nil "~a~c~c" encoded #\Return #\Newline))))
    (is (= (length png) (tun.files::base64-length (format nil "~a~c~c" encoded #\Return #\Newline)))
        "a line break at the end does not hide the padding")
    (is (= (length png) (tun.files::base64-length encoded)))))

(test a-name-that-is-only-an-extension-gets-a-name
  (is (equal "file.png" (tun.files:stored-filename ".png" :png)))
  (is (equal "file.PDF" (tun.files:stored-filename " .PDF " :pdf))))

(test a-filename-star-is-escaped-as-rfc-5987-says
  (is (equal "a%27b%28c%29%2A%2C%20%C3%B8.png" (tun.web::rfc-5987-value "a'b(c)*, ø.png"))))

(test the-system-may-remove-a-file
  (with-test-app ()
    (let* ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "System") "id"))
           (file (first-file-id (add-file "employee:anna" "file_note" id))))
      (with-application (*app*)
        (with-actor ((system-actor "test"))
          (is (eq t (jget (tun.files:attachments-remove *app* (make-input (jobj "id" file)))
                          "removed"))))))))

;;; ------------------------------------------------------------------
;;; Many small pieces (spec/files.md 2.1): what a file costs to walk grows
;;; with its octets, and a file has at most 100 000 pieces.

(defun repeated (unit count)
  "UNIT, octets, COUNT times over, as one vector."
  (let ((octets (make-array (* count (length unit)) :element-type '(unsigned-byte 8))))
    (dotimes (i count octets)
      (replace octets unit :start1 (* i (length unit))))))

(defun many-piece-jpeg (count)
  "The JPEG fixture with COUNT more DRI segments, each kept."
  (jpeg-with (fixture "foto.jpg") (repeated (jpeg-segment #xDD (bytes 0 0)) count)))

(defun many-piece-png (count)
  "The PNG fixture with COUNT more gAMA chunks, each kept."
  (png-with (fixture "skjermbilde.png")
            :before-idat (list (repeated (png-chunk "gAMA" (u32 45455)) count))))

(defun many-piece-gif (count)
  "A GIF of COUNT graphic control extensions before its image."
  (gif-of 2 2 (repeated +gif-control+ count) (gif-image 2 2) #x3B))

(defun many-piece-webp (count)
  "The WebP fixture's image after COUNT empty ALPH chunks, each kept."
  (webp-of (riff-chunk "VP8X" (vp8x #x10 480 320)) (repeated (riff-chunk "ALPH" "") count)
           (riff-chunk "VP8 " (fixture-vp8))))

(test a-file-of-too-many-pieces-is-damaged
  (dolist (make (list #'many-piece-jpeg #'many-piece-png #'many-piece-gif #'many-piece-webp))
    (is (null (file-refusal-of (funcall make 99000))) "99 000 pieces are taken")
    (is (equal +damaged+ (file-refusal-of (funcall make 100001))) "100 001 are not")))

(test a-restart-marker-outside-a-scan-is-damaged
  (let ((jpeg (fixture "foto.jpg")))
    (dolist (marker '(#xD0 #xD7 #x01))
      (is (equal +damaged+ (file-refusal-of (jpeg-with jpeg (bytes #xFF marker))))))))

(test the-boundary-is-the-parameter-of-that-name
  (is (equal "abc" (tun.files:multipart-boundary "multipart/form-data; boundary=abc")))
  (is (equal "a b" (tun.files:multipart-boundary
                    "multipart/form-data; charset=x; boundary=\"a b\"")))
  (is (eq :refused (handler-case (tun.files:multipart-boundary "multipart/form-data; xboundary=abc")
                     (tun.files:multipart-refused () :refused)))
      "another parameter that ends in boundary is not it"))

;;; A file's data in a JSON body is set aside before the body is parsed
;;; (spec/files.md 4.3).

(defun json-escaped-base64 (octets)
  "OCTETS in base64 as a JSON string's content might write it: every / as
\\/ and a \\n every 76 characters."
  (with-output-to-string (out)
    (loop for char across (base64 octets)
          for i from 0
          do (when (and (plusp i) (zerop (mod i 76))) (write-string "\\n" out))
             (if (char= char #\/) (write-string "\\/" out) (write-char char out)))))

(test a-files-data-in-a-json-body-is-set-aside-before-it-is-parsed
  (with-test-server (port)
    (let* ((headers '(("X-Tun-Actor" . "employee:anna")))
           (png (padded-png (* 1100 1024)))
           (escaped (json-escaped-base64 png))
           (filler (make-string (* 900 1024) :initial-element #\x)))
      (flet ((call (title data &rest more)
               (multiple-value-bind (status text)
                   (post-octets port "/api/file_notes_create"
                                (sb-ext:string-to-octets
                                 (format nil "{\"title\": ~s, \"screenshots\": ~
                                              [{\"filename\": \"a.png\", \"data\": \"~a\"}]~
                                              ~{, \"~a\": ~s~}}"
                                         title data more)
                                 :external-format :utf-8)
                                :headers headers)
                 (values status (parse-json text)))))
        (is (< +mib+ (length escaped)) "the data is set aside: over 1 MiB of the body")
        (multiple-value-bind (status note) (call "Satt til side" escaped)
          (is (= 200 status) "stored, its escapes read: ~s" note)
          (let ((items (jget (parse-json
                              (nth-value 1 (post-octets port "/api/attachments_list"
                                                        (sb-ext:string-to-octets
                                                         (to-json-string
                                                          (jobj "entity" "file_note"
                                                                "record_id" (jget note "id")))
                                                         :external-format :utf-8)
                                                        :headers headers)))
                             "items")))
            (is (= (length (fixture "skjermbilde.png")) (jget (aref items 0) "size"))
                "the file as Tun keeps it")))
        (multiple-value-bind (status json)
            (call "Adresse" (concatenate 'string "data:image/png;base64," escaped))
          (is (= 422 status))
          (is (search "without “data:…;base64,” in front" (to-json-string json)) "a data URL"))
        (multiple-value-bind (status json) (call "Ugyldig" (concatenate 'string escaped "!"))
          (is (= 422 status))
          (is (search "not valid base64" (to-json-string json)) "base64 that is not"))
        (multiple-value-bind (status json)
            (call (make-string (* 1200 1024) :initial-element #\t) "")
          (is (= 413 status) "a long string set aside outside a file's data")
          (is (search "Only a file's content" (to-json-string json))))
        (multiple-value-bind (status json)
            (call "For mye" escaped "x" filler "y" filler "z" filler)
          (is (= 413 status) "more than 2 MiB besides the files' data")
          (is (search "Besides its files' content" (to-json-string json))))))))

;;; attachments-of, a record's files in a client's own operation (spec/files.md 4.2)

(test attachments-of-gives-a-records-files-as-the-tool-does
  (with-test-app ()
    (let* ((one (jget (call-ok "file_notes_create" "employee:anna" "title" "En") "id"))
           (two (jget (call-ok "file_notes_create" "employee:anna" "title" "To") "id"))
           (none (jget (call-ok "file_notes_create" "employee:anna" "title" "Ingen") "id")))
      (add-file "employee:anna" "file_note" one "a.png")
      (add-file "employee:anna" "file_note" one "b.pdf" (fixture "kvittering.pdf"))
      (add-file "employee:anna" "file_note" two "c.png")
      (let ((listed (coerce (jget (call-ok "attachments_list" "viewer:vera" "entity" "file_note"
                                           "record_id" one)
                                  "items")
                            'list)))
        (with-application (*app*)
          (with-actor ((make-actor :viewer "vera"))
            (with-transaction (:read)
              (let ((records (mapcar (lambda (id) (fetch 'file-note id)) (list one two none))))
                (is (equal (mapcar #'to-json-string listed)
                           (mapcar #'to-json-string (tun:attachments-of (first records))))
                    "the same objects as attachments_list, in the order added, through TUN")
                (let ((table (tun.files:attachments-of records)))
                  (is (equal '("a.png" "b.pdf") (mapcar (lambda (a) (jget a "filename"))
                                                        (gethash one table))))
                  (is (equal '("c.png") (mapcar (lambda (a) (jget a "filename"))
                                                (gethash two table))))
                  (is (equal '() (gethash none table)))
                  (is (= 3 (hash-table-count table))))
                (is (= 0 (hash-table-count (tun.files:attachments-of '()))) "an empty list, an empty table")
                (signals error (tun.files:attachments-of (make-instance 'file-note :title "Ulagret")))
                (signals error (tun.files:attachments-of (list (first records)
                                                     (make-instance 'locked-note :title "Annen")))))))))
      (with-application (*app*)
        (with-actor ((system-actor "test"))
          (with-transaction (:write)
            (let ((plain (insert (make-instance 'plain-note :title "Uten filer"))))
              (signals error (tun.files:attachments-of plain))
              (signals error (tun.files:attachments-of (list plain))))))))))

(test attachments-of-reads-the-records-again-as-the-caller
  (with-postgres-app ()
    (let ((karis (jget (call-ok "own_notes_create" "employee:kari" "title" "Karis") "id")))
      (add-file "employee:kari" "own_note" karis)
      (with-application (*app*)
        (with-transaction (:read)
          (let ((record (with-actor ((system-actor "test")) (fetch 'own-note karis))))
            (with-actor ((make-actor :employee "ola"))
              (is (null (tun.files:attachments-of record))
                  "read as the system actor, still not Ola's to see")
              (is (equal '() (gethash karis (tun.files:attachments-of (list record))))))
            (with-actor ((make-actor :employee "kari"))
              (is (= 1 (length (tun.files:attachments-of record))) "Kari's own"))))))))

(test attachments-of-gives-nothing-of-a-record-the-caller-may-not-read
  (with-test-app ()
    (let ((id (jget (call-ok "admin_notes_create" "admin:ada" "title" "Bare for admin") "id")))
      (add-file "admin:ada" "admin_note" id)
      (with-application (*app*)
        (with-transaction (:read)
          (let ((record (with-actor ((system-actor "test")) (fetch 'admin-note id))))
            (with-actor ((make-actor :employee "anna"))
              (is (null (tun:attachments-of record))
                  "no read operation admits an employee: entity-readable-p keeps it")
              (is (equal '() (gethash id (tun:attachments-of (list record))))))
            (with-actor ((make-actor :admin "ada"))
              (is (= 1 (length (tun:attachments-of record)))))))))))

(test attachments-of-reads-a-batch-with-two-statements
  (with-postgres-app ()
    (let ((ids (loop for title in '("En" "To" "Tre" "Fire" "Fem")
                     collect (jget (call-ok "own_notes_create" "employee:kari" "title" title) "id"))))
      (dolist (id ids)
        (add-file "employee:kari" "own_note" id))
      (with-application (*app*)
        (with-actor ((make-actor :employee "kari"))
          (let ((records (with-transaction (:read)
                           (mapcar (lambda (id) (fetch 'own-note id)) ids))))
            (with-request-record (:force-new t)
              (with-transaction (:read)
                (let* ((before (request-store-statements *request-record*))
                       (table (tun:attachments-of records)))
                  (is (= 5 (count-if (lambda (id) (= 1 (length (gethash id table)))) ids)))
                  (is (= 2 (- (request-store-statements *request-record*) before))
                      "two statements for five records, not one per record"))))))))))
