{
  description = "tun inbox module";
  outputs = { self }: {
    tunModule = {
      name = "inbox";
      system = "tun-inbox";
      dependsOn = [ "customers" "orders" "notifications" ];
      core = [ ">= 2.0.0" "< 3.0" ];
      src = ./.;
      rev = self.rev or self.dirtyRev or "unknown";
    };
  };
}
