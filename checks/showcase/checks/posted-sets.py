"""«Visit days», a group of checkboxes that posts its name once for each
box ticked, saves every box ticked (spec/ui.md 8, «A client's pages» 2):
at 390 px with and without JavaScript, and at 1280 px, two ticked save
two, three save three and none saves none, each shown saved and ticked
when the page is opened again."""

SAVED = "[data-saved-days]"
DAYS = ["mon", "tue", "wed", "thu", "fri"]


def save_days(page, days, javascript):
    """Tick DAYS alone on «Visit days» and save; the answer is waited for."""
    page.goto("/visit-days")
    for day in DAYS:
        page.locator(f"input[name=days][value={day}]").set_checked(day in days)
    button = page.get_by_role("button", name="Save")
    if javascript:
        with page.expect_htmx():
            button.click()
    else:
        with page.expect_navigation():
            button.click()


def shown(page):
    """What «Visit days» shows as saved, and which boxes are ticked."""
    page.goto("/visit-days")
    saved = page.locator(SAVED).get_attribute("data-saved-days")
    ticked = [day for day in DAYS if page.locator(f"input[name=days][value={day}]").is_checked()]
    return (saved.split() if saved else []), ticked


def round_of(t, page, what, javascript=True):
    page.sign_in("employee:anna")
    for days in (["mon", "wed"], ["tue", "thu", "fri"], [], ["mon", "wed"]):
        save_days(page, days, javascript)
        saved, ticked = shown(page)
        t.check(saved == days, f"{what}: {len(days)} ticked, {len(days)} saved: {saved}")
        t.check(ticked == days, f"{what}: and ticked again when opened: {ticked}")
    text = page.locator(SAVED).text_content().strip()
    t.check(text == "Saved: Monday, Wednesday.", f"{what}: the page says so: {text!r}")
    t.check(page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"),
            f"{what}: the page does not scroll sideways")


def run(t):
    round_of(t, t.phone(), "390 px")
    round_of(t, t.phone(javascript=False), "390 px without JavaScript", javascript=False)
    round_of(t, t.desktop(), "1280 px")
    t.close_pages()
