{...}: {
  services.unbound = {
    enable = true;
    resolveLocalQueries = false;
    enableRootTrustAnchor = true;

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
    };
  };
}
