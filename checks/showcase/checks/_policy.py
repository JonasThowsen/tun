"""What the policy checks share (spec/ui.md 4): a record, kept in the page,
of every Content-Security-Policy violation the browser reports.

A file whose name starts with _ is not a check (spec/preview.md 4)."""

# Playwright adds this to every document before the page's own scripts;
# the browser lets it in whatever the policy says.
RECORDER = """
window.__violations = [];
document.addEventListener('securitypolicyviolation', (event) => {
  window.__violations.push(`${event.effectiveDirective} ${event.blockedURI || 'inline'}`);
});
"""


def record(page):
    """Record PAGE's violations from its next document on; also its console's."""
    page.add_init_script(RECORDER)
    page.console_violations = []
    page.on("console", lambda message: page.console_violations.append(message.text)
            if "Content Security Policy" in message.text else None)


def violations(page):
    """The violations on the document PAGE shows, and those its console
    reported since the last call."""
    found = page.evaluate("window.__violations || []") + page.console_violations
    page.console_violations.clear()
    return found
