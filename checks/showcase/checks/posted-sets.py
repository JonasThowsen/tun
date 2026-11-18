"""«Visit days», a group of checkboxes that posts its name once for each
box ticked (spec/ui.md 8, «A client's pages» 2), with JavaScript: htmx
builds the post from the boxes ticked, so two ticked save two and none
saves none, each shown saved and ticked when the page is opened again.
Without JavaScript the form is the server's alone, and the page tests post
it (tests/pages.lisp, visit-days-saves-every-box-ticked)."""

SAVED = "[data-saved-days]"
DAYS = ["mon", "tue", "wed", "thu", "fri"]


def save_days(page, days):
    """Tick DAYS alone on «Visit days» and save; the answer is waited for."""
    page.goto("/visit-days")
    for day in DAYS:
        page.locator(f"input[name=days][value={day}]").set_checked(day in days)
    with page.expect_htmx():
        page.get_by_role("button", name="Save").click()


def shown(page):
    """What «Visit days» shows as saved, and which boxes are ticked."""
    page.goto("/visit-days")
    saved = page.locator(SAVED).get_attribute("data-saved-days")
    ticked = [day for day in DAYS if page.locator(f"input[name=days][value={day}]").is_checked()]
    return (saved.split() if saved else []), ticked


def run(t):
    page = t.phone()
    page.sign_in("employee:anna")
    for days in (["mon", "wed"], ["tue", "thu", "fri"], []):
        save_days(page, days)
        saved, ticked = shown(page)
        t.check(saved == days, f"{len(days)} ticked, {len(days)} saved: {saved}")
        t.check(ticked == days, f"and ticked again when opened: {ticked}")
