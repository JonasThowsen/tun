{
  description = "tun employee notifications module";
  outputs = { self }: {
    tunModule = {
      name = "notifications";
      system = "tun-notifications";
      dependsOn = [ "customers" "orders" "staffing" ];
      core = [ ">= 1.2.0" "< 2.0" ];
      src = ./.;
      rev = self.rev or self.dirtyRev or "unknown";
    };
  };
}
