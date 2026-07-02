{...}: {
  services.immich = {
    enable = true;
    host = "10.0.0.2";
    openFirewall = true;
  };

  services.redis.servers.immich.logLevel = "warning";
}
