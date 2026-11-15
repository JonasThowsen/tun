"""A card's file control in Norwegian and in English, at 390 and 1280 px,
with JavaScript and without: the browser's own control paints nothing and
lies over Tun's button, which reads in the page's language; with JavaScript
a line beside it says what is chosen; the input stays the control, named by
its label, reached by Tab, showing the focus ring on the button, and a click
on the button opens the browser's chooser (spec/files.md 6.1)."""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _files  # noqa: E402

SCENARIO = "norwegian"

CONTROL = ".tun-card input[type=file][name=files]"

TEXTS = {
    "nb": {"button": "Velg filer", "none": "Ingen filer valgt", "two": "Valgt: 2"},
    "en": {"button": "Choose files", "none": "No files chosen", "two": "Chosen: 2"},
}

# The picker's parts: the input, Tun's button and the line beside it.
PARTS = """(input) => {
  const picker = input.closest('.tun-file-input-picker');
  const box = (e) => { const r = e.getBoundingClientRect();
                       return {left: r.left, top: r.top, right: r.right, bottom: r.bottom}; };
  const button = picker.querySelector('.tun-file-input-button');
  const status = picker.querySelector('.tun-file-input-status');
  return {opacity: getComputedStyle(input).opacity, input: box(input), button: box(button),
          buttonText: button.textContent, buttonShadow: getComputedStyle(button).boxShadow,
          statusHidden: status.hidden || getComputedStyle(status).display === 'none',
          statusText: status.textContent,
          labels: Array.from(input.labels).map((l) => l.textContent.trim()),
          wide: document.documentElement.scrollWidth > window.innerWidth};
}"""


def covers(outer, inner):
    return (outer["left"] <= inner["left"] + 0.5 and outer["top"] <= inner["top"] + 0.5
            and outer["right"] >= inner["right"] - 0.5 and outer["bottom"] >= inner["bottom"] - 0.5)


def set_english(page):
    """As Jonas, set the tenant's language back to English on «Innstillinger»."""
    page.goto("/settings")
    page.locator("#setting-locale-language").select_option(value="en")
    form = page.locator("form").filter(has=page.locator("#setting-locale-language"))
    form.locator("button[type=submit]").first.click()
    page.wait_for_url(re.compile(r"saved=locale\.language"))


def tab_to(page, selector, most=60):
    """Press Tab until the element SELECTOR has the focus; whether it did."""
    for _ in range(most):
        page.keyboard.press("Tab")
        if page.evaluate("(s) => document.activeElement === document.querySelector(s)", selector):
            return True
    return False


def control_in(t, language, width, make, javascript):
    page = make(javascript=javascript)
    page.sign_in("employee:anna")
    _files.card_page(page, "Item 3")
    say = TEXTS[language]
    where = f"{language}, {width}px, {'with' if javascript else 'without'} JavaScript"
    t.check(page.evaluate("document.documentElement.lang") == language, f"{where}: the page's language")
    control = page.locator(CONTROL)
    parts = control.evaluate(PARTS)
    t.check(parts["opacity"] == "0", f"{where}: the browser's control paints nothing: {parts['opacity']}")
    t.check(covers(parts["input"], parts["button"]), f"{where}: and lies over the button: {parts}")
    t.check(parts["buttonText"] == say["button"], f"{where}: the button reads «{parts['buttonText']}»")
    t.check(parts["labels"] and parts["labels"][0], f"{where}: the label names the input: {parts['labels']}")
    t.check(not parts["wide"], f"{where}: the page does not scroll sideways")
    if javascript:
        t.check(not parts["statusHidden"] and parts["statusText"] == say["none"],
                f"{where}: the line reads «{parts['statusText']}»")
    else:
        t.check(parts["statusHidden"], f"{where}: no line without a script, which alone knows what is chosen")
    page.screenshot(path=str(t.out / f"files-language-{language}-{width}-{'js' if javascript else 'nojs'}.png"))
    if javascript:
        control.set_input_files([_files.path("screenshot.png"), _files.path("receipt.pdf")])
        parts = control.evaluate(PARTS)
        t.check(parts["statusText"] == say["two"], f"{where}: two chosen: «{parts['statusText']}»")
        page.screenshot(path=str(t.out / f"files-language-{language}-{width}-chosen.png"))
    if width > 600:
        t.check(tab_to(page, CONTROL), f"{where}: Tab reaches the input")
        shadow = control.evaluate(PARTS)["buttonShadow"]
        t.check(shadow and shadow != "none", f"{where}: the button shows the focus ring: {shadow}")
    button = parts["button"]
    with page.expect_file_chooser() as chooser:
        page.mouse.click((button["left"] + button["right"]) / 2, (button["top"] + button["bottom"]) / 2)
    t.check(chooser.value.element.evaluate("(e) => e.name") == "files",
            f"{where}: a click on the button opens the browser's chooser for the input")


def run(t):
    for language in ("nb", "en"):
        if language == "en":
            admin = t.desktop()
            admin.sign_in("admin:jonas")
            set_english(admin)
        for width, make in ((390, t.phone), (1280, t.desktop)):
            for javascript in (True, False):
                control_in(t, language, width, make, javascript)
