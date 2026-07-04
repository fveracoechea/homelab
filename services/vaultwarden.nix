{...}: {
  services.vaultwarden = {
    enable = true;
    dbBackend = "postgresql";
    environmentFile = "/var/lib/vaultwarden/vaultwarden.env";
    config = {
      DOMAIN = "https://10.0.0.2";
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      ROCKET_LOG = "critical";
      SIGNUPS_ALLOWED = false;
    };
  };

  services.caddy.virtualHosts."passwords.veracoechea.com".extraConfig = ''
    tls internal
    reverse_proxy 127.0.0.1:8222
  '';
}
