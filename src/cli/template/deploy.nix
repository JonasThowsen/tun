# Where {{name}} runs: nixploy targets (github:JonasThowsen/nixploy), each
# deployed with `nixploy deploy --target NAME`. Tun fills in the image, the
# host network, PORT, PUBLIC_URL (from web.domain) and the health check
# ($TUN_SOURCE/spec/deploy.md); a target names its host, its domain, two
# free ports and its secrets.
{
  # production = {
  #   ip = "203.0.113.10";
  #   user = "nixploy";
  #   identityFile = "~/.ssh/id_nixploy";
  #   web = {
  #     domain = "{{name}}.example.com";
  #     slots = { blue = 4100; green = 4101; };
  #   };
  #   # A SOPS-encrypted dotenv file holding
  #   # DATABASE_URL=postgresql://USER:PASSWORD@127.0.0.1/DATABASE
  #   # and what (:sign-in ...) and (:mail ...) read, such as
  #   # WORKOS_DOMAIN, WORKOS_CLIENT_ID, WORKOS_CLIENT_SECRET and RESEND_API_KEY
  #   # ($TUN_SOURCE/docs/client-api.md)
  #   secrets.app = ./secrets/production.env;
  # };
}
