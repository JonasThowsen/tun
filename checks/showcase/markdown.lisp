;;;; markdown.lisp -- /markdown: a comment as an agent writes it, shown with
;;;; MARKDOWN (spec/ui.md 6.2): every block and inline rule, a table of three
;;;; columns and one of ten, and lines too long for a phone.

(in-package #:showcase)

(defparameter +agent-comment+
  "# What I changed

The export now writes **one file a day**, and *only* the orders since the last run. `bin/export` takes `--from`; see [the item](/items/12), [the guide](https://example.com/docs/export_(v2)) or <https://example.com/status>, and write to [the team](mailto:team@example.com).

## Steps

1. Read the orders since the last run
2. Write them to `exports/`
   - one line an order
   - sorted by number
3. Mark them as sent

---

```sh
bin/export --from 2026-11-01 --to 2026-11-30 --format csv --output exports/orders-2026-11.csv --verbose
```

| Step | Who | When |
|---|---|--:|
| Plan | Kari | Monday |
| Build | an agent | Tuesday |

| Order | Customer | Date | Status | Lines | Net | VAT | Total | Paid | Note |
|---|---|---|---|--:|--:|--:|--:|---|---|
| 10482 | Fjord Coffee Ltd | 12 Oct 2026 | New | 3 | €3,504.00 | €876.00 | €4,380.00 | no | Deliver before noon |
| 10481 | Hansen Building and Construction Ltd | 11 Oct 2026 | In progress | 12 | €103,160.00 | €25,790.00 | €128,950.00 | yes | |

A line with no spaces: exports/orders-2026-11-01-to-2026-11-30-for-every-customer-and-every-department-in-the-company.csv

And a long address: https://example.com/exports/2026/11/orders-for-every-customer-and-every-department-in-the-company.csv

<script>alert('shown as written')</script> [and this](javascript:alert(1))."
  "The comment the page shows.")

(define-page markdown-page ("markdown" :title "Markdown" :icon :file-text :policy :employee)
    (method path form query)
  (declare (ignore form query))
  (if (or (eq method :post) path)
      (values 404 (tr "Markdown") (list (ui:alert (:variant :warning
                                                   :title (tr "Page not found")))))
      (values 200 (tr "Markdown")
              (list (ui:card (:title (tr "A comment"))
                      (ui:markdown (:id "comment" :text +agent-comment+)))))))
