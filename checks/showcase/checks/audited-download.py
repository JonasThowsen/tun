"""«Customer data» downloads a customer's data as JSON through a read that
is audited with the reason the admin gives (spec/core.md 3.8, spec/files.md
5.5), on a phone with and without JavaScript; without a reason nothing is
downloaded; the «Audit log» then shows the export, who made it, the
customer and the reason, and nothing of the customer's data."""

import json
import pathlib


def export(t, page, reason, what):
    page.goto("/customer-data")
    choice = page.locator("select[name=customer_id] option").nth(1)
    name = choice.inner_text().strip()
    page.locator("select[name=customer_id]").select_option(index=1)
    page.locator("textarea[name=reason]").fill(reason)
    with page.expect_download() as info:
        page.get_by_role("button", name="Download the data").click()
    download = info.value
    t.check(download.suggested_filename == f"customer-{name}.json",
            f"{what}: named after the customer: {download.suggested_filename}")
    data = json.loads(pathlib.Path(download.path()).read_text(encoding="utf-8"))
    t.check(data["customer"]["name"] == name,
            f"{what}: the customer's data: {data['customer']['name']}")
    t.check(page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"),
            f"{what}: the page does not scroll sideways")
    return data["customer"]


def run(t):
    page = t.phone()
    page.sign_in("admin:jonas")
    page.goto("/customer-data")
    downloads = []
    page.on("download", lambda download: downloads.append(download))
    page.locator("select[name=customer_id]").select_option(index=1)
    with page.expect_navigation():
        page.get_by_role("button", name="Download the data").click()
    t.check(page.locator(".tun-alert").is_visible(), "without a reason: an alert")
    t.check("reason" in page.locator(".tun-alert").inner_text().lower(),
            f"naming the reason: {page.locator('.tun-alert').inner_text()}")
    t.check(not downloads, "and no file")
    customer = export(t, page, "The customer asked for a copy", "on a phone")
    page.goto("/audit")
    log = page.locator("[data-audit-log]")
    rows = log.locator("tbody tr")
    first = rows.first.inner_text()
    t.check("customer_data_export" in first and "admin:jonas" in first,
            f"the export is the latest entry, by the admin: {first}")
    t.check(customer["id"] in first, f"naming the customer: {first}")
    t.check("The customer asked for a copy" in first, f"with the reason: {first}")
    t.check(customer["email"] not in log.inner_text() and customer["name"] not in log.inner_text(),
            "nothing of the customer's data is in the log")
    t.check(page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"),
            "the log does not scroll sideways")
    plain = t.phone(javascript=False)
    plain.sign_in("admin:jonas")
    export(t, plain, "Asked again, without a script", "without JavaScript")
    viewer = t.phone()
    viewer.sign_in("employee:anna")
    refused = viewer.request.get(t.url + "/customer-data")
    t.check(refused.status == 403, f"an employee is refused the page: {refused.status}")
