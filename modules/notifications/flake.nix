{
  description = "tun employee notifications module";
  outputs = { self }: {
    tunModule = {
      name = "notifications";
      system = "tun-notifications";
      dependsOn = [ "customers" "orders" "staffing" ];
      core = [ ">= 2.0.0" "< 3.0" ];
      src = ./.;
      rev = self.rev or self.dirtyRev or "unknown";
    };
  };
}
