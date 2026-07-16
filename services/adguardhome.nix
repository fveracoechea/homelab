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
          password = "$2b$12$jeSGNoPYjq6WpVsQ6SMU3eYpOR7XtwqlUOZS/nns4/T.nfDXxl5Jm";
        }
      ];

      dns = {
        bind_hosts = ["0.0.0.0"];
        port = 53;
        upstream_dns = [
          "127.0.0.1:5335"
        ];
        bootstrap_dns = ["1.1.1.1" "9.9.9.9"];

        cache_enabled = true;
        cache_size = 52428800;
        cache_optimistic = true;
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
          # AdGuard DNS filter - main ad/tracker/mobile/social/cryptominer compilation (EasyList + EasyPrivacy + AdGuard Base, simplified for DNS-level blocking)
          "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
          # Smart TV telemetry and in-app ads (Samsung, LG, Roku, etc.) - near-zero overlap with the main filter
          "https://adguardteam.github.io/HostlistsRegistry/assets/filter_7.txt"
          # The Big List of Hacked Malware Web Sites - sites compromised with malware/ransomware/trojans
          "https://adguardteam.github.io/HostlistsRegistry/assets/filter_9.txt"
          # Malicious URL Blocklist (URLHaus) - malicious URLs from abuse.ch's database
          "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt"
          # HaGeZi's Threat Intelligence Feeds - malware, cryptojacking, spam, scam, phishing (broader than #9/#11)
          "https://adguardteam.github.io/HostlistsRegistry/assets/filter_44.txt"
          # breaks streaming apps (Peacock, Netflix) - blocks Conviva, Adobe Analytics, Comscore endpoints that apps block on
          # "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
        ];
    };
  };

  services.caddy.virtualHosts."ad-blocker.veracoechea.com".extraConfig = ''
    tls /var/lib/acme/veracoechea.com/fullchain.pem /var/lib/acme/veracoechea.com/key.pem
    reverse_proxy 127.0.0.1:8082
  '';

  networking.firewall.interfaces.enp8s0 = {
    allowedUDPPorts = [53];
    allowedTCPPorts = [53];
  };
  networking.firewall.interfaces.tailscale0 = {
    allowedUDPPorts = [53];
    allowedTCPPorts = [53];
  };
}
