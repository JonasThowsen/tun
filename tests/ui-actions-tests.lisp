;;;; tests/ui-actions-tests.lisp -- the actions group of the design system:
;;;; what screen readers get from button groups, links, badges and avatars
;;;; (spec/ui.md 5-6).

(in-package #:tun.tests)

(def-suite ui-actions :in ui)
(in-suite ui-actions)

(defun actions-html (markup)
  (tun.html:render-html markup))

(defun actions-occurrences (part string)
  "How many times PART occurs in STRING."
  (loop for start = (search part string) then (search part string :start2 (1+ start))
        while start
        count t))

(test a-button-group-is-a-named-group
  (let ((group (actions-html (tun.ui:button-group (:label "Visning")
                               (tun.ui:button (:variant :outline) "Liste")
                               (tun.ui:button (:variant :outline) "Tavle")))))
    (is (search "role=\"group\"" group))
    (is (search "aria-label=\"Visning\"" group))
    (is (search "data-orientation=\"horizontal\"" group))
    (is (zerop (actions-occurrences "<hr" group)) "no separators unless asked for")))

(test a-separated-group-has-a-separator-between-each-part
  (let ((group (actions-html (tun.ui:button-group (:label "Send faktura" :separated t)
                               (tun.ui:button () "Send")
                               nil
                               (tun.ui:button (:size :icon :label "Flere valg")
                                              (tun.ui:icon (:name :chevron-down)))))))
    (is (= 1 (actions-occurrences "role=\"separator\"" group)) "one line between two parts")
    (is (search "aria-orientation=\"vertical\"" group)
        "the line between side-by-side buttons stands upright"))
  (let ((group (actions-html (tun.ui:button-group (:label "Antall" :orientation :vertical
                                                          :separated t)
                               (tun.ui:button () "Pluss")
                               (tun.ui:button () "Minus")
                               (tun.ui:button () "Null")))))
    (is (= 2 (actions-occurrences "role=\"separator\"" group)))
    (is (search "aria-orientation=\"horizontal\"" group)))
  (signals error (tun.ui:button-group (:orientation :diagonal) "x")))

(test a-link-needs-an-address-and-says-when-it-leaves-the-site
  (signals error (tun.ui:link () "Kunden"))
  (let ((internal (actions-html (tun.ui:link (:href "/kunder/218") "Rørlegger Hansen AS"))))
    (is (search "href=\"/kunder/218\"" internal))
    (is (not (search "another site" internal))))
  (let ((external (actions-html (tun.ui:link (:href "https://www.brreg.no" :external t)
                                             "Brønnøysundregistrene"))))
    (is (search "(another site)" external) "screen readers hear where the link goes")
    (is (search "aria-hidden=\"true\"" external) "the icon itself is not read")))

(test keys-pressed-together-are-nested-kbd-elements
  (let ((keys (actions-html (tun.ui:kbd () (tun.ui:kbd () "Ctrl") "+" (tun.ui:kbd () "K")))))
    (is (eql 0 (search "<kbd class=\"tun-kbd\"><kbd class=\"tun-kbd\">Ctrl</kbd>+" keys)))))

(test a-button-shows-its-shortcut-as-caps-after-its-content
  (let ((button (actions-html (tun.ui:button (:variant :outline :size :icon :label "Søk"
                                                       :icon :search :shortcut "Ctrl+K")))))
    (is (search "aria-label=\"Søk\"" button) "the label stays the button's name")
    (is (search "aria-keyshortcuts=\"Control+K Meta+K\"" button)
        "Ctrl is either key, as the dialog takes it")
    (is (search (concatenate 'string "aria-hidden=\"true\"><kbd class=\"tun-kbd\""
                             " data-tun-key=\"ctrl\">Ctrl</kbd><kbd class=\"tun-kbd\">K</kbd>"
                             "</kbd></button>")
                button)
        "one silent kbd at the end, holding a kbd per key"))
  (let ((button (actions-html (tun.ui:button (:icon-end :arrow-right :shortcut "/") "Neste"))))
    (is (search "aria-keyshortcuts=\"/\"" button) "a key without Ctrl is itself")
    (is (< (search "data-icon=\"end\"" button) (search "data-tun-shortcut" button))
        "the keys come after the end icon"))
  (is (not (search "aria-keyshortcuts" (actions-html (tun.ui:button () "Lagre")))))
  (dolist (shortcut '("" "Ctrl+" "+K" "Shift+K" "Ctrl+Shift+K"))
    (signals error (tun.ui:button (:shortcut shortcut) "Søk")
      "~s is not a key, or Ctrl and a key" shortcut)))

(test a-badge-carries-its-variant-and-a-silent-icon
  (let ((badge (actions-html (tun.ui:badge (:variant :success :icon :check) "Bekreftet"))))
    (is (search "data-variant=\"success\"" badge))
    (is (search "aria-hidden=\"true\"" badge))
    (is (search "Bekreftet" badge))))

(test an-avatar-is-read-as-the-persons-name
  (let ((avatar (actions-html (tun.ui:avatar (:name "Kari Nordmann")))))
    (is (search "role=\"img\"" avatar))
    (is (search "aria-label=\"Kari Nordmann\"" avatar))
    (is (search ">KN</span>" avatar) "the initials of the first and last name"))
  (is (search ">AB</span>" (actions-html (tun.ui:avatar (:name "  Anne-Lise   Berg ")))))
  (is (search ">ØÅ</span>" (actions-html (tun.ui:avatar (:name "øystein ås")))))
  (is (search ">O</span>" (actions-html (tun.ui:avatar (:name "Ola"))))))

(test an-avatar-photo-falls-back-to-the-initials
  (let ((avatar (actions-html (tun.ui:avatar (:name "Per Olsen" :src "/bilder/per.jpg")))))
    (is (search "alt=\"\"" avatar) "the root carries the name, so the photo is not read twice")
    (is (search ">PO</span>" avatar) "the initials are under the photo"))
  (let ((avatar (actions-html (tun.ui:avatar (:src "/bilder/per.jpg" :alt "Per Olsen")))))
    (is (search "aria-label=\"Per Olsen\"" avatar)))
  (signals error (tun.ui:avatar (:src "/bilder/per.jpg")) "a photo alone has no name"))

(test an-avatar-beside-the-name-is-hidden-from-screen-readers
  (let ((avatar (actions-html (tun.ui:avatar (:name "Kari Nordmann" :alt "")))))
    (is (search "aria-hidden=\"true\"" avatar))
    (is (not (search "role=\"img\"" avatar)))))

(test an-avatar-group-shows-at-most-max-and-names-the-rest
  (let ((group (actions-html (tun.ui:avatar (:group '("Kari Nordmann" "Ola Hansen" "Per Olsen"
                                                      "Lise Berg")
                                                    :max 2 :label "Montører")))))
    (is (search "role=\"group\"" group))
    (is (search "aria-label=\"Montører\"" group))
    (is (search "aria-label=\"Kari Nordmann\"" group))
    (is (not (search "aria-label=\"Per Olsen\"" group)))
    (is (search "aria-label=\"2 more: Per Olsen, Lise Berg\"" group))
    (is (search ">+2</span>" group)))
  (is (not (search "data-count" (actions-html (tun.ui:avatar (:group '("Kari Nordmann")))))))
  (signals error (tun.ui:avatar (:group '("Kari Nordmann") :name "Ola Hansen"))))

(test the-smallest-buttons-take-a-finger-on-a-touch-screen
  (let ((css (tun.ui:component-css (tun.ui:find-component "button"))))
    (is (search "@media (pointer: coarse)" css))
    (is (search "inset: min(0px, calc(50% - var(--control-height) / 2))" css))))
