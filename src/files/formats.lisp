;;;; files/formats.lisp -- what Tun takes of an uploaded file (spec/files.md
;;;; 2, 3): its type decided by its bytes, its structure walked to its end,
;;;; its size read from its header, and its metadata taken out.
;;;;
;;;; Each format is walked by the lengths it states: PNG's chunks, JPEG's
;;;; segments, WebP's RIFF chunks and GIF's blocks and sub-blocks.  What is
;;;; kept is listed, and copied byte for byte; everything else is dropped.
;;;; Nothing here inflates, decodes or re-encodes image data, and nothing
;;;; calls another program: a file is only ever read as a sequence of
;;;; lengths and names.

(in-package #:tun.files)

(declaim (optimize (safety 3) (debug 2)))

(deftype octets () '(simple-array (unsigned-byte 8) (*)))

(define-condition file-refused (error)
  ((message :initarg :message :reader file-refused-message))
  (:report (lambda (c s) (write-string (file-refused-message c) s)))
  (:documentation "A file Tun does not take; MESSAGE says why, in Norwegian."))

(defun refuse-file (control &rest arguments)
  (error 'file-refused :message (apply #'format nil control arguments)))

(defparameter +type-refused+
  "Filtypen er ikke tillatt. Tillatt er PNG, JPEG, WebP, GIF og PDF.")

(defparameter +damaged+ "Bildet er skadet eller ufullstendig.")

(defun damaged ()
  (refuse-file +damaged+))

;;; ------------------------------------------------------------------
;;; Bounds (spec/files.md 2.2)

(defparameter +most-file-octets+ (* 10 1024 1024) "The largest file, after decoding.")
(defparameter +most-call-octets+ (* 25 1024 1024) "The most octets one call's files hold.")
(defparameter +most-side+ 30000 "The widest and tallest image or frame, in pixels.")
(defparameter +most-pixels+ 50000000 "The most pixels in an image or a frame.")

(defun check-pixels (width height)
  "Refuse an image or frame of WIDTH × HEIGHT pixels past the bounds."
  (when (or (> width +most-side+) (> height +most-side+) (> (* width height) +most-pixels+))
    (refuse-file "Bildet er for stort: høyst 30 000 piksler på hver side og 50 megapiksler.")))

;;; ------------------------------------------------------------------
;;; Reading octets

(defun u16be (octets at) (logior (ash (aref octets at) 8) (aref octets (1+ at))))
(defun u32be (octets at) (logior (ash (u16be octets at) 16) (u16be octets (+ at 2))))
(defun u16le (octets at) (logior (aref octets at) (ash (aref octets (1+ at)) 8)))
(defun u24le (octets at) (logior (u16le octets at) (ash (aref octets (+ at 2)) 16)))
(defun u32le (octets at) (logior (u16le octets at) (ash (u16le octets (+ at 2)) 16)))

(defun octets-of (string)
  "STRING, of ASCII characters, as octets."
  (map 'octets #'char-code string))

(defun octets-at-p (octets at expected)
  "True when OCTETS holds EXPECTED, a string of ASCII characters or octets, at AT."
  (let ((expected (if (stringp expected) (octets-of expected) expected)))
    (and (<= (+ at (length expected)) (length octets))
         (not (mismatch octets expected :start1 at :end1 (+ at (length expected)))))))

(defun need (octets end)
  "Refuse OCTETS as damaged unless it holds at least END octets."
  (when (> end (length octets))
    (damaged)))

(defun join-octets (parts)
  "PARTS, a list of octet vectors, as one."
  (let ((joined (make-array (reduce #'+ parts :key #'length) :element-type '(unsigned-byte 8)))
        (at 0))
    (dolist (part parts joined)
      (replace joined part :start1 at)
      (incf at (length part)))))

(defun part (octets start end)
  (subseq octets start end))

;;; What is kept of a file is copied into one buffer as it is walked, never
;;; collected as a part per chunk or segment: a file of a million tiny
;;; segments must cost what its octets cost, not a million objects.

(defparameter +most-pieces+ 100000
  "The most chunks, segments or blocks one file may have; more is damaged.")

(defun make-output (octets)
  "A buffer for what is kept of OCTETS: never longer than they are."
  (make-array (length octets) :element-type '(unsigned-byte 8) :fill-pointer 0))

(defun keep (output octets start end)
  "Copy OCTETS from START to END to the end of OUTPUT."
  (let ((at (fill-pointer output)))
    (setf (fill-pointer output) (+ at (- end start)))
    (replace output octets :start1 at :start2 start :end2 end)))

(defun output-octets (output &optional header)
  "What OUTPUT holds, after HEADER when given, as one simple vector."
  (let* ((offset (length (or header #())))
         (octets (make-array (+ offset (fill-pointer output)) :element-type '(unsigned-byte 8))))
    (when header (replace octets header))
    (replace octets output :start1 offset)
    octets))

(defun count-piece (count)
  "COUNT, the pieces walked so far, plus one; refuses a file of too many."
  (if (>= count +most-pieces+) (damaged) (1+ count)))

;;; ------------------------------------------------------------------
;;; The type (spec/files.md 2.1)

(defun file-type (octets)
  "The type OCTETS' first bytes name: :PNG, :JPEG, :WEBP, :GIF or :PDF, else NIL."
  (cond ((octets-at-p octets 0 #(#x89 #x50 #x4E #x47 #x0D #x0A #x1A #x0A)) :png)
        ((octets-at-p octets 0 #(#xFF #xD8 #xFF)) :jpeg)
        ((and (octets-at-p octets 0 "RIFF") (octets-at-p octets 8 "WEBP")) :webp)
        ((or (octets-at-p octets 0 "GIF87a") (octets-at-p octets 0 "GIF89a")) :gif)
        ((octets-at-p octets 0 "%PDF-") :pdf)))

(defparameter +content-types+
  '((:png . "image/png") (:jpeg . "image/jpeg") (:webp . "image/webp") (:gif . "image/gif")
    (:pdf . "application/pdf")))

(defun content-type-of (type)
  "The Content-Type a file of TYPE, a keyword of FILE-TYPE, is served as."
  (cdr (assoc type +content-types+)))

(defparameter +extensions+
  '((:png "png") (:jpeg "jpg" "jpeg") (:webp "webp") (:gif "gif") (:pdf "pdf"))
  "Each type's extensions, the first the one added to a name without one.")

;;; ------------------------------------------------------------------
;;; PNG (spec/files.md 2.1, 3)

(defparameter +png-kept+
  '("IHDR" "PLTE" "IDAT" "IEND" "tRNS" "cHRM" "gAMA" "iCCP" "sBIT" "sRGB" "cICP" "bKGD"
    "pHYs" "acTL" "fcTL" "fdAT")
  "The chunks a stored PNG keeps: the critical ones, colour and pixel size, and APNG's.")

(defun chunk-name (octets at)
  (map 'string #'code-char (subseq octets at (+ at 4))))

(defun critical-chunk-p (name)
  "A chunk a decoder must understand: its name starts with an upper-case letter."
  (upper-case-p (char name 0)))

(defun walk-png (octets)
  "Values the PNG OCTETS with only +PNG-KEPT+'s chunks, its width and height."
  (let ((at 8) (output (make-output octets)) (pieces 0) (width nil) (height nil) (data nil))
    (keep output octets 0 8)
    (loop
     (need octets (+ at 8))
     (setf pieces (count-piece pieces))
     (let* ((length (u32be octets at))
            (name (chunk-name octets (+ at 4)))
            (end (+ at 12 length)))
       (need octets end)
       (cond ((null width)
              (unless (and (string= name "IHDR") (= length 13)) (damaged))
              (setf width (u32be octets (+ at 8)) height (u32be octets (+ at 12))))
             ((string= name "IHDR") (damaged))
             ((and (critical-chunk-p name) (not (member name +png-kept+ :test #'string=)))
              (damaged)))
       (when (and (string= name "fcTL") (>= length 12))
         (check-pixels (u32be octets (+ at 12)) (u32be octets (+ at 16))))
       (when (string= name "IDAT") (setf data t))
       (when (member name +png-kept+ :test #'string=)
         (keep output octets at end))
       (setf at end)
       (when (string= name "IEND")
         (unless data (damaged))
         (return (values (output-octets output) width height)))))))

;;; ------------------------------------------------------------------
;;; JPEG (spec/files.md 2.1, 3)

(defun frame-marker-p (marker)
  "A start of frame, SOF0 to SOF15, but not DHT (C4), JPG (C8) or DAC (CC)."
  (and (<= #xC0 marker #xCF) (not (member marker '(#xC4 #xC8 #xCC)))))

(defun restart-marker-p (marker)
  (<= #xD0 marker #xD7))

(defun scan-end (octets at)
  "Where the entropy-coded data from AT ends: the next marker that is not a
stuffed zero or a restart.  Refuses a scan that runs to the end of OCTETS."
  (loop for i from at below (1- (length octets))
        when (and (= (aref octets i) #xFF)
                  (let ((next (aref octets (1+ i))))
                    (not (or (zerop next) (= next #xFF) (restart-marker-p next)))))
        do (return i)
        finally (damaged)))

(defun exif-orientation (payload)
  "The orientation, 1 to 8, in PAYLOAD, an Exif APP1's content after
\"Exif\\0\\0\": a TIFF header and its first IFD.  NIL when it is not
there or cannot be read (spec/files.md 3)."
  (when (>= (length payload) 8)
    (let ((big (cond ((octets-at-p payload 0 "MM") t)
                     ((octets-at-p payload 0 "II") nil)
                     (t (return-from exif-orientation nil)))))
      (flet ((u16 (at) (if big (u16be payload at) (u16le payload at)))
             (u32 (at) (if big (u32be payload at) (u32le payload at))))
        (unless (= (u16 2) 42) (return-from exif-orientation nil))
        (let ((ifd (u32 4)))
          (when (> (+ ifd 2) (length payload)) (return-from exif-orientation nil))
          (let ((count (u16 ifd)))
            (when (> (+ ifd 2 (* 12 count)) (length payload))
              (return-from exif-orientation nil))
            (loop for i below count
                  for entry = (+ ifd 2 (* 12 i))
                  when (= (u16 entry) #x0112)
                  do (return (and (= (u16 (+ entry 2)) 3) (= (u32 (+ entry 4)) 1)
                                  (let ((value (u16 (+ entry 8))))
                                    (and (<= 1 value 8) value)))))))))))

(defun orientation-segment (orientation)
  "A minimal Exif APP1 segment holding only ORIENTATION, big-endian."
  (coerce (list #xFF #xE1 0 34
                ;; "Exif\0\0", then the TIFF header "MM", 42 and IFD0 at 8
                #x45 #x78 #x69 #x66 0 0 #x4D #x4D 0 #x2A 0 0 0 8
                ;; one entry: tag 0x0112, type SHORT, count 1, the value
                0 1 #x01 #x12 0 3 0 0 0 1 0 orientation 0 0
                ;; no next IFD
                0 0 0 0)
          'octets))

(defparameter +exif-start+ (coerce '(#x45 #x78 #x69 #x66 0 0) 'octets) "Exif\\0\\0")
(defparameter +jfif-start+ (coerce '(#x4A #x46 #x49 #x46 0) 'octets) "JFIF\\0")
(defparameter +icc-start+ (concatenate 'octets (octets-of "ICC_PROFILE") (list 0)) "ICC_PROFILE\\0")

(defun jfif-segment (payload)
  "The JFIF APP0 whose content is PAYLOAD, without the thumbnail it may
carry, or NIL when it is not JFIF."
  (when (and (octets-at-p payload 0 +jfif-start+) (>= (length payload) 14))
    ;; The marker, the length 16, then JFIF's fixed 14 octets with a 0 × 0
    ;; thumbnail.
    (let ((segment (join-octets (list (coerce '(#xFF #xE0 0 16) 'octets) (part payload 0 14)))))
      (setf (aref segment 16) 0 (aref segment 17) 0)
      segment)))

(defun kept-app-segment-p (marker payload)
  "True for the APPn segments with content PAYLOAD a stored JPEG keeps
besides JFIF: an ICC profile in APP2 and Adobe's colour segment in APP14."
  (case marker
    (#xE2 (octets-at-p payload 0 +icc-start+))
    (#xEE (octets-at-p payload 0 "Adobe"))
    (t nil)))

(defun walk-jpeg (octets)
  "Values the JPEG OCTETS with only the segments spec/files.md 3 keeps, its
width and height as shown (turned by its orientation), and the orientation."
  (let ((at 2) (jfif nil) (output (make-output octets)) (pieces 0) (frame nil) (scan nil)
        (width 0) (height 0) (exif-count 0) (orientation nil))
    (loop
     (need octets (+ at 2))
     (unless (= (aref octets at) #xFF) (damaged))
     ;; Fill bytes: any number of FF before the marker.
     (loop while (and (< (1+ at) (length octets)) (= (aref octets (1+ at)) #xFF))
           do (incf at))
     (need octets (+ at 2))
     (setf pieces (count-piece pieces))
     (let ((marker (aref octets (1+ at))))
       (cond
         ((= marker #xD9)
          (unless (and frame scan) (damaged))
          (keep output octets at (+ at 2))
          (let ((exif (and (= exif-count 1) orientation (/= orientation 1)
                           (list (orientation-segment orientation)))))
            (return (values (output-octets output
                                           (join-octets (append (list (coerce '(#xFF #xD8) 'octets))
                                                                (and jfif (list jfif))
                                                                exif)))
                            (if (and exif (>= orientation 5)) height width)
                            (if (and exif (>= orientation 5)) width height)))))
         ;; A restart or TEM belongs inside a scan; SOI and a zero are no marker here.
         ((or (= marker 1) (restart-marker-p marker) (zerop marker) (= marker #xD8))
          (damaged))
         (t
          (need octets (+ at 4))
          (let* ((length (u16be octets (+ at 2)))
                 (end (+ at 2 length)))
            (when (< length 2) (damaged))
            (need octets end)
            (cond
              ((frame-marker-p marker)
               (when (or frame (< length 8)) (damaged))
               (setf frame t
                     height (u16be octets (+ at 5))
                     width (u16be octets (+ at 7)))
               (when (or (zerop width) (zerop height)) (damaged))
               (check-pixels width height)
               (keep output octets at end))
              ((= marker #xDA)
               (unless frame (damaged))
               (setf scan t)
               (let ((data-end (scan-end octets end)))
                 (keep output octets at data-end)
                 (setf end data-end)))
              ((= marker #xDC) (damaged))             ; DNL: a height after the scan
              ((member marker '(#xC4 #xCC #xDB #xDD)) ; DHT, DAC, DQT, DRI
               (keep output octets at end))
              ;; What an APPn segment is, read from its own content only.
              ((= marker #xE0)
               (when (and (null jfif) (zerop (fill-pointer output)))
                 (setf jfif (jfif-segment (part octets (+ at 4) (min end (+ at 18)))))))
              ((and (= marker #xE1) (octets-at-p (part octets (+ at 4) (min end (+ at 10)))
                                                 0 +exif-start+))
               (incf exif-count)
               (setf orientation (exif-orientation (part octets (+ at 10) end))))
              ((kept-app-segment-p marker (part octets (+ at 4) (min end (+ at 16))))
               (keep output octets at end)))
            (setf at end))))))))

;;; ------------------------------------------------------------------
;;; WebP (spec/files.md 2.1, 3)

(defparameter +webp-kept+ '("VP8 " "VP8L" "VP8X" "ALPH" "ANIM" "ANMF" "ICCP")
  "The chunks a stored WebP keeps.")

(defun webp-image-size (name octets at length)
  "Values the width and height a VP8 or VP8L chunk's data at AT gives."
  (cond ((string= name "VP8 ")
         (unless (and (>= length 10) (octets-at-p octets (+ at 3) #(#x9D #x01 #x2A))) (damaged))
         (values (logand (u16le octets (+ at 6)) #x3FFF) (logand (u16le octets (+ at 8)) #x3FFF)))
        (t
         (unless (and (>= length 5) (= (aref octets at) #x2F)) (damaged))
         (let ((bits (u32le octets (+ at 1))))
           (values (1+ (logand bits #x3FFF)) (1+ (logand (ash bits -14) #x3FFF)))))))

(defun walk-webp (octets)
  "Values the WebP OCTETS with only +WEBP-KEPT+'s chunks, its width and height."
  (need octets 12)
  (let ((end (+ 8 (u32le octets 4)))
        (at 12) (output (make-output octets)) (pieces 0) (width nil) (height nil) (image nil))
    (need octets end)
    (keep output octets 0 12)
    (loop while (< at end)
          do (need octets (+ at 8))
             (setf pieces (count-piece pieces))
             (let* ((name (chunk-name octets at))
                    (length (u32le octets (+ at 4)))
                    (data (+ at 8))
                    (next (+ data length (logand length 1))))
               (when (> (+ data length) end) (damaged))
               (cond ((string= name "VP8X")
                      (unless (and (null width) (>= length 10)) (damaged))
                      (setf width (1+ (u24le octets (+ data 4)))
                            height (1+ (u24le octets (+ data 7)))))
                     ((member name '("VP8 " "VP8L") :test #'string=)
                      (setf image t)
                      (multiple-value-bind (w h) (webp-image-size name octets data length)
                        (check-pixels w h)
                        (unless width (setf width w height h))))
                     ((string= name "ANMF")
                      (unless (>= length 16) (damaged))
                      (setf image t)
                      (check-pixels (1+ (u24le octets (+ data 6)))
                                    (1+ (u24le octets (+ data 9))))))
               (when (member name +webp-kept+ :test #'string=)
                 (let ((start (fill-pointer output)))
                   (keep output octets at (min next end))
                   (when (string= name "VP8X")
                     ;; No Exif and no XMP any more (bits 3 and 2 of the flags).
                     (setf (aref output (+ start 8))
                           (logand (aref output (+ start 8)) (lognot #x0C))))))
               (setf at next)))
    (unless (and image width (plusp width) (plusp height)) (damaged))
    (check-pixels width height)
    ;; The RIFF size: what follows it.
    (let ((size (- (fill-pointer output) 8)))
      (loop for i below 4
            do (setf (aref output (+ 4 i)) (ldb (byte 8 (* 8 i)) size))))
    (values (output-octets output) width height)))

;;; ------------------------------------------------------------------
;;; GIF (spec/files.md 2.1, 3)

(defun sub-blocks-end (octets at)
  "Where the sub-blocks from AT end, after their zero terminator."
  (loop
   (need octets (1+ at))
   (let ((size (aref octets at)))
     (when (zerop size) (return (1+ at)))
     (setf at (+ at 1 size))
     (need octets at))))

(defun colour-table-octets (flags)
  (if (logbitp 7 flags) (* 3 (ash 1 (1+ (logand flags 7)))) 0))

(defparameter +netscape-looping+
  (concatenate 'octets (list 11) (octets-of "NETSCAPE2.0"))
  "The start of the application extension that makes a GIF loop: its first
sub-block, 11 octets naming it.")

(defun walk-gif (octets)
  "Values the GIF OCTETS without comments, plain text, application
extensions other than NETSCAPE2.0 or what follows its trailer; its width
and height."
  (need octets 13)
  (let ((width (u16le octets 6))
        (height (u16le octets 8))
        (at (+ 13 (colour-table-octets (aref octets 10))))
        (output (make-output octets))
        (pieces 0))
    (when (or (zerop width) (zerop height)) (damaged))
    (check-pixels width height)
    (need octets at)
    (keep output octets 0 at)
    (loop
     (need octets (1+ at))
     (setf pieces (count-piece pieces))
     (case (aref octets at)
       (#x3B                           ; the trailer
        (keep output octets at (1+ at))
        (return (values (output-octets output) width height)))
       (#x2C                           ; an image
        (need octets (+ at 10))
        (check-pixels (u16le octets (+ at 5)) (u16le octets (+ at 7)))
        (let* ((data (+ at 10 (colour-table-octets (aref octets (+ at 9)))))
               (end (progn (need octets (1+ data)) (sub-blocks-end octets (1+ data)))))
          (keep output octets at end)
          (setf at end)))
       (#x21                           ; an extension
        (need octets (+ at 2))
        (let ((label (aref octets (+ at 1)))
              (end (sub-blocks-end octets (+ at 2))))
          (when (or (= label #xF9)
                    (and (= label #xFF) (octets-at-p octets (+ at 2) +netscape-looping+)))
            (keep output octets at end))
          (setf at end)))
       (t (damaged))))))

;;; ------------------------------------------------------------------
;;; The whole of it

(defun examine-file (octets)
  "Values the file OCTETS as Tun stores it (metadata taken out), its type
keyword, and its width and height (NIL for a PDF).  Signals FILE-REFUSED for
a file of another type, a damaged one or one past the pixel bounds."
  (let ((type (file-type octets)))
    (multiple-value-bind (stored width height)
        (case type
          (:png (walk-png octets))
          (:jpeg (walk-jpeg octets))
          (:webp (walk-webp octets))
          (:gif (walk-gif octets))
          (:pdf (values octets nil nil))
          (t (refuse-file +type-refused+)))
      (when width
        (when (or (zerop width) (zerop height)) (damaged))
        (check-pixels width height))
      (values (coerce stored 'octets) type width height))))

;;; ------------------------------------------------------------------
;;; Names (spec/files.md 2.3)

(defparameter +most-given-name+ 255 "The longest filename a caller may give.")
(defparameter +most-stored-name+ 200 "The longest filename Tun keeps.")

(defun control-character-p (char)
  "True for Unicode's control and format characters (Cc and Cf), the line and
paragraph separators, and the double quote."
  (or (member (sb-unicode:general-category char) '(:cc :cf))
      (member char (list (code-char #x2028) (code-char #x2029) #\"))))

(defun stored-filename (given type)
  "The name a file of TYPE given as GIVEN is stored under (spec/files.md 2.3)."
  (let* ((base (subseq given (1+ (or (position-if (lambda (c) (member c '(#\/ #\\))) given
                                                  :from-end t)
                                     -1))))
         (clean (string-trim " " (remove-if #'control-character-p base)))
         (extensions (cdr (assoc type +extensions+)))
         (suffix (find-if (lambda (extension)
                            (let ((ending (concatenate 'string "." extension)))
                              (and (>= (length clean) (length ending))
                                   (string-equal ending clean :start2 (- (length clean)
                                                                         (length ending))))))
                          extensions))
         (stem (if suffix (subseq clean 0 (- (length clean) (length suffix) 1)) clean))
         (ending (if suffix
                     (subseq clean (- (length clean) (length suffix) 1))
                     (concatenate 'string "." (first extensions)))))
    (when (zerop (length stem))
      (setf stem "fil"))
    (concatenate 'string
                 (subseq stem 0 (min (length stem) (- +most-stored-name+ (length ending))))
                 ending)))

;;; ------------------------------------------------------------------
;;; Base64 (spec/files.md 4.1)

(defparameter +base64-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  "The standard base64 alphabet (RFC 4648 4).")

(defparameter +base64-values+
  (let ((values (make-array 128 :element-type '(integer -1 63) :initial-element -1)))
    (loop for char across +base64-alphabet+
          for value from 0
          do (setf (aref values (char-code char)) value))
    values)
  "Each ASCII character's value in +BASE64-ALPHABET+, or -1.")

(declaim (inline base64-code-value))
(defun base64-code-value (code)
  "The value in base64 of the character whose code is CODE, or NIL."
  (and (< code 128) (let ((value (aref +base64-values+ code))) (and (>= value 0) value))))

(defun line-break-p (char)
  (member char '(#\Return #\Newline)))

(defun line-break-code-p (code)
  (or (= code 10) (= code 13)))

;;; The decoder reads the characters of the text through EACH-CODE, a
;;; function that calls its argument with each character's code in turn
;;; and NIL when it meets one that cannot be read: a string's characters
;;; (STRING-CODES), or a JSON string still in a body's octets
;;; (JSON-STRING-CODES), so neither is copied first.

(defun string-codes (text)
  (lambda (function)
    (loop for char across text do (funcall function (char-code char)))))

(defun base64-shape (each-code)
  "Values how many characters EACH-CODE gives are base64's, line breaks left
out, and how many of them are padding at the end; NIL when another
character is in it, padding is not only at its end, or the count is not a
multiple of four."
  (let ((count 0) (padding 0))
    (funcall each-code
             (lambda (code)
               (cond ((null code) (return-from base64-shape nil))
                     ((line-break-code-p code))
                     ((= code 61) (incf count) (incf padding)) ; =
                     ((and (zerop padding) (base64-code-value code)) (incf count))
                     (t (return-from base64-shape nil)))))
    (and (zerop (mod count 4)) (<= padding 2) (values count padding))))

(defun base64-decode (each-code)
  "The octets the characters EACH-CODE gives encode in standard base64 (RFC
4648 4), line breaks ignored.  Signals FILE-REFUSED for any other
character, bad padding, or more than +MOST-FILE-OCTETS+ octets, before
decoding those.  Decodes straight into the result."
  (multiple-value-bind (count padding) (base64-shape each-code)
    (unless count
      (refuse-file "Innholdet i data er ikke gyldig base64."))
    (let ((size (- (* 3 (floor count 4)) padding)))
      (when (> size +most-file-octets+)
        (refuse-file "Filen er større enn 10 MB."))
      (let ((octets (make-array size :element-type '(unsigned-byte 8)))
            (bits 0) (held 0) (at 0))
        (funcall each-code
                 (lambda (code)
                   (let ((value (and code (base64-code-value code))))
                     (when value
                       (setf bits (logior (ash (ldb (byte 18 0) bits) 6) value))
                       (incf held 6)
                       (when (>= held 8)
                         (decf held 8)
                         (setf (aref octets at) (ldb (byte 8 held) bits))
                         (incf at))))))
        octets))))

(defun refuse-data-url ()
  (refuse-file "Send bare base64-innholdet i data, uten «data:…;base64,» foran."))

(defun base64-octets (text)
  "The octets TEXT encodes in standard base64 (BASE64-DECODE).  Signals
FILE-REFUSED for a data URL too.  TEXT, a large string, is never copied."
  (when (and (>= (length text) 5) (string-equal "data:" text :end2 5))
    (refuse-data-url))
  (base64-decode (string-codes text)))

(defun json-string-codes (octets start end)
  "The codes of the characters of a JSON string in OCTETS, from START to END
between its quotes, read in place: its ASCII characters, and the escapes
\\/, \\n and \\r, which base64 in JSON may have; NIL for anything else."
  (lambda (function)
    (let ((i start))
      (loop while (< i end)
            do (let ((octet (aref octets i)))
                 (cond ((= octet 92)    ; a backslash
                        (case (and (< (1+ i) end) (aref octets (1+ i)))
                          (47 (funcall function 47))
                          (110 (funcall function 10))
                          (114 (funcall function 13))
                          (t (funcall function nil) (return)))
                        (incf i 2))
                       ((>= octet 128) (funcall function nil) (return))
                       (t (funcall function octet) (incf i))))))))

(defun json-base64-octets (octets start end)
  "The octets the JSON string in OCTETS from START to END encodes in base64,
as BASE64-OCTETS gives them for its text, without making that text."
  (when (and (>= (- end start) 5)
             (string-equal "data:" (map 'string #'code-char (subseq octets start (+ start 5)))))
    (refuse-data-url))
  (base64-decode (json-string-codes octets start end)))

(defun base64-length (text)
  "How many octets TEXT, base64, decodes to, without decoding it; line breaks,
at the end too, left out."
  (let ((count (count-if-not #'line-break-p text))
        (padding (count #\= text)))
    (max 0 (- (* 3 (floor count 4)) (min padding 2)))))
