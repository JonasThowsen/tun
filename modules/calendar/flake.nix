{
  description = "tun module calendar: calendar events and the merged calendar";

  # A module is pinned by git revision like core (tun-platform.md 2.1): a
  # client's flake has one input per module, and its flake.lock pins each.
  # This flake only describes the module; the client builds it, against the
  # client's pinned core, with lib.buildClient from the core flake.
  outputs = { self }: {
    tunModule = {
      name = "calendar";
      system = "tun-calendar";
      dependsOn = [ "orders" "staffing" ];
      # The core versions this module builds against (its README states it).
      core = [ ">= 2.0.0" "< 3.0" ];
      src = ./.;
      rev = self.rev or self.dirtyRev or "unknown";
    };
  };
}
