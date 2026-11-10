# The test client's module `logbook`

ASDF system `tun-logbook`, package `tun.logbook`: a module kept in a
client's repository (tun-platform.md §2.1), the test client's own, so that
Tun's suite runs the checks such a module gets on one (testing.md §1,
tests 2 and 10).

- **Owns:** `logbook_entry`; `logbook_add`, `logbook_list`.
- **Depends on:** none. A note's subject is an id the module does not look
  up.
- **Core range:** `>= 2.19.0, < 3.0`.
