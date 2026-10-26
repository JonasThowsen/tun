;;;; tests/rank-tests.lisp -- rank keys: rank-between and the key format
;;;; (spec/core.md 2.6).

(in-package #:tun.tests)

(def-suite rank :in core)
(in-suite rank)

(defun keys-in-order-p (keys)
  "True when KEYS, a list, is strictly increasing by code point."
  (loop for (a b) on keys
        always (or (null b) (string< a b))))

(defparameter +largest-whole-part+ (concatenate 'string "z" (make-string 26 :initial-element #\z)))
(defparameter +smallest-whole-part+ (concatenate 'string "A" (make-string 26 :initial-element #\0)))

(test the-first-key-and-keys-at-either-end
  (is (string= "a0" (rank-between nil nil)))
  (is (string= "a1" (rank-between "a0" nil)) "the end steps the whole part")
  (is (string= "Zz" (rank-between nil "a0")) "the top steps it down, below zero")
  (is (string= "a0" (rank-between nil "a0V")) "before a key with a fraction, its whole part alone")
  (is (string= "b00" (rank-between "az" nil)) "a whole part gets longer away from zero")
  (is (string= "Yzz" (rank-between nil "Z0")) "and below zero too")
  (is (string= "a0" (rank-between "Zz" nil)) "from below zero up to zero"))

(test the-fraction-digit-is-the-midpoint-rounded-half-up
  (is (string= "a0V" (rank-between "a0" "a1")))
  (is (string= "a0l" (rank-between "a0V" "a1")) "(31 + 62 + 1) / 2 is 47, l")
  (is (string= "a1V" (rank-between "a1" "a2")))
  (is (string= "a0G" (rank-between "a0" "a0V")) "(0 + 31 + 1) / 2 is 16, G")
  (is (string= "a0VV" (rank-between "a0V" "a0W")) "adjacent digits keep LOW's and go on")
  (is (string= "a0G" (rank-between "a0" "a0W")) "between a whole part and a fraction"))

(test the-same-arguments-give-the-same-key
  (is (string= (rank-between "a0" "a1") (rank-between "a0" "a1")))
  (is (string= (rank-between "a0V" nil) (rank-between "a0V" nil))))

(test a-key-is-strictly-between-its-neighbours
  (dolist (pair '(("a0" "a1") ("a0" "a0V") ("a0V" "a0W") ("Zz" "a0") ("a0" "b00")
                  ("az" "b00") ("a0zzzzz" "a1") ("a0" "a00001") ("Zzzz" "a0001")))
    (destructuring-bind (low high) pair
      (let ((key (rank-between low high)))
        (is (and (string< low key) (string< key high)) "~s is between ~s and ~s" key low high)
        (is (tun.core:rank-key-p key))))))

(test the-largest-and-smallest-whole-parts-take-a-fraction
  (let ((key (rank-between +largest-whole-part+ nil)))
    (is (string< +largest-whole-part+ key))
    (is (string= +largest-whole-part+ (subseq key 0 27)) "past the largest, its whole part")
    (is (string= key (rank-between +largest-whole-part+ nil))))
  (let* ((high (concatenate 'string +smallest-whole-part+ "V"))
         (key (rank-between nil high)))
    (is (string< key high))
    (is (string= +smallest-whole-part+ (subseq key 0 27)) "before the smallest, its whole part")
    (is (tun.core:rank-key-p key))))

(test ten-thousand-keys-at-either-end-stay-short
  (let ((keys (loop repeat 10000
                    for key = (rank-between nil nil) then (rank-between key nil)
                    collect key)))
    (is (keys-in-order-p keys) "added at the end")
    (is (<= (reduce #'max keys :key #'length) 4)))
  (let ((keys (loop repeat 10000
                    for key = (rank-between nil nil) then (rank-between nil key)
                    collect key)))
    (is (keys-in-order-p (reverse keys)) "added at the top")
    (is (<= (reduce #'max keys :key #'length) 4))))

(test a-thousand-keys-at-one-spot-stay-in-order-and-under-210-characters
  ;; Each new key directly after a0: between a0 and the key added last.
  (let ((keys (loop repeat 1000
                    for key = (rank-between "a0" "a1") then (rank-between "a0" key)
                    collect key)))
    (is (keys-in-order-p (cons "a0" (reverse keys))))
    (is (= 169 (reduce #'max keys :key #'length)) "about one character per six keys"))
  ;; Each new key directly before a1: between the key added last and a1.
  (let ((keys (loop repeat 1000
                    for key = (rank-between "a0" "a1") then (rank-between key "a1")
                    collect key)))
    (is (keys-in-order-p (append keys (list "a1"))))
    (is (= 202 (reduce #'max keys :key #'length)) "about one character per five keys")
    (is (<= (reduce #'max keys :key #'length) 210))))

(test random-insertions-keep-a-list-sorted
  (let ((state (sb-ext:seed-random-state 2026))
        (keys (list (rank-between nil nil))))
    (dotimes (i 2000)
      (let* ((at (random (1+ (length keys)) state))
             (low (if (plusp at) (nth (1- at) keys)))
             (high (nth at keys))
             (key (rank-between low high)))
        (setf keys (append (subseq keys 0 at) (list key) (nthcdr at keys)))))
    (is (= 2001 (length keys)))
    (is (keys-in-order-p keys) "every key sits between its neighbours")
    (is (equal keys (sort (copy-list keys) #'string<)) "sorting the keys gives the list's order")
    (is (every #'tun.core:rank-key-p keys))))

(test a-string-that-is-not-a-key-is-a-type-error
  (dolist (bad (list "" "a0-" "aø" "0a" "b0" "Y0" "a0V0" +smallest-whole-part+ 1 :a0))
    (signals type-error (rank-between bad nil) "~s as LOW" bad)
    (signals type-error (rank-between nil bad) "~s as HIGH" bad))
  (signals type-error (rank-between "b0" "a0") "a non-key is a type-error before the order"))

(test low-not-before-high-is-a-rank-order-error
  (dolist (pair '(("a1" "a0") ("a0" "a0") ("a0V" "a0")))
    (destructuring-bind (low high) pair
      (handler-case (progn (rank-between low high)
                           (fiveam:fail "~s ~s gave a key" low high))
        (rank-order-error (condition)
          (is (string= low (rank-order-error-low condition)))
          (is (string= high (rank-order-error-high condition))))))))
