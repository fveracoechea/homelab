{...}: {
  services.adguardhome = {
    enable = true;
    host = "127.0.0.1";
    port = 8082;
    mutableSettings = false;

    settings = {
      users = [
        {
          name = "admin";
          password = "$2b$12$qTJxOKiP1YJyCOiC0vn51eHY8MJwQXiVAQBbbQSHCRMPD8RtlahBS";
        }
      ];

      dns = {
        bind_hosts = ["0.0.0.0"];
        port = 53;
        upstream_dns = [
          "127.0.0.1:5335"
        ];
        bootstrap_dns = ["1.1.1.1" "9.9.9.9"];
      };

      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
        parental_enabled = true;
        safe_search.enabled = false;
      };

      filters =
        map (url: {
          enabled = true;
          url = url;
        }) [
          "https://adguardteam.github.io/AdGuardDNSFilter/Filters/filter.txt"
          "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
          "https://adguardteam.github.io/HostlistsRegistry/assets/filter_9.txt"
          "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt"
        ];
    };
  };

  services.caddy.virtualHosts."ad-blocker.veracoechea.com".extraConfig = ''
    tls /var/lib/acme/veracoechea.com/fullchain.pem /var/lib/acme/veracoechea.com/key.pem
    reverse_proxy 127.0.0.1:8082
  '';

  networking.firewall.interfaces.enp8s0.allowedUDPPorts = [53];
  networking.firewall.interfaces.tailscale0.allowedUDPPorts = [53];
}
