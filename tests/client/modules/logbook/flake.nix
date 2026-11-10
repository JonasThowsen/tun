{
  description = "the test client's module logbook: notes the staff keep";

  # A module kept in a client's repository (tun-platform.md 2.1): the test
  # client's own, so Tun's suite holds what such a module is checked by
  # (testing.md 1, tests 2 and 10).
  outputs = { self }: {
    tunModule = {
      name = "logbook";
      system = "tun-logbook";
      dependsOn = [ ];
      core = [ ">= 2.19.0" "< 3.0" ];
      src = ./.;
      rev = self.rev or self.dirtyRev or "unknown";
    };
  };
}
