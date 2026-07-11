{...}: {
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
      prefetch = true;
      prefetch-key = true;
      qname-minimisation = true;

      local-data = [
        "\"docs.veracoechea.com. IN A 10.0.0.2\""
        "\"photos.veracoechea.com. IN A 10.0.0.2\""
        "\"warden.veracoechea.com. IN A 10.0.0.2\""
        "\"home.veracoechea.com. IN A 10.0.0.2\""
        "\"ai-docs.veracoechea.com. IN A 10.0.0.2\""
        "\"ad-blocker.veracoechea.com. IN A 10.0.0.2\""
      ];
    };

    settings.remote-control = {
      control-enable = true;
      control-interface = "/run/unbound/unbound.ctl";
    };
  };
}
