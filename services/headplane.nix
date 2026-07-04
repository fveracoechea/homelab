{
  config,
  lib,
  pkgs,
  ...
}: let
  domain = "gateway.veracoechea.com";
  headscaleDomain = "vpn.veracoechea.com";

  format = pkgs.formats.yaml {};
  headscaleConfig = format.generate "headscale.yml" (
    lib.recursiveUpdate config.services.headscale.settings {
      tls_cert_path = "/dev/null";
      tls_key_path = "/dev/null";
      policy.path = "/dev/null";
    }
  );
in {
  services.headplane = {
    enable = true;
    settings = {
      server = {
        host = "127.0.0.1";
        port = 3000;
        base_url = "https://${domain}";
        cookie_secret_path = "/var/lib/headplane/cookie-secret";
      };
      headscale = {
        url = "https://${headscaleDomain}";
        config_path = "${headscaleConfig}";
      };
      integration.proc.enabled = true;
    };
  };

  services.caddy.virtualHosts."${domain}".extraConfig = ''
    reverse_proxy 127.0.0.1:3000
  '';
}
