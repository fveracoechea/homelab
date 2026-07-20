{...}: {
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 4194304;
    "net.core.wmem_max" = 4194304;
  };

  services.unbound = {
    enable = true;
    resolveLocalQueries = false;
    enableRootTrustAnchor = true;
    localControlSocketPath = "/run/unbound/unbound.ctl";

    settings.server = {
      interface = ["127.0.0.1"];
      port = 5335;
      access-control = [
        "127.0.0.0/8 allow"
        "10.0.0.0/24 allow"
      ];

      num-threads = 2;
      msg-cache-size = "64m";
      rrset-cache-size = "128m";
      key-cache-size = "4m";
      neg-cache-size = "4m";
      msg-cache-slabs = 4;
      rrset-cache-slabs = 4;
      infra-cache-slabs = 4;
      key-cache-slabs = 4;

      so-rcvbuf = "4m";
      so-sndbuf = "4m";

      prefetch = true;
      prefetch-key = true;
      qname-minimisation = true;

      local-data = [
        "\"docs.veracoechea.com. IN A 100.64.0.1\""
        "\"photos.veracoechea.com. IN A 100.64.0.1\""
        "\"warden.veracoechea.com. IN A 100.64.0.1\""
        "\"home.veracoechea.com. IN A 100.64.0.1\""
        "\"ai-docs.veracoechea.com. IN A 100.64.0.1\""
        "\"ad-blocker.veracoechea.com. IN A 100.64.0.1\""
      ];
    };

    settings.remote-control = {
      control-enable = true;
      control-interface = "/run/unbound/unbound.ctl";
    };
  };
}
