{
  description = "tun module dashboard: the developer's pages: «Jobber» for background jobs and schedules, «Feil» for errors, «Logg» for requests";

  # A module is pinned by git revision like core (tun-platform.md 2.1): a
  # client's flake has one input per module, and its flake.lock pins each.
  # This flake only describes the module; the client builds it, against the
  # client's pinned core, with lib.buildClient from the core flake.
  outputs = { self }: {
    tunModule = {
      name = "dashboard";
      system = "tun-dashboard";
      dependsOn = [ ];
      # The core versions this module builds against (its README states it).
      core = [ ">= 2.0.0" "< 3.0" ];
      src = ./.;
      rev = self.rev or self.dirtyRev or "unknown";
    };
  };
}
