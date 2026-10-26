# Lint baseline

Tool: Mallet version 0.9.2. Parent Git revision: `0bebdca3482d6a94f00b8a25dd8df614ba2b62c7`.

Regenerate with `bin/lint --baseline`. Full locations: `.build/lint.json`.

Advisory findings: 2925 in 140 files.

| File | Findings | Rules |
|---|---:|---|
| modules/calendar/calendar.lisp | 21 | line-length (18), needless-let* (1), unused-local-functions (2) |
| modules/catalog/catalog.lisp | 42 | line-length (38), missing-docstring (4) |
| modules/catalog/publish.lisp | 1 | line-length (1) |
| modules/catalog/requirements.lisp | 56 | line-length (56) |
| modules/customers/customers.lisp | 12 | line-length (9), missing-docstring (2), needless-let* (1) |
| modules/dashboard/dashboard.lisp | 1 | line-length (1) |
| modules/dashboard/errors.lisp | 8 | line-length (8) |
| modules/dashboard/jobs.lisp | 13 | line-length (12), needless-let* (1) |
| modules/dashboard/log.lisp | 8 | line-length (8) |
| modules/inbox/inbox.lisp | 59 | line-length (54), missing-docstring (2), needless-let* (1), unused-local-nicknames (1), unused-variables (1) |
| modules/inbox/public-feedback.lisp | 8 | line-length (8) |
| modules/inventory/articles.lisp | 34 | line-length (34) |
| modules/inventory/consumption.lisp | 18 | line-length (16), missing-docstring (1), needless-let* (1) |
| modules/inventory/forecast.lisp | 32 | line-length (32) |
| modules/inventory/inventory.lisp | 36 | line-length (23), missing-docstring (13) |
| modules/inventory/publish.lisp | 2 | line-length (2) |
| modules/inventory/stock.lisp | 17 | line-length (16), needless-let* (1) |
| modules/invoicing/invoicing.lisp | 23 | line-length (21), missing-docstring (2) |
| modules/messaging/messaging.lisp | 99 | line-length (95), missing-docstring (3), unused-local-nicknames (1) |
| modules/messaging/outbox.lisp | 24 | line-length (23), needless-let* (1) |
| modules/notifications/notifications.lisp | 8 | line-length (7), unused-local-nicknames (1) |
| modules/orders/checklists.lisp | 14 | line-length (13), needless-let* (1) |
| modules/orders/orders.lisp | 85 | line-length (75), missing-docstring (9), needless-let* (1) |
| modules/orders/package.lisp | 18 | line-length (16), missing-docstring (1), unused-local-nicknames (1) |
| modules/orders/plans.lisp | 50 | line-length (48), missing-docstring (2) |
| modules/orders/public-offers.lisp | 13 | line-length (12), needless-let* (1) |
| modules/orders/publish.lisp | 5 | line-length (5) |
| modules/orders/quotes.lisp | 27 | line-length (22), missing-docstring (1), unused-variables (4) |
| modules/orders/requirements.lisp | 7 | line-length (7) |
| modules/orders/stock.lisp | 10 | line-length (9), needless-let* (1) |
| modules/orders/transitions.lisp | 23 | line-length (23) |
| modules/reviews/reviews.lisp | 23 | line-length (22), missing-docstring (1) |
| modules/staffing/assignments.lisp | 34 | line-length (31), missing-docstring (1), needless-let* (2) |
| modules/staffing/staffing.lisp | 16 | line-length (15), missing-docstring (1) |
| modules/staffing/unavailability.lisp | 23 | line-length (22), no-ignore-errors (1) |
| modules/warehouse/warehouse.lisp | 17 | line-length (17) |
| scripts/build-image.lisp | 7 | line-length (5), no-ignore-errors (2) |
| scripts/build.lisp | 1 | line-length (1) |
| scripts/serve.lisp | 1 | line-length (1) |
| scripts/setup.lisp | 1 | missing-docstring (1) |
| scripts/test.lisp | 1 | line-length (1) |
| src/adapters/fake-accounting.lisp | 2 | missing-docstring (1), no-ignore-errors (1) |
| src/agent/http.lisp | 30 | double-colon-access (4), line-length (17), missing-docstring (5), needless-let* (1), no-ignore-errors (3) |
| src/agent/mcp.lisp | 10 | line-length (8), no-ignore-errors (2) |
| src/auth/oauth.lisp | 1 | line-length (1) |
| src/auth/oidc.lisp | 2 | line-length (1), missing-docstring (1) |
| src/auth/sign-in.lisp | 4 | line-length (1), missing-docstring (2), needless-let* (1) |
| src/auth/tools.lisp | 1 | line-length (1) |
| src/cli/check.lisp | 5 | line-length (4), no-ignore-errors (1) |
| src/cli/loop.lisp | 16 | line-length (15), no-ignore-errors (1) |
| src/cli/main.lisp | 1 | line-length (1) |
| src/cli/preview.lisp | 22 | line-length (11), missing-docstring (1), no-ignore-errors (10) |
| src/core/actor.lisp | 7 | line-length (1), missing-docstring (6) |
| src/core/application.lisp | 26 | line-length (12), missing-docstring (14) |
| src/core/conditions.lisp | 7 | line-length (2), missing-docstring (5) |
| src/core/deadline.lisp | 8 | line-length (2), missing-docstring (4), no-ignore-errors (2) |
| src/core/entity.lisp | 41 | line-length (23), missing-docstring (15), needless-let* (3) |
| src/core/execution.lisp | 28 | line-length (24), missing-docstring (3), no-ignore-errors (1) |
| src/core/json.lisp | 8 | missing-docstring (8) |
| src/core/module.lisp | 31 | double-colon-access (3), line-length (17), missing-docstring (9), needless-let* (2) |
| src/core/operation.lisp | 31 | line-length (18), missing-docstring (12), needless-let* (1) |
| src/core/package.lisp | 31 | line-length (31) |
| src/core/registry.lisp | 47 | line-length (35), missing-docstring (12) |
| src/core/settings.lisp | 33 | line-length (27), missing-docstring (5), needless-let* (1) |
| src/core/store.lisp | 19 | line-length (4), missing-docstring (15) |
| src/core/system-entities.lisp | 5 | line-length (3), missing-docstring (2) |
| src/core/trace.lisp | 53 | double-colon-access (3), line-length (29), missing-docstring (14), no-ignore-errors (7) |
| src/core/types.lisp | 23 | line-length (7), missing-docstring (16) |
| src/core/util.lisp | 16 | line-length (5), missing-docstring (11) |
| src/core/waiting.lisp | 2 | missing-docstring (1), needless-let* (1) |
| src/jobs/cron.lisp | 4 | line-length (4) |
| src/jobs/jobs.lisp | 9 | line-length (8), missing-docstring (1) |
| src/jobs/runner.lisp | 5 | line-length (4), no-ignore-errors (1) |
| src/jobs/schedules.lisp | 6 | line-length (6) |
| src/jobs/tools.lisp | 4 | line-length (4) |
| src/jobs/triggers.lisp | 1 | line-length (1) |
| src/outbound/outbound.lisp | 2 | line-length (1), missing-docstring (1) |
| src/platform/errors.lisp | 9 | line-length (7), no-ignore-errors (2) |
| src/platform/introspection.lisp | 82 | line-length (77), missing-docstring (2), needless-let* (1), no-eval (1), no-ignore-errors (1) |
| src/platform/live-definitions.lisp | 9 | line-length (5), missing-docstring (2), no-ignore-errors (2) |
| src/platform/platform.lisp | 6 | line-length (6) |
| src/platform/workflows.lisp | 20 | line-length (16), missing-docstring (3), no-ignore-errors (1) |
| src/ports/accounting.lisp | 2 | line-length (2) |
| src/public.lisp | 11 | double-colon-access (2), line-length (9) |
| src/runtime.lisp | 21 | line-length (14), missing-docstring (3), no-ignore-errors (4) |
| src/store/memory.lisp | 11 | line-length (9), missing-docstring (1), needless-let* (1) |
| src/store/postgres.lisp | 1 | line-length (1) |
| src/store/sqlite.lisp | 38 | double-colon-access (2), line-length (26), missing-docstring (1), needless-let* (1), no-ignore-errors (8) |
| src/web/access.lisp | 1 | line-length (1) |
| src/web/html.lisp | 5 | line-length (3), missing-docstring (2) |
| src/web/ui.lisp | 21 | double-colon-access (1), line-length (20) |
| src/web/ui/board.lisp | 12 | line-length (12) |
| src/web/ui/icon-data.lisp | 25 | line-length (25) |
| src/web/ui/kit.lisp | 3 | line-length (3) |
| src/web/web-app.lisp | 2 | line-length (2) |
| tests/api-tests.lisp | 4 | line-length (4) |
| tests/client/tests/extension-tests.lisp | 2 | double-colon-access (2) |
| tests/client/tests/interface-tests.lisp | 1 | no-eval (1) |
| tests/communication-tests.lisp | 86 | line-length (82), needless-let* (4) |
| tests/dashboard-tests.lisp | 1 | line-length (1) |
| tests/errors-tests.lisp | 5 | line-length (4), no-ignore-errors (1) |
| tests/fake-provider.lisp | 2 | line-length (2) |
| tests/group-commit-tests.lisp | 13 | line-length (13) |
| tests/introspection-tests.lisp | 66 | line-length (64), needless-let* (1), no-eval (1) |
| tests/jobs-tests.lisp | 1 | line-length (1) |
| tests/loop-tests.lisp | 9 | line-length (9) |
| tests/mail-tests.lisp | 1 | unused-variables (1) |
| tests/mcp-tests.lisp | 16 | line-length (16) |
| tests/module-system-tests.lisp | 25 | line-length (25) |
| tests/module-tests.lisp | 54 | line-length (52), no-eval (2) |
| tests/oauth-tests.lisp | 5 | line-length (5) |
| tests/orders-depth-tests.lisp | 96 | line-length (94), needless-let* (2) |
| tests/outbound-tests.lisp | 16 | line-length (12), needless-let* (4) |
| tests/pressure-tests.lisp | 22 | line-length (21), needless-let* (1) |
| tests/preview-tests.lisp | 8 | line-length (7), no-eval (1) |
| tests/query-tests.lisp | 1 | no-eval (1) |
| tests/record-policy-tests.lisp | 5 | line-length (4), no-eval (1) |
| tests/registry-tests.lisp | 4 | line-length (4) |
| tests/review-tests.lisp | 22 | line-length (21), no-ignore-errors (1) |
| tests/review2-tests.lisp | 58 | line-length (53), no-eval (5) |
| tests/safety-tests.lisp | 12 | line-length (11), needless-let* (1) |
| tests/schedule-tests.lisp | 4 | line-length (4) |
| tests/settings-tests.lisp | 11 | line-length (11) |
| tests/sign-in-tests.lisp | 2 | line-length (2) |
| tests/slice1-review-tests.lisp | 42 | line-length (39), needless-let* (2), no-eval (1) |
| tests/slice2-review-tests.lisp | 63 | line-length (59), needless-let* (4) |
| tests/slice2-tests.lisp | 237 | line-length (231), needless-let* (6) |
| tests/slice3-review-round3-tests.lisp | 39 | line-length (35), needless-let* (4) |
| tests/slice3-review-round4-tests.lisp | 18 | line-length (17), needless-let* (1) |
| tests/slice3-review-tests.lisp | 79 | line-length (72), needless-let* (6), unused-variables (1) |
| tests/staffing-tests.lisp | 63 | line-length (60), needless-let* (3) |
| tests/store-tests.lisp | 27 | line-length (23), needless-let* (1), no-ignore-errors (3) |
| tests/support.lisp | 51 | double-colon-access (3), line-length (43), missing-docstring (5) |
| tests/ui-data-tests.lisp | 5 | line-length (5) |
| tests/ui-interaction-tests.lisp | 1 | line-length (1) |
| tests/ui-layout-tests.lisp | 1 | line-length (1) |
| tests/util-tests.lisp | 1 | line-length (1) |
| tests/waiting-tests.lisp | 4 | line-length (3), needless-let* (1) |
| tests/web-app-tests.lisp | 7 | line-length (7) |
| tests/web-tests.lisp | 17 | line-length (17) |
