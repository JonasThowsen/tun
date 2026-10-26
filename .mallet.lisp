;; Advisory house-style checks, without suppressing the existing findings.
(:mallet-config
 (:extends :default)
 (:enable :line-length :max 100)
 (:enable :missing-docstring :exported-only t)
 (:enable :double-colon-access)
 (:ignore ".build/**" "reference/lib/**"))
