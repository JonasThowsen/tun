"""What opens moves into place, on the specimen: a dialog is a sheet on a
phone and stays above the keyboard, the dim only gets darker, a closing
menu leaves with motion, the focus and the keys, the one confirm for a
marked control and for hx-confirm, the flash as a toast, and reduced motion
(spec/ui.md 2.1, 6)."""

BOX = """(selector) => {
  const element = document.querySelector(selector);
  const box = element.getBoundingClientRect();
  const style = getComputedStyle(element);
  return {top: box.top, bottom: box.bottom, left: box.left, right: box.right, width: box.width,
          height: box.height, tl: style.borderTopLeftRadius, tr: style.borderTopRightRadius,
          bl: style.borderBottomLeftRadius, br: style.borderBottomRightRadius,
          position: style.position, opacity: style.opacity};
}"""

# Opens (or closes) a dialog by clicking SELECTOR and samples, every frame
# for MS, the dialog's top and its backdrop's opacity.
SAMPLE = """async ([button, dialog, ms]) => {
  const target = document.querySelector(dialog);
  const samples = [];
  document.querySelector(button).click();
  const start = performance.now();
  while (performance.now() - start < ms) {
    await new Promise((resolve) => requestAnimationFrame(resolve));
    samples.push({top: target.getBoundingClientRect().top,
                  dim: parseFloat(getComputedStyle(target, '::backdrop').opacity)});
  }
  return samples;
}"""

CLOSE_SAMPLE = """async ([dialog, ms]) => {
  const target = document.querySelector(dialog);
  const samples = [];
  target.close();
  const start = performance.now();
  while (performance.now() - start < ms) {
    await new Promise((resolve) => requestAnimationFrame(resolve));
    samples.push(parseFloat(getComputedStyle(target, '::backdrop').opacity));
  }
  return samples;
}"""

# A keyboard over the lower part of the window: the visual viewport shrinks
# to HEIGHT, as Safari and Chrome on Android report it.
KEYBOARD = """(height) => {
  if (height === null) delete window.visualViewport.height;
  else Object.defineProperty(window.visualViewport, 'height', {configurable: true, get: () => height});
  window.visualViewport.dispatchEvent(new Event('resize'));
  return [document.documentElement.style.getPropertyValue('--tun-visual-top'),
          document.documentElement.style.getPropertyValue('--tun-visual-bottom')];
}"""

ACTIVE = """() => {
  const element = document.activeElement;
  return element ? (element.getAttribute('aria-label') || element.textContent.trim()
                    || element.tagName) : null;
}"""

IN_DIALOG = "(selector) => document.querySelector(selector).contains(document.activeElement)"

CLOSING_MENU = """async () => {
  const menu = document.querySelector('.tun-specimen-preview [data-tun-dropdown-menu] > [popover]');
  menu.hidePopover();
  const seen = (element) => element.checkVisibility({checkOpacity: false})
    && getComputedStyle(element).display !== 'none';
  await new Promise((resolve) => setTimeout(resolve, 80));
  const midway = {shown: seen(menu), opacity: parseFloat(getComputedStyle(menu).opacity)};
  await new Promise((resolve) => setTimeout(resolve, 260));
  return {midway, after: seen(menu)};
}"""

CONFIRM = """() => {
  const dialog = document.querySelector('[data-tun-confirm-dialog] > dialog');
  const ok = dialog.querySelector('[data-tun-confirm-ok]');
  const sentence = dialog.querySelector('.tun-dialog-description');
  return {open: dialog.open, question: dialog.querySelector('.tun-dialog-title').textContent,
          detail: sentence.hidden ? null : sentence.textContent, ok: ok.textContent.trim(),
          variant: ok.dataset.variant, color: getComputedStyle(ok).color,
          focus: document.activeElement?.textContent.trim()};
}"""

CONFIRM_OPEN = "() => document.querySelector('[data-tun-confirm-dialog] > dialog').open"


def rgb(text):
    return tuple(int(float(part)) for part in text[text.index("(") + 1:text.index(")")].split(",")[:3])


def never_falls(values):
    return all(b >= a - 0.001 for a, b in zip(values, values[1:]))


def never_rises(values):
    return all(b <= a + 0.001 for a, b in zip(values, values[1:]))


def counting(page, path, body="<!doctype html><title>Done</title><p>Done</p>"):
    """Answer every POST to PATH on PAGE, and count them."""
    seen = []

    def answer(route):
        if route.request.method == "POST":
            seen.append(route.request.post_data or "")
        route.fulfill(status=200, content_type="text/html", body=body)

    page.route(f"**{path}", answer)
    return seen


def sheet(t):
    for scheme in ("light", "dark"):
        page = t.phone(scheme=scheme)
        page.goto("/ui/dialog")
        samples = page.evaluate(SAMPLE, ["[commandfor=terms][command=show-modal]", "dialog#terms", 600])
        tops = [s["top"] for s in samples]
        dims = [s["dim"] for s in samples]
        t.check(len(tops) > 5 and tops[0] > tops[-1] + 100,
                f"390px {scheme}: the sheet slides up into place: {[round(x) for x in tops[:6]]} … {round(tops[-1])}")
        t.check(never_falls(dims) and dims[-1] == 1,
                f"390px {scheme}: the dim only gets darker while the sheet opens: {[round(d, 2) for d in dims[:10]]}")
        box = page.evaluate(BOX, "dialog#terms")
        t.check(abs(box["left"]) < 1 and abs(box["width"] - 390) < 1 and abs(box["bottom"] - 844) < 1,
                f"390px {scheme}: the sheet stands at the bottom at the window's width: {box}")
        t.check(box["tl"] == "12px" and box["tr"] == "12px" and box["bl"] == "0px" and box["br"] == "0px",
                f"390px {scheme}: its top corners are rounded, its bottom ones square: {box}")
        t.check(box["top"] >= 32 - 0.5, f"390px {scheme}: a strip of the page shows above it: {box['top']}")
        if scheme == "light":
            header = page.evaluate(BOX, "dialog#terms .tun-dialog-header")
            footer = page.evaluate(BOX, "dialog#terms .tun-dialog-footer")
            scrolled = page.evaluate("""() => {
              const body = document.querySelector('dialog#terms .tun-dialog-body');
              body.scrollTop = body.scrollHeight;
              return body.scrollTop;
            }""")
            header2 = page.evaluate(BOX, "dialog#terms .tun-dialog-header")
            footer2 = page.evaluate(BOX, "dialog#terms .tun-dialog-footer")
            t.check(scrolled > 50 and abs(header["top"] - header2["top"]) < 0.5
                    and abs(footer["top"] - footer2["top"]) < 0.5 and footer2["bottom"] <= box["bottom"] + 0.5
                    and header2["top"] >= box["top"],
                    f"390px: the title and the actions stay while the body scrolls {scrolled}px: "
                    f"{header['top']}→{header2['top']}, {footer['top']}→{footer2['top']}")
        closing = page.evaluate(CLOSE_SAMPLE, ["dialog#terms", 400])
        t.check(never_rises(closing) and closing[-1] < 0.05,
                f"390px {scheme}: the dim only gets lighter while it closes: {[round(d, 2) for d in closing[:8]]}")

    # A dialog with its actions in one row, «Cancel» first.
    page = t.phone()
    page.goto("/ui/dialog")
    page.locator("[commandfor=send-invoice][command=show-modal]").click()
    page.wait_for_timeout(500)
    buttons = page.evaluate("""() => [...document.querySelectorAll('dialog#send-invoice .tun-dialog-footer > *')]
      .map((b) => [b.textContent.trim(), b.getBoundingClientRect().top, b.getBoundingClientRect().left,
                   b.getBoundingClientRect().width])""")
    footer = page.evaluate(BOX, "dialog#send-invoice .tun-dialog-footer")
    t.check(len(buttons) == 2 and buttons[0][0] == "Cancel" and abs(buttons[0][1] - buttons[1][1]) < 1
            and buttons[0][2] < buttons[1][2] and buttons[0][3] + buttons[1][3] > footer["width"] - 12,
            f"390px: the buttons share one row, «Cancel» first, filling it: {buttons}")

    # A dialog without a footer opens as a sheet too.
    page.locator("dialog#send-invoice").evaluate("(d) => d.close()")
    page.wait_for_timeout(300)
    page.locator("[commandfor=shortcuts][command=show-modal]").click()
    page.wait_for_timeout(500)
    box = page.evaluate(BOX, "dialog#shortcuts")
    t.check(abs(box["bottom"] - 844) < 1 and abs(box["width"] - 390) < 1,
            f"390px: a dialog without a footer is a sheet too: {box}")

    # From 40rem: centred, all corners rounded, rising as it fades in.
    for scheme in ("light", "dark"):
        page = t.desktop(scheme=scheme)
        page.goto("/ui/dialog")
        samples = page.evaluate(SAMPLE, ["[commandfor=send-invoice][command=show-modal]", "dialog#send-invoice", 500])
        dims = [s["dim"] for s in samples]
        t.check(never_falls(dims) and dims[-1] == 1,
                f"1280px {scheme}: the dim only gets darker while the dialog opens: {[round(d, 2) for d in dims[:10]]}")
        tops = [s["top"] for s in samples]
        t.check(tops[0] > tops[-1] and tops[0] - tops[-1] <= 8.5,
                f"1280px {scheme}: the dialog rises a few pixels: {round(tops[0], 1)} → {round(tops[-1], 1)}")
        box = page.evaluate(BOX, "dialog#send-invoice")
        # Centred in the window less the room the page's scroll bar keeps.
        t.check(abs((box["left"] + box["right"]) / 2 - 640) <= 8 and abs(box["width"] - 448) < 1
                and box["bl"] == "12px" and box["tl"] == "12px",
                f"1280px {scheme}: centred, 28rem wide, every corner rounded: {box}")
        dim_colour = page.evaluate("() => getComputedStyle(document.querySelector('dialog#send-invoice'), '::backdrop').backgroundColor")
        t.check(dim_colour == ("rgba(0, 0, 0, 0.4)" if scheme == "light" else "rgba(0, 0, 0, 0.54)"),
                f"1280px {scheme}: the dim is --overlay: {dim_colour}")


def keyboard(t):
    page = t.phone()
    page.goto("/ui/dialog")
    page.locator("[commandfor=add-note][command=show-modal]").click()
    page.wait_for_timeout(50)
    first = page.evaluate(BOX, "dialog#add-note")
    page.wait_for_timeout(500)
    box = page.evaluate(BOX, "dialog#add-note")
    t.check(abs(box["height"] - (844 - 32)) < 1 and abs(first["height"] - box["height"]) < 1,
            f"390px: a dialog to type in is as tall as it may be from the start: {first['height']}, {box['height']}")
    focused = page.evaluate("() => document.activeElement.tagName")
    t.check(focused == "TEXTAREA", f"its first control, the text area, has the focus: {focused}")
    inset = page.evaluate(KEYBOARD, 400)
    page.wait_for_timeout(100)
    shrunk = page.evaluate(BOX, "dialog#add-note")
    footer = page.evaluate(BOX, "dialog#add-note .tun-dialog-footer")
    field = page.evaluate(BOX, "dialog#add-note textarea")
    t.check(inset == ["0px", "444px"], f"the script writes where the keyboard is: {inset}")
    t.check(abs(shrunk["bottom"] - 400) < 1 and abs(shrunk["top"] - box["top"]) < 1,
            f"with a keyboard the dialog's bottom edge moves up and its top stays: {box['top']}→{shrunk['top']}, bottom {shrunk['bottom']}")
    t.check(footer["bottom"] <= 400.5 and field["top"] >= shrunk["top"] and field["bottom"] <= footer["top"] + 0.5,
            f"the actions and the field stay above the keyboard: footer {footer['bottom']}, field {field['top']}–{field['bottom']}")
    page.evaluate(KEYBOARD, None)
    page.locator("dialog#add-note").evaluate("(d) => d.close()")
    page.wait_for_timeout(300)
    left = page.evaluate("""() => [document.documentElement.style.getPropertyValue('--tun-visual-bottom'),
                                   document.documentElement.style.overflow]""")
    t.check(left == ["", ""], f"closed, nothing of the keyboard or the hold is left: {left}")

    # The page behind does not scroll while a dialog is open.
    page = t.desktop()
    page.goto("/ui/dialog")
    page.locator("[commandfor=terms][command=show-modal]").click()
    page.wait_for_timeout(400)
    before = page.evaluate("() => scrollY")
    page.mouse.move(40, 400)
    page.mouse.wheel(0, 600)
    page.wait_for_timeout(300)
    held = page.evaluate("() => [scrollY, getComputedStyle(document.documentElement).overflow]")
    t.check(held[0] == before and held[1] == "hidden", f"the page behind holds still: {before}, {held}")


def focus_and_keys(t):
    page = t.desktop()
    page.goto("/ui/dialog")
    opener = page.locator("[commandfor=send-invoice][command=show-modal]")
    opener.click()
    page.wait_for_timeout(300)
    t.check(page.evaluate(ACTIVE) == "Cancel", f"opening puts the focus on the first control: {page.evaluate(ACTIVE)}")
    page.keyboard.press("Shift+Tab")
    t.check(page.evaluate(ACTIVE) == "Close", f"Shift+Tab from the first goes round to the last: {page.evaluate(ACTIVE)}")
    inside = True
    for _ in range(5):
        page.keyboard.press("Tab")
        inside = inside and page.evaluate(IN_DIALOG, "dialog#send-invoice")
    t.check(inside, "Tab stays inside the dialog")
    page.keyboard.press("Escape")
    page.wait_for_timeout(300)
    t.check(not page.locator("dialog#send-invoice").evaluate("(d) => d.open")
            and page.evaluate(ACTIVE) == "Send invoice",
            f"Escape closes it and the focus goes back to its button: {page.evaluate(ACTIVE)}")
    page.locator("[commandfor=search][command=show-modal]").click()
    page.wait_for_timeout(300)
    t.check(page.evaluate("() => document.activeElement.name") == "q",
            "a dialog with an autofocus field opens on it")


def menus(t):
    page = t.desktop()
    page.goto("/ui/dropdown-menu")
    page.locator(".tun-specimen-preview [data-tun-dropdown-menu] > .tun-button").first.click()
    page.wait_for_timeout(300)
    seen = page.evaluate(CLOSING_MENU)
    t.check(seen["midway"]["shown"] and 0 < seen["midway"]["opacity"] < 1 and not seen["after"],
            f"a closing menu is still in the page at 80ms, fading, and gone after --duration-close: {seen}")
    page.locator(".tun-specimen-preview [data-tun-dropdown-menu] > .tun-button").first.click()
    page.wait_for_timeout(30)
    rising = page.evaluate("() => getComputedStyle(document.querySelector('.tun-specimen-preview [data-tun-dropdown-menu] > [popover]')).translate")
    t.check(rising not in ("none", "0px"), f"an opening menu rises into place: translate {rising}")


def confirm(t):
    for width in (390, 1280):
        page = t.phone() if width < 600 else t.desktop()
        posts = counting(page, "/orders/1042/delete")
        page.goto("/ui/confirm-dialog")
        delete = page.locator("form[action='/orders/1042/delete'] button")
        delete.click()
        page.wait_for_timeout(400)
        shown = page.evaluate(CONFIRM)
        t.check(shown["open"] and shown["question"] == "Delete order 1042?"
                and shown["detail"] == "The order and all its lines are deleted for good."
                and shown["ok"] == "Delete order" and shown["variant"] == "destructive",
                f"{width}px: the confirm asks the question, says what happens and repeats the action: {shown}")
        red = rgb(shown["color"])
        t.check(red[0] > red[1] + 80, f"{width}px: a destructive action is red words: {shown['color']}")
        t.check(shown["focus"] == "Cancel", f"{width}px: the focus starts on «Cancel»: {shown['focus']}")
        if width < 600:
            box = page.evaluate(BOX, "[data-tun-confirm-dialog] > dialog")
            t.check(abs(box["bottom"] - 844) < 1 and abs(box["width"] - 390) < 1,
                    f"390px: the confirm is a sheet: {box}")
        page.keyboard.press("Escape")
        page.wait_for_timeout(300)
        t.check(not page.evaluate(CONFIRM_OPEN) and not posts and page.evaluate(ACTIVE) == "Delete order",
                f"{width}px: Escape closes it, nothing is sent, the focus is back: {page.evaluate(ACTIVE)}, {len(posts)}")
        delete.click()
        page.wait_for_timeout(300)
        page.locator("[data-tun-confirm-cancel]").first.click()
        page.wait_for_timeout(300)
        t.check(not page.evaluate(CONFIRM_OPEN) and not posts, f"{width}px: «Cancel» sends nothing")
        delete.click()
        page.wait_for_timeout(300)
        with page.expect_navigation():
            page.locator("[data-tun-confirm-ok]").first.click()
        page.wait_for_timeout(300)
        t.check(len(posts) == 1, f"{width}px: the action posts the form once: {len(posts)}")

    page = t.desktop()
    sends = counting(page, "/invoices/2024-117/send")
    page.goto("/ui/confirm-dialog")
    page.locator("form[action='/invoices/2024-117/send'] button").click()
    page.wait_for_timeout(300)
    shown = page.evaluate(CONFIRM)
    t.check(shown["variant"] == "primary" and shown["ok"] == "Send invoice" and shown["focus"] == "Send invoice",
            f"an action without danger is the primary button and has the focus: {shown}")
    with page.expect_navigation():
        page.keyboard.press("Enter")
    t.check(len(sends) == 1, f"Enter on it posts once: {len(sends)}")

    page = t.desktop()
    page.route("**/orders", lambda route: route.fulfill(status=200, content_type="text/html",
                                                        body="<!doctype html><title>Orders</title>"))
    page.goto("/ui/confirm-dialog")
    page.locator(".tun-specimen-preview a[data-tun-confirm]").click()
    page.wait_for_timeout(300)
    shown = page.evaluate(CONFIRM)
    t.check(shown["ok"] == "Leave" and shown["detail"] == "What you changed is lost.",
            f"a link asks too, with the action's own words: {shown}")
    with page.expect_navigation():
        page.locator("[data-tun-confirm-ok]").first.click()
    t.check(page.url.endswith("/orders"), f"and is followed once agreed: {page.url}")

    page = t.desktop()
    archived = counting(page, "/orders/1042/archive", body="")
    page.goto("/ui/confirm-dialog")
    archive = page.locator(".tun-specimen-preview button[hx-confirm]", has_text="Archive").first
    archive.click()
    page.wait_for_timeout(300)
    shown = page.evaluate(CONFIRM)
    t.check(shown["open"] and shown["question"] == "Archive order 1042?"
            and shown["detail"] == "It leaves the list of open orders." and shown["ok"] == "Archive",
            f"hx-confirm asks in the same dialog: {shown}")
    page.locator("[data-tun-confirm-cancel]").first.click()
    page.wait_for_timeout(400)
    t.check(not archived, f"«Cancel» drops htmx's request: {len(archived)}")
    archive.click()
    page.wait_for_timeout(300)
    page.locator("[data-tun-confirm-ok]").first.click()
    page.wait_for_timeout(800)
    t.check(len(archived) == 1, f"the action sends htmx's request once: {len(archived)}")

    # Words past 40 characters give «Confirm»; an hx-confirm without a
    # question is all question.
    page = t.desktop()
    finished = counting(page, "/orders/archive-finished", body="")
    page.goto("/ui/confirm-dialog")
    page.locator(".tun-specimen-preview button", has_text="Send a reminder of every unpaid").click()
    page.wait_for_timeout(300)
    shown = page.evaluate(CONFIRM)
    t.check(shown["question"] == "Send 12 reminders?" and shown["ok"] == "Confirm",
            f"a control whose words run past 40 characters gives the action «Confirm»: {shown}")
    page.locator("[data-tun-confirm-cancel]").first.click()
    page.wait_for_timeout(300)
    page.locator(".tun-specimen-preview button", has_text="Archive the finished orders").click()
    page.wait_for_timeout(300)
    shown = page.evaluate(CONFIRM)
    t.check(shown["question"] == "Every finished order is archived." and shown["detail"] is None
            and shown["ok"] == "Archive the finished orders",
            f"an hx-confirm without «?» is all question, with no sentence: {shown}")
    page.locator("[data-tun-confirm-ok]").first.click()
    page.wait_for_timeout(800)
    t.check(len(finished) == 1, f"and its request goes once agreed: {len(finished)}")
    ids = page.evaluate("() => [...document.querySelectorAll('[id]')].map((e) => e.id)")
    t.check(len(ids) == len(set(ids)), f"no id twice on the page: {sorted({i for i in ids if ids.count(i) > 1})}")

    # From inside a dialog: Escape closes the confirm only.
    page = t.desktop()
    page.goto("/ui/confirm-dialog")
    page.locator("[commandfor=edit-order][command=show-modal]").click()
    page.wait_for_timeout(300)
    page.locator("dialog#edit-order button", has_text="Delete").click()
    page.wait_for_timeout(300)
    page.keyboard.press("Escape")
    page.wait_for_timeout(300)
    state = page.evaluate("() => [document.querySelector('dialog#edit-order').open, document.querySelector('[data-tun-confirm-dialog] > dialog').open, document.activeElement.textContent.trim()]")
    t.check(state == [True, False, "Delete"], f"Escape closes the top one only, the focus back on «Delete»: {state}")


def toast(t):
    page = t.desktop()
    page.goto("/ui/flash")
    page.wait_for_timeout(500)
    box = page.evaluate(BOX, ".tun-specimen-preview .tun-flash:not([data-placement])")
    t.check(box["position"] == "fixed" and abs(box["top"] - 16) < 1 and abs(box["right"] - (1280 - 16)) < 1
            and box["width"] <= 400.5,
            f"1280px: a flash is a toast at the top right: {box}")
    page.wait_for_timeout(3500)
    t.check(page.locator(".tun-flash:not([data-placement])").count() == 1, "it is still there after 4 seconds")
    page.wait_for_timeout(2000)
    t.check(page.locator(".tun-flash:not([data-placement])").count() == 0, "and has left after 5 seconds")
    t.check(page.locator(".tun-flash[data-placement=page]").count() >= 4, "a flash in the page stays")

    page = t.desktop()
    page.goto("/ui/flash")
    page.locator(".tun-flash:not([data-placement])").hover()
    page.wait_for_timeout(6000)
    t.check(page.locator(".tun-flash:not([data-placement])").count() == 1, "pointed at, it stays")
    page.mouse.move(5, 790)
    page.wait_for_timeout(5600)
    t.check(page.locator(".tun-flash:not([data-placement])").count() == 0, "and leaves once the pointer has gone")

    # A warning stays until closed.
    page.evaluate("""() => {
      const flash = document.querySelector('.tun-flash[data-placement=page][data-variant=warning]').cloneNode(true);
      flash.removeAttribute('data-placement');
      document.querySelector('.tun-specimen-preview').append(flash);
      flash.dispatchEvent(new Event('htmx:after:settle', {bubbles: true}));
    }""")
    page.wait_for_timeout(6000)
    warning = page.locator(".tun-flash:not([data-placement])[data-variant=warning]")
    t.check(warning.count() == 1, "a warning stays after 5 seconds")
    warning.locator("[data-tun-flash-close]").click()
    page.wait_for_timeout(400)
    t.check(warning.count() == 0, "until it is closed")

    page = t.phone()
    page.goto("/ui/flash")
    page.wait_for_timeout(500)
    box = page.evaluate(BOX, ".tun-specimen-preview .tun-flash:not([data-placement])")
    t.check(box["position"] == "fixed" and abs(box["bottom"] - (844 - 16)) < 1 and abs(box["left"] - 16) < 1
            and abs(box["width"] - (390 - 32)) < 1,
            f"390px: a toast at the bottom of the phone: {box}")

    page = t.desktop(javascript=False)
    page.goto("/ui/flash")
    box = page.evaluate(BOX, ".tun-specimen-preview .tun-flash")
    page.wait_for_timeout(6000)
    t.check(box["position"] == "static" and page.locator(".tun-specimen-preview .tun-flash").count() >= 5,
            f"without JavaScript a flash stands in the page and stays: {box['position']}")


def without_javascript(t):
    page = t.phone(javascript=False)
    sent = counting(page, "/invoices/2024-117/send")
    page.goto("/ui/dialog")
    page.locator("[commandfor=send-invoice][command=show-modal]").click()
    page.wait_for_timeout(500)
    box = page.evaluate(BOX, "dialog#send-invoice")
    t.check(abs(box["bottom"] - 844) < 1, f"without JavaScript a dialog opens with its button, a sheet: {box}")
    with page.expect_navigation():
        page.locator("dialog#send-invoice button[type=submit]").click()
    t.check(len(sent) == 1, f"and its form posts: {len(sent)}")


def reduced_motion(t):
    page = t.phone()
    page._page.emulate_media(reduced_motion="reduce")
    page.goto("/ui/dialog")
    samples = page.evaluate(SAMPLE, ["[commandfor=terms][command=show-modal]", "dialog#terms", 120])
    tops = {round(s["top"]) for s in samples}
    t.check(tops <= {844, 32} and all(s["dim"] in (0, 1) for s in samples) and samples[-1]["top"] == 32,
            f"under reduced motion the sheet stands at once and the page dims at once: {samples[:4]}")
    page = t.desktop()
    page._page.emulate_media(reduced_motion="reduce")
    page.goto("/ui/dropdown-menu")
    page.locator(".tun-specimen-preview [data-tun-dropdown-menu] > .tun-button").first.click()
    page.wait_for_timeout(100)
    seen = page.evaluate(CLOSING_MENU)
    t.check(not seen["midway"]["shown"], f"under reduced motion a menu is gone at once: {seen}")


def run(t):
    sheet(t)
    keyboard(t)
    focus_and_keys(t)
    menus(t)
    confirm(t)
    toast(t)
    without_javascript(t)
    reduced_motion(t)
