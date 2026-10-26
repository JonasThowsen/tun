# Where the design system comes from

The components in `src/web/ui/` are converted from these projects
(`spec/ui.md` §1). Each component's `:source` names the one it follows.
Their licences ask that the copyright and permission notices travel with
copies of their work; this file is that notice for Tun's repository and
images.

| Project | Revision converted | Licence | Copyright |
|---|---|---|---|
| [Basecoat](https://github.com/hunvreus/basecoat) | `6953a4a` | MIT | Copyright (c) 2025 Ronan Berder |
| [GOV.UK Frontend](https://github.com/alphagov/govuk-frontend) | `11d8c85` | MIT | Copyright (C) 2017 Crown Copyright (Government Digital Service) |
| [Designsystemet](https://github.com/digdir/designsystemet) | `e2ed5f4` | MIT | Copyright Digitaliseringsdirektoratet (Digdir) |
| [Lucide](https://github.com/lucide-icons/lucide) | `dab294f` | ISC; icons from Feather also MIT | Copyright (c) 2026 Lucide Icons and Contributors; Feather icons Copyright (c) 2013-present Cole Bemis |

Aksel (NAV, MIT) is read for wording and accessibility; no code is copied
from it.

## htmx

`src/web/ui/htmx.min.js` is [htmx](https://github.com/bigskysoftware/htmx)
4.0.0, `dist/htmx.min.js` from the npm package `htmx.org@4.0.0` unchanged
(npm shasum `72323bd24261364fe3111803c46b80da1fb33445`), whose SHA-256 is
`e484d9171a9db30a39c8f16e3d709d4137f3211c659f8e6125816635033d593f`. Its
licence is Zero-Clause BSD, which asks for no notice; it is the ISC
text below without the notice clause. To move to a newer htmx, replace
the file, update the version and hash here and in `spec/ui.md` §4.1, and
read the release notes for changed defaults of the configuration Tun
sets and for changes to `initSecurity`, which Tun's extension uses.

## MIT licence (Basecoat, GOV.UK Frontend, Designsystemet, Feather)

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
USE OR OTHER DEALINGS IN THE SOFTWARE.

## ISC licence (Lucide)

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
