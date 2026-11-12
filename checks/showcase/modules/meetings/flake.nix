{
  description = "the showcase's module meetings: a generated list and form that choose a customer";

  # A module kept in the showcase's tree (tun-platform.md 2.1), so the
  # showcase has a generated resource whose records refer to another's
  # (spec/ui.md 8, «Choosing a record»).
  outputs = { self }: {
    tunModule = {
      name = "meetings";
      system = "tun-meetings";
      dependsOn = [ "customers" ];
      core = [ ">= 2.35.0" "< 3.0" ];
      src = ./.;
      rev = self.rev or self.dirtyRev or "unknown";
    };
  };
}
