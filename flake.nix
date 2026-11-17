{
  description = "tun (SBCL + ASDF): the kernel, dev shell, module and client builder";

  # Pinned to the nixpkgs revision of the build host so the toolchain is
  # reproducible: SBCL 2.6.4 and every Lisp library come from this commit.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/4382ed2b7a6839d4280a9b386db49cbc5907414d";
  # lisp, the agent's image and debugger as a command (spec/tooling.md).
  inputs.slynk-cli.url = "github:JonasThowsen/slynk-cli";
  inputs.slynk-cli.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, slynk-cli }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      inherit (pkgs) lib;
      sbcl = pkgs.sbcl;

      # Third-party libraries core needs at run time (all from nixpkgs).
      coreLibs = ps: with ps; [
        alexandria
        bordeaux-threads
        cl-base64   # password hashes in the PHC format (spec/auth.md)
        cl-ppcre
        closer-mop
        com_dot_inuoe_dot_jzon
        flexi-streams
        hunchentoot
        chunga   # Hunchentoot's chunked streams, unwrapped to end a connection
        ironclad
        sqlite
        cl-postgres   # the Postgres store adapter (spec/store.md)
        drakma   # an identity provider's token endpoint (spec/auth.md 3.5)
        swank   # --repl-port (core.md §8.2): the native REPL, debug-only
      ];
      # Plus what the test-suites and the dev shell use.
      devLibs = ps: coreLibs ps ++ (with ps; [ fiveam usocket
        slynk   # bin/repl: the SLY editor connection, dev shell only
      ]);

      # Development-only lint libraries and CLI.
      trivialGlob = sbcl.buildASDFSystem {
        pname = "trivial-glob";
        version = "0.1.0";
        src = pkgs.fetchFromGitHub {
          owner = "fukamachi";
          repo = "trivial-glob";
          rev = "5dc3289defb0debaa239679a7286b3c9b57212b5";
          hash = "sha256-Eb1MYkrLPxKJ5SaLSIaFcxoGrvjnsB83PCczYN9hB5Q=";
        };
      };
      malletLibrary = sbcl.buildASDFSystem {
        pname = "mallet";
        version = "0.9.2";
        src = pkgs.fetchFromGitHub {
          owner = "fukamachi";
          repo = "mallet";
          rev = "bd0c6d054c6508c445d3b27d966f39f502a27ab9";
          hash = "sha256-9LVmkzsEGQOgKwRh5Nofu/D0uNEH21bGtPsTm/D0ifw=";
        };
        # Use Nix's ASDF and libraries instead of the release's bundled copies.
        postPatch = ''
          rm -rf .bundle-libs
        '';
        lispLibs = [ trivialGlob ] ++ (with sbcl.pkgs; [
          alexandria cl-interpol cl-ppcre eclector
        ]);
      };
      malletLisp = sbcl.withPackages (_: [ malletLibrary ]);
      malletLauncher = pkgs.writeText "mallet-main.lisp" ''
        (load (sb-ext:posix-getenv "ASDF"))
        (let ((*standard-output* *error-output*)
              (*trace-output* *error-output*))
          (asdf:load-system "mallet"))
        (uiop:symbol-call :mallet :main)
      '';
      mallet = pkgs.writeShellScriptBin "mallet" ''
        # The Nix Lisp wrapper supplies its own dependency environment.
        unset ASDF CL_SOURCE_REGISTRY ASDF_OUTPUT_TRANSLATIONS
        exec ${malletLisp}/bin/sbcl --noinform --non-interactive \
          --no-userinit --no-sysinit --load ${malletLauncher} \
          --end-toplevel-options "$@"
      '';

      # The kernel's version; modules declare the range they build against
      # (each module's flake.nix, "core").  Must equal TUN.CORE:+CORE-VERSION+
      # (a core test checks it).
      coreVersion = "2.49.0";

      # Core (the kernel) as an installable ASDF package: only kernel
      # sources, no modules, compiled in the sandbox by nixpkgs' builder;
      # fasls ship in the output.
      tun = sbcl.buildASDFSystem {
        pname = "tun";
        version = coreVersion;
        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./tun.asd ./src
          ];
        };
        systems = [ "tun" ];
        lispLibs = coreLibs sbcl.pkgs;
        nativeLibs = [ pkgs.sqlite ];
      };

      # What makes a PDF (spec/pdf.md 3.2): Typst, and the fonts it is given,
      # static TrueType files only (Typst 0.14 cannot draw a variable font):
      # Liberation Sans for Latin, Greek and Cyrillic, DejaVu Sans for the
      # letters Liberation lacks.  The server finds both through the
      # environment, TUN_TYPST and TUN_PDF_FONTS (pdfEnvironment).
      typst = pkgs.typst;
      pdfFonts = pkgs.runCommand "tun-pdf-fonts" { } ''
        mkdir -p $out
        cp ${pkgs.liberation_ttf}/share/fonts/truetype/LiberationSans-{Regular,Bold,Italic,BoldItalic}.ttf $out/
        cp ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans{,-Bold}.ttf $out/
      '';
      pdfEnvironment = ''
        export TUN_TYPST="${typst}/bin/typst"
        export TUN_PDF_FONTS="${pdfFonts}"
      '';

      # The test helpers of the core suite, as a package a client's dev shell
      # can use (spec/cli.md 6).
      testSupport = sbcl.buildASDFSystem {
        pname = "tun-test-support";
        version = coreVersion;
        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [ ./tun-test-support.asd ./tests/support.lisp ./tests/case-guard.lisp ./tests/timing.lisp
                                         ./tests/i18n-support.lisp
                                         ./tests/scenarios.lisp ./tests/fuzz-inputs.lisp
                                         ./tests/fuzzing.lisp ./tests/policy-checks.lisp
                                         ./tests/sequences.lisp ./tests/pages.lisp
                                         ./tests/generated.lisp ];
        };
        systems = [ "tun-test-support" ];
        lispLibs = [ tun ] ++ (with sbcl.pkgs; [ drakma usocket fiveam ]);
      };

      # Reading material for agents and people (reference/README.md): pinned
      # sources of exemplary libraries, SBCL's own source and manual, the
      # HyperSpec, PAIP and Google's Lisp guides.  Built with bin/reference
      # into reference/lib, which is not committed.  Everything comes from
      # this nixpkgs or a pinned revision, so it matches the code Tun runs.
      reference =
        let
          libraries = [
            "alexandria" "cl-ppcre" "hunchentoot" "closer-mop" "fiveam"
            "com_dot_inuoe_dot_jzon" "ironclad" "serapeum" "parachute"
          ];
          sbclSource = pkgs.runCommand "sbcl-${sbcl.version}-source" { } ''
            mkdir $out
            tar -xjf ${sbcl.src} -C $out --strip-components=1
          '';
          paip = pkgs.fetchFromGitHub {
            owner = "norvig"; repo = "paip-lisp";
            rev = "9cea73837e439d331fe78d7b585e994c7113aac2";
            hash = "sha256-Qdp0PSH84Zq7ivH6/U3pN5FdAvErcfoy7AnmkJwBg08=";
          };
          googleGuides = pkgs.fetchFromGitHub {
            owner = "google"; repo = "styleguide";
            rev = "0a7d5c8768211371646a3c1beeff8cd224b974be";
            hash = "sha256-VoRJhyx8/3HeWU3xxwp4eFiYtGIJCwoq+o/gO/kKwmo=";
          };
        in
        pkgs.linkFarm "tun-reference" (
          map (name: { inherit name; path = sbcl.pkgs.${name}.src; }) libraries
          ++ [
            { name = "sbcl"; path = sbclSource; }
            { name = "sbcl-manual"; path = "${sbcl}/share/info"; }
            { name = "hyperspec"; path = "${sbcl.pkgs.clhs.src}/HyperSpec-7-0/HyperSpec"; }
            { name = "paip"; path = paip; }
            { name = "google-lisp-guides"; path = googleGuides; }
          ]);

      # A version constraint such as ">= 1.0" holds for coreVersion?
      satisfies = constraint:
        let
          m = builtins.match " *(>=|<=|>|<|=) *([0-9.]+) *" constraint;
          op = builtins.elemAt m 0;
          c = builtins.compareVersions coreVersion (builtins.elemAt m 1);
        in
        if m == null then throw "malformed core constraint ${constraint}"
        else if op == ">=" then c >= 0
        else if op == ">" then c > 0
        else if op == "<=" then c <= 0
        else if op == "<" then c < 0
        else c == 0;

      # The modules a client pins (their flakes' tunModule), checked and built
      # in dependency order, each against this core and its dependencies.
      buildModules = modules:
        let
          byName = builtins.listToAttrs (map (m: { name = m.name; value = m; }) modules);
          # Two modules of one name, such as a client's own module named as
          # one of Tun's (tun-platform.md 2.1), would hide one another.
          duplicates = builtins.filter (m: builtins.length (builtins.filter (o: o.name == m.name) modules) > 1) modules;
          checked = if duplicates != [ ]
            then throw "two modules are named ${(builtins.head duplicates).name}: ${lib.concatMapStringsSep " and " (m: "${m.src}") duplicates}"
            else map (m:
            let failed = builtins.filter (c: !(satisfies c)) m.core; in
            if failed != [ ]
            then throw "module ${m.name} (rev ${m.rev}) builds against core ${lib.concatStringsSep " and " m.core}, but the pinned core is ${coreVersion} (constraint ${lib.concatStringsSep ", " failed} fails)"
            else
              let missing = builtins.filter (d: !(byName ? ${d})) m.dependsOn; in
              if missing != [ ]
              then throw "module ${m.name} depends on ${lib.concatStringsSep ", " missing}, which the client does not pin"
              else m) modules;
          sorted = lib.toposort (a: b: builtins.elem a.name b.dependsOn) checked;
          ordered = if sorted ? cycle
                    then throw "module dependency cycle: ${lib.concatMapStringsSep " -> " (m: m.name) sorted.cycle}"
                    else sorted.result;
          built = builtins.listToAttrs (map (m: {
            name = m.name;
            value = sbcl.buildASDFSystem {
              pname = m.system;
              version = coreVersion;
              src = m.src;
              systems = [ m.system ];
              lispLibs = [ tun ] ++ map (d: built.${d}) m.dependsOn;
            };
          }) ordered);
        in
        { inherit ordered built; };

      # Build a client's server from its own source and this core package.
      # The client's package must define *APPLICATION-CLASS*.  The launcher
      # loads core and client from the Nix store only, never a working tree.
      # A client may carry several manifests (a default one and a minimal
      # one, say): ASDFSYSTEM is the ASDF system of the manifest built here and
      # CLASSVARIABLE the symbol (in PACKAGE) naming its application class.
      buildClient = { pname, version ? "0.1.0", src, package ? lib.toUpper pname, lispLibs ? [ ], revision ? "unknown",
                      modules ? [ ], asdfSystem ? pname, classVariable ? "*APPLICATION-CLASS*",
                      extraSystems ? [ ], screens ? { } }:
        let
          mods = buildModules modules;
          moduleSystems = map (m: m.system) mods.ordered;
          # SCREENS: the client's single-page screens, each built by
          # buildScreen, by the folder of the source its files go in, the
          # path its define-single-page's :files names ("screens/queue/dist").
          # Without any, the source is SRC as it is.
          folders = lib.mapAttrsToList (path: built:
            let folder = lib.removeSuffix "/" path; in
            if folder == "" || lib.hasPrefix "/" folder || lib.elem ".." (lib.splitString "/" folder)
            then throw "buildClient ${pname}: a screen's folder is a path in the source, not ${path}"
            else { inherit folder built; }) screens;
          source = if screens == { } then src else pkgs.runCommand "${pname}-source" { } (''
            cp -r ${src} $out
            chmod -R u+w $out
          '' + lib.concatMapStrings ({ folder, built }: ''
            rm -rf "$out/${folder}"
            mkdir -p "$(dirname "$out/${folder}")"
            cp -r ${built} "$out/${folder}"
            chmod -R u+w "$out/${folder}"
          '') folders);
          clientLib = sbcl.buildASDFSystem {
            inherit pname version;
            src = source;
            # EXTRASYSTEMS: other systems of the client's own (a base its
            # manifests share); the builder keeps only the .asd files of SYSTEMS.
            systems = [ asdfSystem ] ++ extraSystems;
            lispLibs = [ tun ] ++ map (m: mods.built.${m.name}) mods.ordered ++ lispLibs;
          };
          env = sbcl.withPackages (_: [ clientLib ]);
          launcher = pkgs.writeText "${pname}-serve.lisp" ''
            (setf *read-eval* nil)
            (load (sb-ext:posix-getenv "ASDF"))
            (let ((*compile-verbose* nil) (*load-verbose* nil))
              (handler-bind ((warning #'muffle-warning))
                (asdf:load-system "${asdfSystem}")))
            ;; Refuse to run unless core, every module and the client came from the store.
            (dolist (system '("tun" ${lib.concatMapStringsSep " " (s: "\"${s}\"") moduleSystems} "${asdfSystem}"))
              (let ((dir (namestring (asdf:system-source-directory system))))
                (unless (eql 0 (search "/nix/store/" dir))
                  (format *error-output* "~a: refusing to start, ~a was loaded from ~a~%" "${pname}" system dir)
                  (sb-ext:exit :code 3))
                (format t "~&~a: ~a from ~a~%" "${pname}" system dir)))
            (funcall (find-symbol "MAIN" "TUN.RUNTIME")
                     (symbol-value (find-symbol "${classVariable}" "${package}"))
                     :name "${pname}")
          '';
        in
        pkgs.writeShellScriptBin "${pname}-server" ''
          # Nothing from the caller's environment may add source trees.
          unset CL_SOURCE_REGISTRY ASDF_OUTPUT_TRANSLATIONS
          # introspect_runtime's build revisions (core.md §8.2). The client's
          # is the one its target gives at start (deploy.md 3), else REVISION.
          export TUN_CORE_REVISION="${self.rev or self.dirtyRev or "unknown"}"
          export TUN_CLIENT_REVISION="''${TUN_CLIENT_REVISION:-${revision}}"
          ${lib.concatMapStringsSep "\n" (m: "export TUN_MODULE_REVISION_${lib.toUpper m.name}=\"${m.rev}\"") mods.ordered}
          ${pdfEnvironment}
          exec ${env}/bin/sbcl --noinform --non-interactive --no-userinit --no-sysinit \
            --load ${launcher} --end-toplevel-options "$@"
        '';
      # A single-page screen's built files (spec/typescript.md 6): the folder
      # SRC, a screen with its package.json and package-lock.json, type-checked
      # by its `check` script and built by its `build` script into dist/,
      # which is the output.  Its npm dependencies are the lock file's,
      # fetched by one fixed-output derivation whose hash is NPMDEPSHASH, so
      # the build itself has no network; a lock file changed without a new
      # hash fails the build, naming the hash it needs.  The screen's
      # node_modules are a derivation of their own (passthru.nodeModules),
      # so a change to the screen's code fetches and installs nothing again.
      buildScreen = { name, src, npmDepsHash }:
        let
          locked = lib.fileset.toSource {
            root = src;
            fileset = lib.fileset.unions [ (src + "/package.json") (src + "/package-lock.json") ];
          };
          npmDeps = pkgs.fetchNpmDeps { name = "${name}-npm-deps"; src = locked; hash = npmDepsHash; };
          nodeModules = pkgs.stdenvNoCC.mkDerivation {
            name = "${name}-node-modules";
            src = locked;
            inherit npmDeps;
            nativeBuildInputs = [ pkgs.nodejs pkgs.npmHooks.npmConfigHook ];
            dontBuild = true;
            installPhase = ''
              mkdir $out
              mv node_modules $out/
            '';
          };
        in
        pkgs.stdenvNoCC.mkDerivation {
          name = "${name}-screen";
          inherit src;
          nativeBuildInputs = [ pkgs.nodejs ];
          buildPhase = ''
            runHook preBuild
            ln -s ${nodeModules}/node_modules node_modules
            # npm runs the screen's scripts and nothing else: no registry, no
            # check for a newer npm.
            export HOME="$TMPDIR" npm_config_offline=true npm_config_update_notifier=false
            npm run --silent check
            npm run --silent build
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            test -f dist/index.html || { echo "${name}: its build wrote no dist/index.html" >&2; exit 1; }
            cp -r dist $out
            runHook postInstall
          '';
          passthru = { inherit nodeModules npmDeps; };
        };

      # The showcase's single-page screen (checks/showcase/screen, its
      # sign-off.lisp): bin/check links its build into the showcase's tree.
      showcaseScreen = buildScreen {
        name = "showcase-sign-off";
        src = ./checks/showcase/screen;
        npmDepsHash = "sha256-PBgy2PvDijasio2uypSZHFUUkieg2b96Udkkvip+igw=";
      };
      # The showcase's server as a client builds its own, its screen's files
      # put in its source where its define-single-page looks: what a
      # client's nix build does with a screen (spec/typescript.md 6).
      showcase = buildClient {
        pname = "showcase";
        src = lib.fileset.toSource {
          root = ./checks/showcase;
          fileset = lib.fileset.union
            (lib.fileset.difference
              (lib.fileset.fileFilter (f: f.hasExt "lisp" || f.hasExt "asd") ./checks/showcase)
              (lib.fileset.unions [ ./checks/showcase/tests ./checks/showcase/modules ./checks/showcase/checks ]))
            ./checks/showcase/icons;
        };
        modules = builtins.filter (m: m.name == "customers") repoModules
          ++ [ ((import ./checks/showcase/modules/meetings/flake.nix).outputs { inherit self; }).tunModule ];
        screens = { "screen/dist" = showcaseScreen; };
      };

      # A client's OCI image (spec/deploy.md 2): its server is the
      # entrypoint, so arguments are the server's flags, and PORT and
      # DATABASE_URL come from the environment.  No shell, no other programs.
      clientImage = { name, server, tag ? "latest" }:
        pkgs.dockerTools.buildLayeredImage {
          inherit name tag;
          contents = [ pkgs.cacert ];
          extraCommands = "mkdir -m 1777 tmp";
          config = {
            Entrypoint = [ (lib.getExe server) ];
            Env = [ "HOME=/tmp" "LANG=C.UTF-8" "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
          };
        };

      # A nixploy target for a client's image (spec/deploy.md 3): what every
      # Tun server needs, under what TARGET sets. nixploy builds from a copy
      # of the tracked files with no git history, where the flake has no
      # self.rev, so the commit comes from nixploy: it replaces {revision}
      # with the commit it deploys when it starts the server.
      deployTarget = target: lib.recursiveUpdate (lib.recursiveUpdate {
        image = "docker";
        run = {
          network = "host";
          environment = { PORT = "{port}"; TUN_CLIENT_REVISION = "{revision}"; };
        };
        web.healthPath = "/health";
      } (lib.optionalAttrs (target ? web.domain) {
        run.environment.PUBLIC_URL = "https://${target.web.domain}";
        # Caddy on the host reaches the slot from the loopback (core.md 7.5).
        run.environment.TRUSTED_PROXY = "127.0.0.1";
      })) target;

      # Every target of a client's deploy.nix (spec/deploy.md 3). The commit
      # reaches the server when it starts rather than being built into the
      # image, so a commit that changes none of the client's files builds
      # the same image. A revision passed here, as Tun 2.13.0's template
      # did, is ignored: nixploy's is the one that is right where it builds.
      deployTargets = { targets, ... }: builtins.mapAttrs (_: deployTarget) targets;

      # This revision's own modules, as a client's flake pins them
      # (modules/*/flake.nix, tunModule).
      repoModules = map
        (name: ((import ./modules/${name}/flake.nix).outputs { inherit self; }).tunModule)
        (builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./modules)));

      # The tun command (spec/cli.md): tun-cli with every module of this
      # revision, which it describes, loaded from the store.
      cli =
        let
          cliLib = sbcl.buildASDFSystem {
            pname = "tun-cli";
            version = coreVersion;
            src = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [ ./tun-cli.asd ./src/cli ];
            };
            systems = [ "tun-cli" ];
            lispLibs = [ tun ];
          };
          mods = buildModules repoModules;
          env = sbcl.withPackages (_: [ cliLib ] ++ map (m: mods.built.${m.name}) mods.ordered);
          launcher = pkgs.writeText "tun-cli.lisp" ''
            (setf *read-eval* nil)
            (load (sb-ext:posix-getenv "ASDF"))
            (let ((*standard-output* *error-output*) (*compile-verbose* nil) (*load-verbose* nil))
              (handler-bind ((warning #'muffle-warning))
                (dolist (system '("tun-cli" ${lib.concatMapStringsSep " " (m: "\"${m.system}\"") mods.ordered}))
                  (asdf:load-system system))))
            (funcall (find-symbol "MAIN" "TUN.CLI"))
          '';
        in
        pkgs.writeShellScriptBin "tun" ''
          # The caller's ASDF settings, for the programs tun loop verify runs
          # (spec/loop.md 6); tun itself loads only what is in its store path.
          export TUN_CALLER_CL_SOURCE_REGISTRY="''${CL_SOURCE_REGISTRY-}"
          export TUN_CALLER_ASDF_OUTPUT_TRANSLATIONS="''${ASDF_OUTPUT_TRANSLATIONS-}"
          unset CL_SOURCE_REGISTRY ASDF_OUTPUT_TRANSLATIONS
          export TUN_CORE_REVISION="${self.rev or self.dirtyRev or "unknown"}"
          exec ${env}/bin/sbcl --noinform --non-interactive --no-userinit --no-sysinit \
            --load ${launcher} --end-toplevel-options "$@"
        '';

      # bin/with-postgres for a client's bin/test (spec/cli.md 6).
      withPostgres =
        pkgs.writeShellScriptBin "tun-with-postgres" (builtins.readFile ./bin/with-postgres);

      # A client repository's dev shell (spec/cli.md 6): SBCL with the
      # kernel, the client's pinned MODULES, the test support, FiveAM and
      # Slynk; Postgres; sops; and the tun command of this revision.  The
      # client's own systems join ASDF's source registry from the working
      # tree.
      clientShell = { modules ? [ ], packages ? [ ] }:
        let mods = buildModules modules; in
        pkgs.mkShell {
          packages = [
            (sbcl.withPackages (ps: [ tun testSupport ps.fiveam ps.slynk ]
                                    ++ map (m: mods.built.${m.name}) mods.ordered))
            pkgs.postgresql cli withPostgres checkPython
            # A deployed client's secrets are SOPS files (spec/deploy.md 3).
            pkgs.sops
          ] ++ packages;
          shellHook = ''
            export TUN_SOURCE="${self}"
            ${pdfEnvironment}
            # The client's systems and its own modules', from the working tree
            # (spec/cli.md 6, tun-platform.md 2.1).
            export CL_SOURCE_REGISTRY="$PWD/:$PWD/modules//''${CL_SOURCE_REGISTRY:+:$CL_SOURCE_REGISTRY}"
          '';
        };
      # Python with Playwright and the Chromium it drives: bin/ui-shots
      # screenshots the design system's specimen with it (spec/ui.md 7), and
      # tun check runs browser checks (spec/preview.md 4).
      browserPython = name: pkgs.writeShellScriptBin name ''
        export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
        export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
        # Fonts for the screenshots, rather than whatever the host has
        # (scripts/ui-shots.py names them).
        export FONTCONFIG_FILE="${pkgs.writeText "ui-shots-fonts.conf" ''
          <?xml version="1.0"?>
          <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
          <fontconfig>
            <dir>${pkgs.open-sans}/share/fonts</dir>
            <dir>${pkgs.source-code-pro}/share/fonts</dir>
            <dir>${pkgs.noto-fonts-color-emoji}/share/fonts</dir>
            <cachedir prefix="xdg">fontconfig</cachedir>
          </fontconfig>
        ''}"
        exec ${pkgs.python3.withPackages (ps: [ ps.playwright ])}/bin/python3 -I "$@"
      '';
      uiShots = browserPython "ui-shots";
      checkPython = browserPython "tun-check-python";
    in {
      packages.${system} = {
        inherit tun reference mallet cli;
        ui-shots = uiShots;
        tun-test-support = testSupport;
        showcase-screen = showcaseScreen;
        inherit showcase;
        default = tun;
      };

      # nix build .#checks.x86_64-linux.client-without-screen: a client with
      # no single-page screen pays nothing for them (spec/typescript.md 6).
      # The test client's server, built as any client's is, has neither Node
      # nor npm in its closure, and a client's dev shell has no node, npm or
      # tsc among its programs.
      checks.${system}.client-without-screen =
        let
          server = buildClient {
            pname = "test-client";
            src = lib.fileset.toSource {
              root = ./tests/client;
              fileset = lib.fileset.difference
                (lib.fileset.fileFilter (f: f.hasExt "lisp" || f.hasExt "asd") ./tests/client)
                (lib.fileset.unions [ ./tests/client/tests ./tests/client/modules ]);
            };
            modules = repoModules
              ++ [ ((import ./tests/client/modules/logbook/flake.nix).outputs { inherit self; }).tunModule ];
          };
          shell = clientShell { };
        in
        pkgs.runCommand "client-without-screen" {
          closure = pkgs.closureInfo { rootPaths = [ server ]; };
          programs = shell.nativeBuildInputs ++ shell.buildInputs;
        } ''
          found=$(grep -E -- '-(nodejs|npm)-' "$closure/store-paths" || true)
          if [ -n "$found" ]; then
            echo "a client without a screen has Node in its server's closure:"; echo "$found"; exit 1
          fi
          for p in $programs; do
            for name in node npm npx tsc; do
              if [ -e "$p/bin/$name" ]; then
                echo "a client without a screen has $name in its dev shell, from $p"; exit 1
              fi
            done
          done
          echo "$(wc -l < "$closure/store-paths") paths in the server's closure, none of Node or npm" > $out
        '';

      apps.${system}.default = {
        type = "app";
        program = "${cli}/bin/tun";
      };

      lib.${system} = {
        inherit buildClient buildModules clientImage clientShell deployTarget deployTargets sbcl coreVersion;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          (sbcl.withPackages devLibs) pkgs.sqlite pkgs.postgresql pkgs.python3 pkgs.curl pkgs.cloc
          pkgs.emacs-nox mallet checkPython slynk-cli.packages.${system}.default
          # flock(1), which the verify lock's tests hold it with (spec/preview.md 4).
          pkgs.util-linux
          # pdfinfo and pdftotext, which the PDF tests read a made PDF with.
          pkgs.poppler-utils
          # tsc, which type-checks and compiles the TypeScript module of a
          # single-page screen, and node, which the module's tests run it
          # in (spec/typescript.md 7).  Tun's own shell only: a client's
          # shell and build have no Node.
          pkgs.typescript pkgs.nodejs
        ];
        # The checkout's own systems (the kernel, modules/, the test client
        # and clients/) join
        # the libraries in ASDF's source registry, so any SBCL started in the
        # shell can load them: SLY's `M-x sly' in an editor that takes this
        # shell from .envrc, for one.
        shellHook = ''
          export TUN_LISP_ROOT="$PWD"
          # svelte-check, Svelte and TypeScript, the showcase screen's own
          # packages, for the suite's type check of a Svelte component
          # (spec/typescript.md 6.5).
          export TUN_SCREEN_NODE_MODULES="${showcaseScreen.nodeModules}/node_modules"
          ${pdfEnvironment}
          export CL_SOURCE_REGISTRY="$PWD/:$PWD/modules//:$PWD/tests/client/:$PWD/clients//''${CL_SOURCE_REGISTRY:+:$CL_SOURCE_REGISTRY}"
        '';
      };
    };
}
