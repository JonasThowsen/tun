(in-package #:tun.tests)
(in-suite core)

(test declared-settings-policy-and-secrets
  (with-test-app ()
    (is (equal "forbidden" (nth-value 1 (call "settings_list" "employee:anna"))))
    (is (equal "forbidden" (nth-value 1 (call "settings_get" "employee:anna" "key" "lenker.hemmelighet"))))
    (is (equal "https://tun.example" (jget (call-ok "settings_get" "employee:anna" "key" "lenker.base_url") "value")))
    (let ((items (jget (call-ok "settings_list" "admin:anna") "items")))
      (is (equal "***" (jget (find-by "key" "lenker.hemmelighet" items) "value"))))
    (is (equal "invalid_input" (nth-value 1 (call "settings_set" "admin:anna" "key" "lenker.base_url" "value" "file:///tmp"))))
    (call-ok "settings_set" "admin:anna" "key" "lenker.base_url" "value" "http://localhost:8080")
    (is (equal "http://localhost:8080" (jget (call-ok "settings_get" "employee:anna" "key" "lenker.base_url") "value")))
    (let ((id (new-id "req")))
      (let ((*request-id* id))
        (call-ok "settings_set" "admin:anna" "key" "lenker.hemmelighet" "value" "private-secret"))
      (let ((request (call-ok "introspect_request" "admin:anna" "request_id" id)))
        (is (equal "settings_set" (jget request "tool")) "the request that set it")
        (is (not (search "private-secret" (to-json-string request))))))))


(test declared-settings-persist-across-restart
  (let ((db (scratch-path "settings")))
    (with-test-app (:db db)
      (call-ok "settings_set" "admin:anna" "key" "lenker.base_url" "value" "https://changed.example"))
    (with-test-app (:db db)
      (is (equal "https://changed.example" (jget (call-ok "settings_get" "employee:anna" "key" "lenker.base_url") "value"))))))

(test settings-declarations-conflicts-nullability-and-types
  (let ((tun.core::*setting-declarations* (make-hash-table :test 'equal)))
    (define-setting "test.flag" (:type "bool" :default nil))
    (define-setting "test.hours" (:type "int" :default 48 :min 1 :max 720))
    (define-setting "test.email" (:type "email" :nullable t))
    (define-setting "test.secret" (:type "secret"))
    (signals extension-error (define-setting "test.flag" (:type "bool")))
    (signals extension-error (define-setting "test.unknown" (:type "unknown")))
    (with-test-app ()
      (is (null (jget (find-by "key" "test.flag" (jget (call-ok "settings_list" "admin:a") "items")) "default")))
      (is (equal "***" (jget (call-ok "settings_set" "admin:a" "key" "test.secret" "value" "ok") "value")))
      (dolist (value '(0 721 "48" :null))
        (is (equal "invalid_input" (nth-value 1 (call "settings_set" "admin:a" "key" "test.hours" "value" value)))))
      (is (equal "invalid_input" (nth-value 1 (call "settings_set" "admin:a" "key" "test.email" "value" "a@b.no
Bcc: x@y.no"))))
      (is (json-null-p (jget (call-ok "settings_set" "admin:a" "key" "test.email" "value" :null) "value"))))))
