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
        fallback_dns = ["1.1.1.1" "9.9.9.9"];
        bootstrap_dns = ["1.1.1.1" "9.9.9.9"];

        cache_enabled = true;
        cache_size = 52428800;
        cache_optimistic = true;

        upstream_timeout = "3s";
        enable_dnssec = false;
      };

      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
        parental_enabled = false;
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
          # HaGeZi's Threat Intelligence Feeds - malware, cryptojacking, spam, scam, phishing
          "https://adguardteam.github.io/HostlistsRegistry/assets/filter_44.txt"
          # HaGeZi's NSFW DNS Blocklist - adult content blocking (replaces parental_enabled, which used the failing family.adguard-dns.com upstream)
          "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/nsfw.txt"
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
