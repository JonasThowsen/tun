;;;; tests/util-tests.lisp -- JSON, time, identifiers.

(in-package #:tun.tests)

(def-suite util :in core)
(in-suite util)

(test json-round-trip
  (let* ((text "{\"navn\":\"Ærlige Øystein på Å\",\"n\":[1,2,3],\"t\":true,\"f\":false,\"z\":null,\"e\":[]}")
         (value (parse-json text)))
    (is (string= "Ærlige Øystein på Å" (jget value "navn")))
    (is (equalp #(1 2 3) (jget value "n")))
    (is (string= text (to-json-string value)))))

(test canonical-json-sorts-keys
  (is (string= (to-json-string (jobj "b" 1 "a" 2) :canonical t) "{\"a\":2,\"b\":1}"))
  (is (string= (canonical-json-hash (jobj "b" 1 "a" 2))
               (canonical-json-hash (jobj "a" 2 "b" 1)))))

(test empty-list-is-array-only-as-vector
  (is (string= "[]" (to-json-string (jarr '()))))
  (is (string= "false" (to-json-string nil))))

(test rfc3339
  (let ((t0 (parse-rfc3339 "2026-03-01T09:00:00Z")))
    (is (integerp t0))
    (is (string= "2026-03-01T09:00:00Z" (format-rfc3339 t0)))
    (is (= t0 (parse-rfc3339 "2026-03-01T10:00:00+01:00")))
    (is (= t0 (parse-rfc3339 "2026-03-01T09:00:00.123Z")))
    (is (null (parse-rfc3339 "2026-02-30T09:00:00Z")))
    (is (null (parse-rfc3339 "not a time")))))

(test dates
  (is (string= "2026-06-20" (date-add-days "2026-07-11" -21)))
  (is (string= "2026-03-01" (date-add-days "2026-02-28" 1)))
  (is (null (parse-date "2026-13-01")))
  (is (null (parse-date "2026-6-1"))))

(test identifiers-are-random-and-prefixed
  (let ((a (new-id "cus")) (b (new-id "cus")))
    (is (string-prefix-p "cus_" a))
    (is (string/= a b))
    (is (= 64 (length (new-secret-token))))))
