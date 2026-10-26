;;;; tun-cli.asd -- the tun command (spec/cli.md).
;;;;
;;;; A system of its own, beside tun.asd, so Nix builds it as a package of
;;;; its own. The program loads it together with every module of the same
;;;; revision (bin/tun from this checkout, flake.nix's cli from the store),
;;;; and those are the modules it describes.

(defsystem "tun-cli"
  :description "The tun command: list Tun's modules, create a client, add a module to one, preview one, run the feature loop."
  :depends-on ("tun" "cl-ppcre" "uiop" "drakma" (:require "sb-posix") (:require "sb-bsd-sockets"))
  :pathname "src/cli"
  :serial t
  :components ((:file "package")
               (:file "catalog")
               (:file "client")
               (:file "preview")
               (:file "check")
               (:file "loop")
               (:file "main")))
