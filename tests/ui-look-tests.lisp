;;;; tests/ui-look-tests.lisp -- the look of the design system: its tokens,
;;;; edges, radii, text, focus, pressed and chosen states, buttons and badges,
;;;; read from the stylesheet (spec/ui.md 2.1, 3, 10).

(in-package #:tun.tests)

(def-suite ui-look :in core)
(in-suite ui-look)

;;; ------------------------------------------------------------------
;;; The stylesheet as declarations

(defun css-declarations (css)
  "Every declaration in CSS as a list (MEDIA SELECTORS PROPERTY VALUE): MEDIA
the at-rules around it (@media, @supports, @container, @layer,
@starting-style), SELECTORS the nested selectors from the outermost, the
value with its runs of white space made one space.  The insides of
@keyframes are left out."
  (let ((found '()))
    (labels ((squeeze (text)
               (string-trim " " (cl-ppcre:regex-replace-all "\\s+" text " ")))
             (walk (body media selectors)
               (loop for (prelude . inner) in (tun.ui::css-rules body)
                     do (cond ((null inner)
                               (let ((colon (position #\: prelude)))
                                 (when (and colon (plusp (length selectors)))
                                   (push (list media selectors
                                               (squeeze (subseq prelude 0 colon))
                                               (squeeze (subseq prelude (1+ colon))))
                                         found))))
                              ((eql 0 (search "@keyframes" prelude)))
                              ((char= (char prelude 0) #\@)
                               (walk inner (append media (list (squeeze prelude))) selectors))
                              (t (walk inner media
                                       (append selectors (list (squeeze prelude)))))))))
      (walk (tun.ui::strip-css-comments css) '() '()))
    (nreverse found)))

(defvar *look-declarations* (cons nil nil)
  "The stylesheet last read and its declarations.")

(defun look-declarations ()
  "The declarations of the whole stylesheet, read again when it changed."
  (let ((css (tun.ui:stylesheet)))
    (unless (eq css (car *look-declarations*))
      (setf *look-declarations* (cons css (css-declarations css))))
    (cdr *look-declarations*)))

(defun component-declarations (name)
  "The declarations of component NAME's CSS."
  (css-declarations (tun.ui:component-css (tun.ui:find-component name))))

(defun declaration-media (declaration) (first declaration))
(defun declaration-selectors (declaration) (second declaration))
(defun declaration-property (declaration) (third declaration))
(defun declaration-value (declaration) (fourth declaration))

(defun declaration-where (declaration)
  "Where DECLARATION is, for a test's message."
  (format nil "~{~a~^ >> ~}: ~a: ~a" (declaration-selectors declaration)
          (declaration-property declaration) (declaration-value declaration)))

(defun selectors-text (declaration)
  (format nil "~{~a~^ ~}" (declaration-selectors declaration)))

(defun token (name)
  "The value of the token NAME on :root, outside any @media."
  (let ((declaration (find-if (lambda (d)
                                (and (equal (declaration-selectors d) '(":root"))
                                     (notany (lambda (m) (search "@media" m))
                                             (declaration-media d))
                                     (string= (declaration-property d) name)))
                              (look-declarations))))
    (and declaration (declaration-value declaration))))

;;; ------------------------------------------------------------------
;;; Colours and contrast (WCAG 2.2)

(defun hex-colour (hex)
  "HEX, #rrggbb or #rrggbbaa, as (R G B ALPHA), R, G and B from 0 to 255."
  (let ((digits (string-left-trim "#" hex)))
    (list (parse-integer digits :start 0 :end 2 :radix 16)
          (parse-integer digits :start 2 :end 4 :radix 16)
          (parse-integer digits :start 4 :end 6 :radix 16)
          (if (= (length digits) 8)
              (/ (parse-integer digits :start 6 :end 8 :radix 16) 255)
              1))))

(defun scheme-colours (value)
  "The two colours of VALUE, light-dark(#LIGHT, #DARK), as hex strings."
  (or (cl-ppcre:register-groups-bind (light dark)
          ("^light-dark\\((#[0-9a-f]+), (#[0-9a-f]+)\\)$" value)
        (list light dark))
      (error "~s is not light-dark() of two hex colours" value)))

(defun token-colour (name scheme)
  "Token NAME's hex colour in SCHEME, :light or :dark."
  (let ((colours (scheme-colours (token name))))
    (if (eq scheme :light) (first colours) (second colours))))

(defun over (colour alpha ground)
  "COLOUR (R G B) at ALPHA laid over GROUND, as the browser blends them."
  (mapcar (lambda (c g) (+ (* alpha c) (* (- 1 alpha) g))) colour ground))

(defun opaque (hex ground-hex)
  "HEX, with its own alpha, over the opaque GROUND-HEX, as (R G B)."
  (destructuring-bind (r g b alpha) (hex-colour hex)
    (over (list r g b) alpha (subseq (hex-colour ground-hex) 0 3))))

(defun luminance (rgb)
  (flet ((channel (value)
           (let ((v (/ value 255d0)))
             (if (<= v 0.04045d0) (/ v 12.92d0) (expt (/ (+ v 0.055d0) 1.055d0) 2.4d0)))))
    (destructuring-bind (r g b) (mapcar #'channel rgb)
      (+ (* 0.2126d0 r) (* 0.7152d0 g) (* 0.0722d0 b)))))

(defun contrast (a b)
  "The contrast ratio of colours A and B, (R G B) each."
  (let ((la (luminance a)) (lb (luminance b)))
    (/ (+ (max la lb) 0.05d0) (+ (min la lb) 0.05d0))))

(defun text-contrast (text-hex alpha ground-hex)
  "The contrast of TEXT-HEX at ALPHA over GROUND-HEX against that ground."
  (let ((ground (subseq (hex-colour ground-hex) 0 3)))
    (contrast (over (subseq (hex-colour text-hex) 0 3) alpha ground) ground)))

(defparameter +grounds+ '("--background" "--card" "--popover" "--chrome" "--input-background"
                          "--muted")
  "The grounds text stands on (spec/ui.md 2.1).")

;;; ------------------------------------------------------------------
;;; The tokens (spec/ui.md 3)

(test the-tokens-hold-the-look
  (loop for (name value)
          on '("--background" "light-dark(#ffffff, #19191c)"
               "--card" "light-dark(#ffffff, #19191c)"
               "--popover" "light-dark(#ffffff, #19191c)"
               "--chrome" "light-dark(#f6f6f7, #111113)"
               "--chrome-border" "light-dark(#0000000f, #ffffff12)"
               "--input-background" "light-dark(#ffffff, #141417)"
               "--foreground" "light-dark(#171717, #ededed)"
               "--primary" "light-dark(#171717, #ededed)"
               "--primary-foreground" "light-dark(#ffffff, #19191c)"
               "--muted" "light-dark(#f3f3f4, #222226)"
               "--muted-foreground" "color-mix(in oklab, var(--foreground) 72%, transparent)"
               "--accent" "light-dark(#0000000d, #ffffff0f)"
               "--pressed" "light-dark(color-mix(in oklab, var(--foreground) 8%, transparent), color-mix(in oklab, var(--foreground) 10%, transparent))"
               "--soft" "color-mix(in oklab, var(--foreground) 5%, transparent)"
               "--border" "light-dark(#0000001f, #ffffff24)"
               "--border-strong" "light-dark(color-mix(in oklab, var(--foreground) 26%, transparent), color-mix(in oklab, var(--foreground) 30%, transparent))"
               "--input" "light-dark(color-mix(in oklab, var(--foreground) 50%, transparent), color-mix(in oklab, var(--foreground) 40%, transparent))"
               "--highlight" "light-dark(#005ff2, #47a8ff)"
               "--ring" "var(--highlight)"
               "--radius" "0.75rem"
               "--radius-sm" "calc(var(--radius-md) - 0.125rem)"
               "--radius-md" "0.5rem"
               "--radius-lg" "var(--radius)"
               "--radius-xl" "var(--radius)"
               "--radius-full" "9999px"
               "--text-xs" "0.75rem" "--text-xs--line-height" "calc(1 / 0.75)"
               "--text-sm" "0.875rem" "--text-sm--line-height" "calc(1.25 / 0.875)"
               "--text-running" "0.875rem"
               "--text-running--line-height" "calc(1.375 / 0.875)"
               "--shadow-panel" "0 1px 2px light-dark(rgb(0 0 0 / 0.04), transparent), 0 2px 8px light-dark(rgb(0 0 0 / 0.03), transparent)"
               "--focus-ring" "0 0 0 2px var(--background), 0 0 0 4px var(--ring)"
               "--focus-ring-inset" "inset 0 0 0 2px var(--ring)"
               "--ease" "cubic-bezier(0.16, 1, 0.3, 1)"
               "--duration-fast" "150ms" "--duration" "200ms"
               "--duration-sheet" "280ms" "--duration-close" "160ms")
        by #'cddr
        do (is (equal value (token name)) "~a is ~s, not ~s" name (token name) value)))

(test every-duration-is-0-under-reduced-motion
  (let ((reduced (remove-if-not (lambda (d)
                                  (and (equal (declaration-selectors d) '(":root"))
                                       (some (lambda (m) (search "prefers-reduced-motion: reduce" m))
                                             (declaration-media d))))
                                (look-declarations))))
    (dolist (name '("--duration-fast" "--duration" "--duration-sheet" "--duration-close"))
      (is (find-if (lambda (d) (and (string= name (declaration-property d))
                                    (string= "0ms" (declaration-value d))))
                   reduced)
          "~a is not 0ms under reduced motion" name))))

(test running-text-is-the-pages
  (let ((body (remove-if-not (lambda (d) (equal (declaration-selectors d) '("body")))
                             (look-declarations))))
    (is (find "var(--text-running)" body :key #'declaration-value :test #'string=))
    (is (find "var(--text-running--line-height)" body :key #'declaration-value
                                                    :test #'string=)))
  (dolist (name '("card" "dialog" "summary-list" "timeline" "tabs" "accordion" "confirm-panel"))
    (is (find "var(--text-running)" (component-declarations name)
              :key #'declaration-value :test #'string=)
        "~a's text is not running text" name)))

;;; ------------------------------------------------------------------
;;; Contrast, computed from the tokens

(test text-and-muted-text-read-on-every-ground
  (dolist (scheme '(:light :dark))
    (let ((text (token-colour "--foreground" scheme)))
      (dolist (ground +grounds+)
        (let ((ground-hex (token-colour ground scheme)))
          (is (>= (text-contrast text 1 ground-hex) 4.5) "text on ~a, ~a" ground scheme)
          (is (>= (text-contrast text 0.72 ground-hex) 6.5)
              "muted text on ~a, ~a: ~,2f" ground scheme (text-contrast text 0.72 ground-hex)))))))

(test the-accent-shows-on-every-ground
  (dolist (scheme '(:light :dark))
    (let ((accent (token-colour "--highlight" scheme)))
      (dolist (ground '("--background" "--card" "--input-background"))
        (is (>= (text-contrast accent 1 (token-colour ground scheme)) 4.5)
            "the accent on ~a, ~a" ground scheme))
      (is (>= (text-contrast accent 1 (token-colour "--chrome" scheme)) 3)
          "the accent on the chrome, ~a" scheme)
      (is (>= (text-contrast (token-colour "--highlight-foreground" scheme) 1 accent) 4.5)
          "text on the accent, ~a" scheme))))

(test a-fields-edge-is-3-to-1
  ;; --input is the text colour at 50 % in the light and 40 % in the dark
  ;; (pinned above); WCAG 1.4.11 asks 3:1 of a control's edge.
  (loop for (scheme alpha) in '((:light 0.5) (:dark 0.4))
        do (let ((text (token-colour "--foreground" scheme)))
             (dolist (ground '("--background" "--card" "--chrome" "--input-background"))
               (let ((ground-hex (token-colour ground scheme)))
                 (is (>= (text-contrast text alpha ground-hex) 3)
                     "a field's edge on ~a, ~a: ~,2f" ground scheme
                     (text-contrast text alpha ground-hex)))))))

(test every-badge-tone-reads
  (dolist (scheme '(:light :dark))
    (is (>= (text-contrast (token-colour "--foreground" scheme) 1 (token-colour "--muted" scheme))
            4.5)
        "the neutral badge, ~a" scheme)
    (dolist (tone '("info" "success" "warning" "destructive"))
      (let ((strong (token-colour (format nil "--~a" tone) scheme))
            (soft (token-colour (format nil "--~a-soft" tone) scheme))
            (on-strong (token-colour (format nil "--~a-foreground" tone) scheme)))
        (is (>= (text-contrast strong 1 soft) 4.5) "~a on its tint, ~a: ~,2f" tone scheme
            (text-contrast strong 1 soft))
        (is (>= (text-contrast strong 1 (token-colour "--background" scheme)) 4.5)
            "~a on the page, ~a" tone scheme)
        (is (>= (text-contrast on-strong 1 strong) 4.5) "text on ~a, ~a" tone scheme)))))

;;; ------------------------------------------------------------------
;;; Edges, radii and capitals (spec/ui.md 2.1)

(defparameter +edge-properties+
  "^border(-(top|right|bottom|left|inline|block)(-(start|end))?)?(-width)?$")

(defun mark-p (declaration)
  "True when DECLARATION draws one of the marks spec/ui.md 2.1 lets have a
wider edge: the tick of a checkbox, a graph node's tone, the confirm panel's !."
  (let ((selectors (selectors-text declaration)))
    (or (and (search "tun-checkbox-input" selectors) (search "::after" selectors))
        (and (search "tun-graph-node" selectors)
             (string= "border-inline-start" (declaration-property declaration)))
        (search "tun-confirm-panel-mark" selectors))))

(test every-edge-is-1px
  (dolist (declaration (look-declarations))
    (when (and (cl-ppcre:scan +edge-properties+ (declaration-property declaration))
               (not (mark-p declaration)))
      (cl-ppcre:do-matches-as-strings (length "[0-9.]+(px|rem|em)" (declaration-value declaration))
        (is (member length '("1px" "0px") :test #'string=)
            "an edge of ~a: ~a" length (declaration-where declaration))))))

(test every-radius-is-a-token
  (dolist (declaration (look-declarations))
    (when (cl-ppcre:scan "^border(-[a-z]+)*-radius$" (declaration-property declaration))
      (dolist (part (cl-ppcre:split " " (declaration-value declaration)))
        (is (member part '("var(--radius-sm)" "var(--radius-md)" "var(--radius-lg)"
                           "var(--radius-xl)" "var(--radius-full)" "0" "inherit")
                    :test #'string=)
            "a radius of ~a: ~a" part (declaration-where declaration))))))

(test no-component-writes-in-capitals
  (dolist (declaration (look-declarations))
    (let ((property (declaration-property declaration))
          (value (declaration-value declaration)))
      (is (not (and (string= property "text-transform") (search "uppercase" value)))
          "capitals: ~a" (declaration-where declaration))
      (is (not (and (string= property "letter-spacing")
                    (cl-ppcre:scan "^[0-9]*\\.?[0-9]+[a-z]+" value)
                    (not (cl-ppcre:scan "^0+(\\.0+)?[a-z]*$" value))))
          "letter-spaced: ~a" (declaration-where declaration)))))

;;; ------------------------------------------------------------------
;;; Focus, hover and motion

(test every-focus-ring-has-the-one-shape
  (dolist (declaration (look-declarations))
    (when (search ":focus-visible" (selectors-text declaration))
      (let ((property (declaration-property declaration))
            (value (declaration-value declaration)))
        (when (string= property "box-shadow")
          (is (or (search "var(--focus-ring)" value) (search "var(--focus-ring-inset)" value))
              "a ring of another shape: ~a" (declaration-where declaration)))
        (when (and (string= property "outline") (string/= value "none"))
          (is (string= value "2px solid var(--ring)")
              "an outline of another shape: ~a" (declaration-where declaration))))))
  (is (search "--focus-ring: 0 0 0 2px var(--chrome), 0 0 0 4px var(--ring);"
              (tun.ui:component-css (tun.ui:find-component "app-shell")))
      "the chrome leaves the ring's gap in its own ground")
  (is (search ":focus-visible { outline: 2px solid var(--ring); outline-offset: 2px; }"
              (tun.ui:stylesheet))
      "a link in running text has the same shape from the base rule"))

(test every-hover-is-where-a-pointer-hovers
  (dolist (declaration (look-declarations))
    (when (search ":hover" (selectors-text declaration))
      (is (some (lambda (media) (search "(hover: hover)" media)) (declaration-media declaration))
          "a hover outside (hover: hover): ~a" (declaration-where declaration)))))

(test every-transition-takes-a-duration-token
  (dolist (declaration (look-declarations))
    (let ((property (declaration-property declaration))
          (value (declaration-value declaration)))
      (cond ((string= property "transition-duration")
             (is (or (eql 0 (search "var(--duration" value)) (string= value "0s")
                     (string= value "0.01ms !important"))
                 "a duration not a token: ~a" (declaration-where declaration)))
            ((string= property "transition")
             (dolist (part (split-sequence-commas value))
               (is (or (string= part "none") (search "var(--duration" part))
                   "a transition without a duration token: ~a"
                   (declaration-where declaration))))))))

(defun split-sequence-commas (value)
  "VALUE split at its commas outside parentheses, each part trimmed."
  (tun.ui::split-selectors value))

;;; ------------------------------------------------------------------
;;; Pressed and chosen (spec/ui.md 2.1)

(test every-tappable-component-answers-while-pressed
  (dolist (name '("button" "card" "table" "nav-list" "tabs" "dropdown-menu" "combobox"
                  "accordion"))
    (let ((pressed (remove-if-not (lambda (d) (search ":active" (selectors-text d)))
                                  (component-declarations name))))
      (is (find-if (lambda (d) (member (declaration-property d)
                                       '("background-color" "background-image")
                                       :test #'string=))
                   pressed)
          "~a has no pressed ground" name)
      (is (find-if (lambda (d) (and (string= "transition-duration" (declaration-property d))
                                    (string= "0s" (declaration-value d))))
                   pressed)
          "~a eases into its pressed state" name))))

(test every-component-under-a-pointer-answers-a-press
  ;; A tooltip shows on hover and has no tap of its own.
  (dolist (component (tun.ui:all-components :internal t))
    (let ((declarations (css-declarations (tun.ui:component-css component))))
      (when (and (find-if (lambda (d) (search ":hover" (selectors-text d))) declarations)
                 (not (string= "tooltip" (component-label component))))
        (is (find-if (lambda (d) (search ":active" (selectors-text d))) declarations)
            "~a has a hover and no pressed state" (component-label component))))))

(defun without-not (selector)
  "SELECTOR without its :not(...) parts."
  (let ((start (search ":not(" selector)))
    (if (null start)
        selector
        (let ((depth 0) (end nil))
          (loop for i from (+ start 4) below (length selector)
                do (case (char selector i)
                     (#\( (incf depth))
                     (#\) (decf depth) (when (zerop depth) (setf end i) (return)))))
          (without-not (concatenate 'string (subseq selector 0 start)
                                    (subseq selector (1+ (or end (1- (length selector)))))))))))

(defparameter +chosen-state+
  "\\[aria-(selected|current|pressed|checked|expanded|sort)|:checked"
  "A selector that holds this picks out something chosen, current or on.")

(defparameter +box-properties+
  "^(font|font-weight|font-size|letter-spacing|padding.*|margin.*|width|height|(min|max)-(width|height)|border(-(top|right|bottom|left|inline|block)(-(start|end))?)?-width)$"
  "What a chosen state may not change, since it would move its neighbours.")

(defun chosen-p (declaration)
  (let ((selectors (mapcar #'without-not (declaration-selectors declaration))))
    (and (some (lambda (selector) (cl-ppcre:scan +chosen-state+ selector)) selectors)
         (notany (lambda (selector) (cl-ppcre:scan "::(before|after)" selector)) selectors))))

(test choosing-moves-nothing
  (dolist (component (tun.ui:all-components :internal t))
    (dolist (declaration (css-declarations (tun.ui:component-css component)))
      (when (chosen-p declaration)
        (let ((property (declaration-property declaration)))
          (is (not (cl-ppcre:scan +box-properties+ property))
              "~a: a chosen state sets ~a" (component-label component)
              (declaration-where declaration))
          (is (not (and (cl-ppcre:scan "^border(-(top|right|bottom|left|inline|block))?$" property)
                        (cl-ppcre:scan "[0-9]+px" (declaration-value declaration))))
              "~a: a chosen state sets an edge's width: ~a" (component-label component)
              (declaration-where declaration)))))))

(test the-scan-finds-a-chosen-state-that-moves
  (let ((declarations (css-declarations
                       ".tun-x { & .tun-x-tab { padding: 1px; &[aria-selected='true'] {
                           font-weight: 600; } &:not([aria-current]) { padding: 2px; }
                           &:checked::before { width: 4px; } } }")))
    (is (equal '("font-weight")
               (mapcar #'declaration-property (remove-if-not #'chosen-p declarations)))
        "a heavier chosen tab is found; :not() and a mark are not")))

;;; ------------------------------------------------------------------
;;; Buttons and badges (spec/ui.md 6)

(test the-destructive-button-has-no-fill
  (dolist (declaration (component-declarations "button"))
    (when (and (search "destructive" (selectors-text declaration))
               (member (declaration-property declaration) '("background-color" "background")
                       :test #'string=))
      (is (string= "var(--background)" (declaration-value declaration))
          "a destructive button filled: ~a" (declaration-where declaration))))
  (is (find-if (lambda (d) (and (search "destructive" (selectors-text d))
                                (string= "color" (declaration-property d))
                                (string= "var(--destructive)" (declaration-value d))))
               (component-declarations "button"))
      "its words are red")
  (is (not (search "background-color: var(--destructive)"
                   (tun.ui:component-css (tun.ui:find-component "confirm-panel"))))
      "the confirm panel's last step is not filled red"))

(test an-icon-only-outline-button-is-frameless-by-its-attributes
  (let* ((rest (remove-if-not (lambda (d)
                                (let ((selectors (selectors-text d)))
                                  (and (search "[data-size^='icon'][data-variant='outline']:not("
                                               selectors)
                                       (not (search ":has(" selectors)))))
                              (component-declarations "button")))
         (values (mapcar (lambda (d) (cons (declaration-property d) (declaration-value d))) rest)))
    (is (equal "transparent" (cdr (assoc "border-color" values :test #'string=))))
    (is (equal "transparent" (cdr (assoc "background-color" values :test #'string=))))
    (is (every (lambda (d) (search "[aria-pressed='true']" (selectors-text d))) rest)
        "a pressed one keeps its frame"))
  (is (find-if (lambda (d) (and (search "> .tun-button[data-size^='icon'][data-variant='outline']"
                                        (selectors-text d))
                                (string= "border-color" (declaration-property d))
                                (string= "var(--border)" (declaration-value d))))
               (component-declarations "button-group"))
      "in a group it keeps the group's frame")
  (let ((html (tun.html:render-html (tun.ui:button (:variant :outline :size :icon
                                                    :label "Rediger")
                                          (tun.ui:icon (:name :pencil))))))
    (is (and (search "data-variant=\"outline\"" html) (search "data-size=\"icon\"" html))
        "the button writes what decides it")))

(test a-small-button-takes-a-finger
  (let ((css (tun.ui:component-css (tun.ui:find-component "button"))))
    (is (search "&:is([data-size='xs'], [data-size='sm'], [data-size='icon-xs'], [data-size='icon-sm'])"
                css)
        "every size under a control's height has the invisible area")
    (is (search "inset: min(0px, calc(50% - var(--control-height) / 2))" css))))

(test a-badge-is-a-soft-pill
  (let ((declarations (component-declarations "badge")))
    (is (find "var(--radius-full)" declarations :key #'declaration-value :test #'string=))
    (is (notany (lambda (d) (cl-ppcre:scan "^border(-|$)" (declaration-property d)))
                (remove "border-radius" declarations :key #'declaration-property
                                                     :test #'string=))
        "a badge has no edge")
    (dolist (tone '("info" "success" "warning" "destructive"))
      (let ((rule (remove-if-not (lambda (d) (search (format nil "'~a'" tone) (selectors-text d)))
                                 declarations)))
        (is (equal (format nil "var(--~a-soft)" tone)
                   (declaration-value (find "background-color" rule
                                            :key #'declaration-property :test #'string=))))
        (is (equal (format nil "var(--~a)" tone)
                   (declaration-value (find "color" rule
                                            :key #'declaration-property :test #'string=)))))))
  (is (search "data-variant=\"neutral\"" (tun.html:render-html (tun.ui:badge () "Utkast")))
      "a badge is neutral unless told")
  (dolist (older '(:primary :secondary :outline))
    (is (search (format nil "data-variant=\"~(~a~)\"" older)
                (tun.html:render-html (tun.ui:badge* (list :variant older) "Ny")))
        "the variant ~a still renders" older)))

;;; ------------------------------------------------------------------
;;; Grounds, panels and the accent

(test the-shell-stands-on-the-chrome
  (let ((css (tun.ui:component-css (tun.ui:find-component "app-shell"))))
    (is (search "background-color: color-mix(in oklab, var(--chrome) 95%, transparent);" css)
        "the top bar")
    (is (search "background-color: var(--chrome);" css) "the sidebar and the phone's menu")
    (is (search "border-right: 1px solid var(--chrome-border);" css))
    (is (search "border-bottom: 1px solid var(--chrome-border);" css))))

(test panels-have-the-edge-and-the-panel-shadow
  (dolist (name '("card" "stat"))
    (let ((declarations (component-declarations name)))
      (is (find "1px solid var(--border)" declarations :key #'declaration-value :test #'string=)
          "~a has the edge" name)
      (is (find "var(--shadow-panel)" declarations :key #'declaration-value :test #'string=)
          "~a has the panel's shadow" name)))
  (dolist (name '("table" "markdown" "flash" "confirm-panel" "board" "graph"))
    (is (find-if (lambda (d) (search "var(--shadow-panel)" (declaration-value d)))
                 (component-declarations name))
        "~a has the panel's shadow" name)))

(test the-accent-is-only-for-focus-on-selection-and-a-drop
  (dolist (declaration (look-declarations))
    (when (and (cl-ppcre:scan "var\\(--(ring|highlight|focus-ring)" (declaration-value declaration))
               (not (eql 0 (search "--" (declaration-property declaration)))))
      (is (cl-ppcre:scan ":focus|::selection|:checked|data-tun-board-over|data-dragging"
                         (selectors-text declaration))
          "the accent used for something else: ~a" (declaration-where declaration)))))
