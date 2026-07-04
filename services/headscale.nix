{...}: let
  domain = "vpn.veracoechea.com";
in {
  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8081;

    settings = {
      server_url = "https://${domain}";
      listen_addr = "127.0.0.1:8081";
      metrics_listen_addr = "127.0.0.1:9090";

      database = {
        type = "sqlite";
        sqlite = {
          path = "/var/lib/headscale/db.sqlite";
          write_ahead_log = true;
        };
      };

      dns = {
        magic_dns = true;
        base_domain = "tailnet.veracoechea.com";
        nameservers.global = ["1.1.1.1"];
      };

      derp = {
        server = {
          enabled = true;
          region_id = 999;
          region_code = "hostinger";
          region_name = "Hostinger VPS";
          stun_listen_addr = "0.0.0.0:3478";
        };
        urls = [];
        auto_update_enabled = false;
      };

      log = {
        level = "info";
        format = "text";
      };
    };
  };

  services.caddy.virtualHosts."${domain}".extraConfig = ''
    tls /var/lib/acme/vpn.veracoechea.com/fullchain.pem /var/lib/acme/vpn.veracoechea.com/key.pem
    reverse_proxy 127.0.0.1:${toString 8081} {
      header_up X-Forwarded-For {remote_host}
    }
  '';

  networking.firewall.allowedUDPPorts = [3478];
}


