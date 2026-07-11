{...}: {
  services.adguardhome = {
    enable = true;
    host = "127.0.0.1";
    port = 8082;

    settings = {
      dns = {
        bind_hosts = ["10.0.0.2"];
        port = 53;
        upstream_dns = [
          "1.1.1.1"
          "1.0.0.1"
          "9.9.9.9"
          "149.112.112.112"
        ];
        bootstrap_dns = ["1.1.1.1" "9.9.9.9"];
      };

      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
        parental_enabled = false;
        safe_search.enabled = false;
      };

      filters = map (url: {enabled = true; url = url;}) [
        "https://adguardteam.github.io/HostlistsRegistry/assets/filter_9.txt"
        "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt"
      ];
    };
  };

  services.caddy.virtualHosts."adguard.veracoechea.com".extraConfig = ''
    tls /var/lib/acme/veracoechea.com/fullchain.pem /var/lib/acme/veracoechea.com/key.pem
    reverse_proxy 127.0.0.1:8082
  '';

  networking.firewall.interfaces.enp8s0.allowedUDPPorts = [53];
  networking.firewall.interfaces.tailscale0.allowedUDPPorts = [53];
}
