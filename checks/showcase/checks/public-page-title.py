"""A customer's public page shows the name the client answers for it, the
company's, as the frame's title, its mark and the tab's title; a public
page the client passes on for and a staff page show the application's
(spec/ui.md 8, «Public pages»)."""

COMPANY = "Lindenhof Services"
APPLICATION = "showcase"


def names(page):
    return (page.locator(".tun-app-shell-name-text").first.text_content().strip(),
            page.locator(".tun-app-shell-mark").first.text_content().strip(),
            page.title())


def scrolls_sideways(page):
    return page.evaluate("document.documentElement.scrollWidth > window.innerWidth")


def run(t):
    for width, page in ((390, t.phone()), (1280, t.desktop())):
        page.goto("/quote/q1")
        title, mark, tab = names(page)
        t.check(title == COMPANY and mark == "L",
                f"{width} px: the quote's frame is the company's: {title!r}, {mark!r}")
        t.check(tab.endswith(f"– {COMPANY}"), f"{width} px: and so is the tab's title: {tab!r}")
        t.check(not scrolls_sideways(page), f"{width} px: the quote does not scroll sideways")

        page.goto("/notice")
        title, mark, tab = names(page)
        t.check(title == APPLICATION and mark == "s" and tab.endswith(f"– {APPLICATION}"),
                f"{width} px: a page the client passes on for is the application's: "
                f"{title!r}, {tab!r}")

        page.sign_in("employee:anna")
        page.goto("/items")
        title, mark, tab = names(page)
        t.check(title == APPLICATION and tab.endswith(f"– {APPLICATION}"),
                f"{width} px: a staff page keeps the application's title: {title!r}, {tab!r}")

        page.goto("/quote/q1")
        t.check(names(page)[0] == COMPANY,
                f"{width} px: and the quote, opened signed in, the company's")
