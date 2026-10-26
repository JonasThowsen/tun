{
  description = "tun module customers: customer records";

  # A module is pinned by git revision like core (tun-platform.md 2.1): a
  # client's flake has one input per module, and its flake.lock pins each.
  # This flake only describes the module; the client builds it, against the
  # client's pinned core, with lib.buildClient from the core flake.
  outputs = { self }: {
    tunModule = {
      name = "customers";
      system = "tun-customers";
      dependsOn = [ ];
      # The core versions this module builds against (its README states it).
      core = [ ">= 1.2.0" "< 2.0" ];
      src = ./.;
      rev = self.rev or self.dirtyRev or "unknown";
    };
  };
}
