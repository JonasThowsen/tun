;;;; tests/markdown-tests.lisp -- MARKDOWN: text people and agents write
;;;; (spec/ui.md 6.2): its blocks and inline marks, what shows as written,
;;;; the links it makes and refuses, and its bounds.

(in-package #:tun.tests)

(def-suite markdown :in core)
(in-suite markdown)

(defun md (text &rest options)
  "The HTML of TEXT as MARKDOWN with OPTIONS, inside its root."
  (let* ((html (with-language ("en")
                 (tun.html:render-html (tun.ui:markdown* (list* :text text options)))))
         (open (length "<div class=\"tun-markdown\">")))
    (assert (eql 0 (search "<div class=\"tun-markdown\">" html)))
    (subseq html open (- (length html) (length "</div>")))))

(defun md-lines (&rest lines)
  "LINES as one text, a newline after each but the last."
  (format nil "~{~a~^~%~}" lines))

;;; ------------------------------------------------------------------
;;; Blocks

(test paragraphs-keep-their-line-breaks
  (is (string= "<p>Hei<br>andre linje</p><p>Ny avsnitt</p>"
               (md (md-lines "Hei" "andre linje" "" "" "Ny avsnitt"))))
  (is (string= "" (md nil)) "NIL is the empty text")
  (is (string= "" (md (md-lines "" "   " ""))) "blank lines make nothing"))

(test headings-stay-below-the-page
  (is (string= "<h3 data-level=\"1\">Tittel</h3><h4 data-level=\"2\">Under</h4><h4 data-level=\"2\">Dypere</h4><p>#12 er en sak</p>"
               (md (md-lines "# Tittel" "## Under ##" "#### Dypere" "#12 er en sak"))))
  (is (string= "<h2 data-level=\"1\">A</h2><h3 data-level=\"2\">B</h3>"
               (md (md-lines "# A" "## B") :heading-level 2)))
  (is (string= "<h5 data-level=\"1\">A</h5><h6 data-level=\"2\">B</h6>"
               (md (md-lines "# A" "## B") :heading-level 5)))
  (signals error (md "# A" :heading-level 6))
  (signals error (md "# A" :heading-level 1))
  (is (string= "<h3 data-level=\"1\"></h3>" (md "#")) "a # alone is an empty heading")
  (is (string= "<p>Tekst</p><h3 data-level=\"1\">Ny</h3>" (md (md-lines "Tekst" "# Ny")))
      "a heading ends a paragraph"))

(test lists-nest-by-indentation
  (is (string= "<ul><li>a</li><li>b<ul><li>c<ul><li>d<ul><li>e</li><li>f</li></ul></li></ul></li></ul></li><li>g<br>fortsetter</li></ul>"
               (md (md-lines "- a" "- b" "  - c" "    - d" "      - e" "        - f" "- g" "fortsetter")))
      "four levels at most, a line that is no marker continuing its item")
  (is (string= "<ol><li>en</li><li>to</li></ol>" (md (md-lines "1. en" "2) to"))))
  (is (string= "<ol start=\"3\"><li>tre</li></ol>" (md "3. tre")) "the first number is kept")
  (is (string= "<ul><li>a</li><li>b</li></ul>" (md (md-lines "* a" "" "+ b")))
      "a blank line between items keeps the list")
  (is (string= "<ul><li>a</li></ul><p>etter</p>" (md (md-lines "- a" "" "etter")))
      "after a blank line, only an item goes on")
  (is (string= "<ul><li>a</li></ul><ol><li>b</li></ol>" (md (md-lines "- a" "1. b")))
      "a marker of the other kind starts a new list")
  (is (string= "<ul><li>a</li></ul><h3 data-level=\"1\">H</h3>" (md (md-lines "- a" "# H"))))
  (is (string= "<p>Møtet er<br>2. mai</p><ul><li>punkt</li></ul>"
               (md (md-lines "Møtet er" "2. mai" "- punkt")))
      "an ordered list from 1 only, and any unordered one, ends a paragraph")
  (is (string= "<ol start=\"17\"><li>mai er fridag</li></ol>" (md "17. mai er fridag")))
  (is (string= "<p>-ikke<br>-</p>" (md (md-lines "-ikke" "-"))) "a marker needs a space and text"))

(test code-blocks-are-written-as-they-are
  (let ((html (md (md-lines "```lisp" "(+ 1 2)" "<b>**x**</b>" "```" "etter"))))
    (is (search "<code class=\"tun-code-block-code\" id=\"tun-code-" html))
    (is (search ">(+ 1 2)
&lt;b&gt;**x**&lt;/b&gt;</code>" html) "the lines as written, no marks read")
    (is (search "<p>etter</p>" html))
    (is (not (search "lisp" html)) "the language is not shown"))
  (is (search ">a
```
b</code>" (md (md-lines "````" "a" "```" "b" "````"))) "a shorter run closes nothing")
  (is (search ">uavsluttet
**x**</code>" (md (md-lines "```" "uavsluttet" "**x**"))) "an unclosed fence runs to the end")
  (is (search ">a
 b</code>" (md (md-lines "  ```" "  a" "   b" "  ```"))) "the fence's indent is taken from its lines")
  (is (search "<p>``` `x</p>" (md "``` `x")) "a fence with a backtick after it is text")
  (is (search (format nil ">all:~%~cmake~%~c~cx</code>" #\Tab #\Tab #\Tab)
              (md (format nil "```~%all:~%~cmake~%~c~cx~%```" #\Tab #\Tab #\Tab)))
      "its tabs are kept"))

(test rules-separate-sections
  (is (string= "<hr><hr><hr>" (md (md-lines "---" "***" "_ _ _"))))
  (is (string= "<p>tekst</p><hr>" (md (md-lines "tekst" "---"))) "under text too, no heading")
  (is (string= "<p>--</p>" (md "--")))
  (is (string= "<ul><li>- -x</li></ul>" (md "- - -x")) "a rule holds nothing else"))

;;; ------------------------------------------------------------------
;;; Tables

(defun cells-of (html tag)
  (cl-ppcre:all-matches-as-strings (format nil "<~a[^>]*>.*?</~a>" tag tag) html))

(test tables-of-three-columns-or-fewer
  (let ((html (md (md-lines "| Steg | Hvem | Når |" "|:--|:-:|--:|" "| Plan | Kari | mandag |"
                         "| Bygg | **en agent** |"))))
    (is (search "<div class=\"tun-markdown-table\"><table><thead><tr><th scope=\"col\" data-align=\"start\">Steg</th><th scope=\"col\" data-align=\"center\">Hvem</th><th scope=\"col\" data-align=\"end\">Når</th></tr></thead>" html))
    (is (search "<tr><td data-align=\"start\"><span class=\"tun-markdown-table-value\">Bygg</span></td><td data-align=\"center\"><span class=\"tun-markdown-table-value\"><strong>en agent</strong></span></td></tr>" html)
        "a short row stays short")
    (is (not (search "data-wide" html)))
    (is (not (search "tun-markdown-table-label" html)) "no headings in the cells")))

(test a-table-of-ten-columns-becomes-cards
  (let* ((header (format nil "|~{ K~d |~}" (loop for i from 1 to 10 collect i)))
         (delimiter (format nil "|~{~a~}" (loop repeat 10 collect "---|")))
         (row (format nil "|~{ v~d |~}" (loop for i from 1 to 12 collect i)))
         (html (md (md-lines header delimiter row "| a | | c |"))))
    (is (search "<div class=\"tun-markdown-table\" data-wide=\"true\">" html))
    (is (= 10 (length (cells-of html "th"))))
    (is (search "<td><span class=\"tun-markdown-table-label\">K1</span><span class=\"tun-markdown-table-value\">v1</span></td>" html)
        "each value has its heading before it")
    (is (not (search "v11" html)) "cells past the headings are left out")
    (is (search "<td><span class=\"tun-markdown-table-value\"></span></td><td><span class=\"tun-markdown-table-label\">K3</span>" html)
        "an empty cell has no heading")))

(test a-card-s-heading-is-text-cut-at-80
  (let* ((long (make-string 100 :initial-element #\x))
         (html (md (md-lines (format nil "| **Fet** | b | c | ~a |" long) "|-|-|-|-|" "| 1 | 2 | 3 | 4 |"))))
    (is (search "<span class=\"tun-markdown-table-label\">Fet</span>" html) "without its marks")
    (is (search (format nil "<span class=\"tun-markdown-table-label\">~a…</span>" (subseq long 0 79)) html))))

(test what-is-not-a-table
  (let ((header (format nil "|~{ ~d |~}" (loop for i from 1 to 21 collect i)))
        (delimiter (format nil "|~{~a~}" (loop repeat 21 collect "-|"))))
    (is (search "<p>|" (md (md-lines header delimiter "| a |"))) "21 columns stay a paragraph"))
  (is (search "<p>" (md (md-lines "| a | b |" "|---|"))) "the delimiter row must match the headings")
  (is (search "<p>" (md (md-lines "| a |" "| x |"))) "and be made of dashes")
  (is (search "<td><span class=\"tun-markdown-table-value\">a | b</span></td>"
              (md (md-lines "| x |" "|---|" "| a \\| b |")))
      "an escaped | is in its cell")
  (is (search "</table></div><p>etter</p>" (md (md-lines "| x |" "|---|" "| 1 |" "etter")))
      "a line with no | ends the table")
  (is (search "</table></div><ul><li>x | y</li></ul>" (md (md-lines "| x |" "|---|" "| 1 |" "- x | y")))
      "so does a list, as any block"))

;;; ------------------------------------------------------------------
;;; Inline

(test bold-italic-and-code
  (is (string= "<p><strong>fet</strong> og <em>kursiv</em> og <em><strong>begge</strong></em> og <strong>fet</strong> <em>og</em></p>"
               (md "**fet** og *kursiv* og ***begge*** og __fet__ _og_")))
  (is (string= "<p>snake_case_name og un<em>frig</em>ly</p>" (md "snake_case_name og un*frig*ly")))
  (is (string= "<p><strong>a <em>b</em> c</strong></p>" (md "**a *b* c**")) "inner marks first")
  (is (string= "<p>2 * 3 * 4</p>" (md "2 * 3 * 4")) "a mark before a space opens nothing")
  (is (string= "<p><code>kode **ikke**</code> og <code>a ` b</code> og <code> </code></p>"
               (md "`kode **ikke**` og `` a ` b `` og ` `")))
  (is (string= "<p><code>to linjer</code></p>" (md (md-lines "`to" "linjer`"))))
  (is (string= "<p>*ikke* \\ C:\\Users</p>" (md "\\*ikke\\* \\ C:\\Users")) "escapes")
  (is (string= "<p>****for mange****</p>" (md "****for mange****")) "a run over three is text"))

(test unterminated-marks-show-as-written
  (dolist (text '("**uavsluttet" "*a" "`kode" "``a`" "[lenke" "[tekst](" "[tekst](/a" "[a](</a)" "<a.no" "_a" "***a**"
                  "[a](/a \"tittel)"))
    (is (string= (format nil "<p>~a</p>" (tun.html:escape-html text)) (md text))
        "~s shows as written" text)))

(test links-to-what-is-safe
  (flet ((link (href text) (format nil "<a class=\"tun-link\" href=\"~a\">~a</a>" href text)))
    (is (string= (format nil "<p>~a</p>" (link "https://a.no/x" "lenke")) (md "[lenke](https://a.no/x)")))
    (is (string= (format nil "<p>~a</p>" (link "http://a.no" "<em>fet</em> <code>kode</code>"))
                 (md "[*fet* `kode`](http://a.no)")))
    (is (string= (format nil "<p>~a</p>" (link "mailto:kari@a.no" "Kari")) (md "[Kari](mailto:kari@a.no)")))
    (is (string= (format nil "<p>~a</p>" (link "MAILTO:kari@a.no" "Kari")) (md "[Kari](MAILTO:kari@a.no)")))
    (is (string= (format nil "<p>~a</p>" (link "/saker/12" "sak 12")) (md "[sak 12](/saker/12)")))
    (is (string= (format nil "<p>~a</p>" (link "https://no.wikipedia.org/wiki/Tun_(gård)" "Tun"))
                 (md "[Tun](https://no.wikipedia.org/wiki/Tun_(gård))"))
        "balanced parentheses in the address")
    (is (string= (format nil "<p>~a</p>" (link "https://a.no/x)y" "x")) (md "[x](<https://a.no/x)y>)"))
        "inside < and >, unbalanced")
    (is (string= (format nil "<p>~a</p>" (link "https://a.no" "a")) (md "[a](https://a.no \"Tittel\")"))
        "a title is not shown")
    (is (string= (format nil "<p>~a</p>" (link "https://a.no" "https://a.no")) (md "<https://a.no>")))
    (is (string= (format nil "<p>Se ~a. Og (~a), ~a!</p>"
                         (link "https://c.no/a_b" "https://c.no/a_b")
                         (link "https://d.no/x_(y)" "https://d.no/x_(y)")
                         (link "http://e.no" "http://e.no"))
                 (md "Se https://c.no/a_b. Og (https://d.no/x_(y)), http://e.no!"))
        "a bare URL, without its final punctuation or an unmatched )")
    (is (string= "<p>xhttps://a.no</p>" (md "xhttps://a.no")) "not after a letter")
    (is (string= (format nil "<p>~a</p>" (link "https://a.no" "https://a.no"))
                 (md "[https://a.no](https://a.no)"))
        "no link inside a link's text")
    (is (string= (format nil "<p>[a ~a</p>" (link "/c" "b"))
                 (md "[a [b](/c)"))
        "the nearest [ starts the link")
    (is (string= (format nil "<p><em>~a</em></p>" (link "/y" "x")) (md "*[x](/y)*")))
    (is (string= (format nil "<p>~a</p>" (link "https://y.com" "<strong>https://x.com</strong>"))
                 (md "[**https://x.com**](https://y.com)"))
        "no link inside a link's text, however deep")
    (is (string= (format nil "<p>~a</p>" (link "/b" "<em><strong>https://a.no</strong></em>"))
                 (md "[*__<https://a.no>__*](/b)")))))

(test addresses-that-make-no-link-show-as-written
  (dolist (text (list "[x](javascript:alert(1))" "[x](JavaScript:alert(1))"
                      "[x](data:text/html,<b>)" "[x](vbscript:msgbox)" "[x](//evil.no)"
                      "[x](/\\evil.no)" "[x](saker/12)" "[x](ftp://a.no)" "<javascript:alert(1)>"
                      "</saker/12>" "[x](https://)" "[x](mailto:)"
                      (format nil "[x](/~a/evil.no)" #\Tab)
                      (format nil "[x](https://a.no/~a)" (make-string 2048 :initial-element #\a))))
    (let ((html (md text)))
      (is (not (search "<a " html)) "~s makes no link" text)
      (is (search (tun.html:escape-html text) html)
          "~s shows as written" text))))

(test html-in-the-text-shows-as-written
  (dolist (text '("<script>alert(1)</script>" "<b>fet</b>" "<!-- skjult -->" "&amp; &lt;"
                  "<img src=x onerror=alert(1)>" "<a href=\"javascript:alert(1)\">x</a>"))
    (is (string= (format nil "<p>~a</p>" (tun.html:escape-html text)) (md text))
        "~s shows as written" text))
  (let ((html (md (md-lines "| <script> | b |" "|---|---|" "| <img src=x> | `<b>` |"))))
    (is (not (search "<script" html)))
    (is (not (search "<img" html)))))

;;; ------------------------------------------------------------------
;;; Plain text and line ends

(defparameter +plain-characters+
  (concatenate 'string "abcdefghijklmnopqrstuvwxyzæøåABCÆØÅ0123456789"
               "      ,;:!?'\"&/=%$@^~{}()" (string #\Newline) (string #\Newline))
  "Characters of text with no marks: no * _ ` [ ] < # | - + \\, no URL, and
no digit before . or ).")

(defun expected-paragraphs (text)
  "TEXT as paragraphs: one per run of lines with no blank line between,
each line break a <br>, as ferdig's paragraphs showed text."
  (let ((blocks '()) (current '()))
    (dolist (line (uiop:split-string text :separator (string #\Newline)))
      (if (string= "" (string-trim " " line))
          (when current (push (reverse current) blocks) (setf current '()))
          (push line current)))
    (when current (push (reverse current) blocks))
    (format nil "~{<p>~{~a~^<br>~}</p>~}"
            (mapcar (lambda (lines) (mapcar #'tun.html:escape-html lines)) (reverse blocks)))))

(test plain-text-reads-as-before
  (let ((*random-state* (sb-ext:seed-random-state 6211)))
    (dotimes (n 500)
      (let ((text (coerce (loop repeat (random 200)
                                collect (char +plain-characters+ (random (length +plain-characters+))))
                          'string)))
        (unless (string= (expected-paragraphs text) (md text))
          (fiveam:fail "~s renders as ~s, not ~s" text (md text) (expected-paragraphs text))
          (return))))
    (pass)))

(test line-ends-of-every-kind
  (dolist (newline (list (format nil "~c~c" #\Return #\Newline) (string #\Return)))
    (flet ((with-ends (&rest lines) (format nil (format nil "~~{~~a~~^~a~~}" newline) lines)))
      (is (string= (md (md-lines "a" "b" "" "c")) (md (with-ends "a" "b" "" "c"))))
      (is (string= "<hr>" (md (with-ends "---"))))
      (is (search ">x</code>" (md (with-ends "```" "x" "```"))))
      (is (search "<div class=\"tun-markdown-table\">" (md (with-ends "| a |" "|---|" "| 1 |"))))
      (is (not (find #\Return (md (with-ends "# H" "- a" "  - b" "| a |" "|--|" "| 1 |" "x" "y"))))
          "no CR in the output"))))

;;; ------------------------------------------------------------------
;;; Extension output

(test the-output-is-allowed-extension-output
  (let* ((text (md-lines "# H" "**a** *b* `c` [d](https://a.no) [e](mailto:kari@a.no) [f](/x)"
                      "<https://b.no> https://c.no" "- x" "1. y" "---" "```" "z" "```"
                      "| 1 | 2 | 3 | 4 |" "|-|-|-|-|" "| a | b | c | d |"))
         (node (tun.ui:markdown* (list :text text)))
         (trusted (tun.html:render-html node))
         (untrusted (tun.html:render-html (tun.html:untrusted node))))
    (is (string= trusted untrusted) "the same in extension output")
    (is (search "href=\"mailto:kari@a.no\"" untrusted) "mailto: kept")))

;;; ------------------------------------------------------------------
;;; Bounds

(defun md-repeated (count &rest parts)
  (with-output-to-string (out)
    (dotimes (i count) (dolist (part parts) (princ part out)))))

(defun costly-texts (&optional (scale 1))
  "Texts of about 64 KiB times SCALE built to cost a parser that looks too far."
  (flet ((n (count) (max 1 (round (* count scale)))))
    (list (cons "brackets" (md-repeated (n 32000) "[" "a"))
          (cons "closing brackets" (md-repeated (n 32000) "a" "]"))
          (cons "link tails" (md-repeated (n 16000) "[a](" ))
          (cons "link tails with no space" (format nil "~a~a" (md-repeated (n 8000) "[](") (md-repeated (n 30000) "x")))
          (cons "stars" (md-repeated (n 21000) "*a "))
          (cons "stars closing" (md-repeated (n 21000) " a*"))
          (cons "underscores" (md-repeated (n 21000) "_a "))
          (cons "alternating marks" (md-repeated (n 16000) "*_" ))
          (cons "nested marks" (format nil "~a~a~a" (md-repeated (n 8000) "*a _") "x" (md-repeated (n 8000) "_ a*")))
          (cons "backtick runs" (with-output-to-string (out)
                                  (loop for run from 1 while (< (file-position out) (n 60000))
                                        do (format out "~a a " (make-string (1+ (mod run 300)) :initial-element #\`)))))
          (cons "angle brackets" (md-repeated (n 32000) "<" "a"))
          (cons "bare URLs" (md-repeated (n 8000) " http://a"))
          (cons "a long URL" (format nil "https://~a" (md-repeated (n 60000) "a")))
          (cons "URLs in one word" (md-repeated (n 8000) "(http://"))
          (cons "URLs in one word, after dots" (md-repeated (n 8000) ".http://"))
          (cons "brackets, then links" (format nil "~a~a" (md-repeated (n 32000) "[")
                                               (md-repeated (n 4500) "[a](/x)")))
          (cons "brackets and marks, then links" (format nil "~a~a" (md-repeated (n 10000) "[*a ")
                                                         (md-repeated (n 3000) "*[b](/c)")))
          (cons "a URL closed many times" (format nil "https://a~a" (md-repeated (n 60000) ")")))
          (cons "table rows" (format nil "~a~%~a~%~a"
                                     (format nil "|~{ ~a |~}" (loop repeat 20 collect (make-string 80 :initial-element #\h)))
                                     (md-repeated 20 "-|")
                                     (md-repeated (n 30000) "|" #\Newline)))
          (cons "table cells" (format nil "~a~%~a~%~a"
                                      (format nil "|~{ ~a |~}" (loop repeat 20 collect (make-string 80 :initial-element #\h)))
                                      (md-repeated 20 "-|")
                                      (md-repeated (n 1500) (md-repeated 20 "a|") #\Newline)))
          (cons "nested lists" (with-output-to-string (out)
                                 (loop for line from 0 below (n 6000)
                                       do (format out "~a- a~%" (make-string (* 2 (mod line 40)) :initial-element #\Space)))))
          (cons "fences" (md-repeated (n 8000) "```" #\Newline))
          (cons "headings" (md-repeated (n 16000) "# a" #\Newline))
          (cons "escapes" (md-repeated (n 32000) "\\*")))))

(test costly-texts-render-within-a-second
  (loop for (name . text) in (costly-texts)
        do (let* ((start (get-internal-real-time))
                  (html (md text))
                  (seconds (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
             (is (< seconds 1) "~a (~d characters) took ~,2f s" name (length text) seconds)
             (is (< (length html) (* 200 (length text)))
                 "~a: ~d characters of output for ~d" name (length html) (length text)))))

(defun render-seconds (text)
  "How long TEXT takes to render, the shorter of two tries."
  (loop repeat 2
        minimize (let ((start (get-internal-real-time)))
                   (md text)
                   (/ (- (get-internal-real-time) start) internal-time-units-per-second))))

(test costly-texts-take-time-in-proportion-to-their-length
  ;; Four times the text in at most about four times the time: a cost that
  ;; grows with the square of the length would take sixteen.
  (loop for (name . small) in (costly-texts 1/8)
        for (nil . large) in (costly-texts 1/2)
        do (let ((once (render-seconds small))
                 (four (render-seconds large)))
             (is (< four (+ (* 8 once) 0.02))
                 "~a: ~,3f s for ~d characters, ~,3f s for ~d" name
                 four (length large) once (length small)))))

(defparameter +mark-characters+
  (concatenate 'string "*_`[]()<>|#-+:.!\\/\"' aht1ps" (string #\Newline) (string #\Newline))
  "Characters random texts are made of: the marks, and enough of the rest to
make URLs, numbers and words.")

(test random-texts-never-signal
  (let ((*random-state* (sb-ext:seed-random-state 6212))
        (worst 0))
    (dotimes (n 3000)
      (let* ((text (coerce (loop repeat (1+ (random 300))
                                 collect (char +mark-characters+ (random (length +mark-characters+))))
                           'string))
             (html (handler-case (md text)
                     (error (e) (fiveam:fail "~s signals ~a" text e) (return)))))
        (setf worst (max worst (/ (length html) (length text))))))
    (is (< worst 400) "the output is at most ~d times the text" (ceiling worst))))
