{
  description = "{{name}}: a Tun client";

  # Tun's kernel and the modules this client builds on, one input each, all
  # pinned in flake.lock. `tun add MODULE` adds a module with its
  # dependencies and pins it at the kernel's revision. `tun update` moves
  # them all to one newer revision; `nix flake update tun` moves the kernel
  # alone.
  inputs.tun.url = "{{tun-input}}";
{{module-inputs}}
  # nixploy deploys the image to the targets in deploy.nix.
  inputs.nixploy = {
    url = "github:JonasThowsen/nixploy";
    inputs.nixpkgs.follows = "tun/nixpkgs";
  };

  outputs = { self, tun, nixploy, ... }@inputs:
    let
      system = "x86_64-linux";
      lib = tun.inputs.nixpkgs.lib;
      tunLib = tun.lib.${system};
      # Every input that is a Tun module.
      modules = map (input: input.tunModule)
        (builtins.filter (input: input ? tunModule) (builtins.attrValues (removeAttrs inputs [ "self" ])));
      server = tunLib.buildClient {
        pname = "{{name}}";
        revision = self.rev or self.dirtyRev or "unknown";
        inherit modules;
        # The client's own sources: its .asd and Lisp files, not its tests,
        # and the icons of the installed app (:web-app), when it has them.
        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.union
            (lib.fileset.difference
              (lib.fileset.fileFilter (f: f.hasExt "lisp" || f.hasExt "asd") ./.)
              ./tests)
            (lib.fileset.maybeMissing ./icons);
        };
      };
    in {
      packages.${system} = {
        default = server;
        docker = tunLib.clientImage { name = "{{name}}"; inherit server; };
      };
      apps.${system}.default = {
        type = "app";
        program = "${server}/bin/{{name}}-server";
      };
      # `nixploy deploy --target NAME` (spec/deploy.md in $TUN_SOURCE).
      nixploy = nixploy.lib.makeConfig {
        project = "{{name}}";
        targets = builtins.mapAttrs (_: tunLib.deployTarget) (import ./deploy.nix);
      };
      # SBCL with the pinned kernel and modules, Postgres, tun and nixploy.
      devShells.${system}.default = tunLib.clientShell {
        inherit modules;
        packages = [ nixploy.packages.${system}.default ];
      };
    };
}
