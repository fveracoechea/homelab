{...}: {
  services.immich = {
    enable = true;
    host = "10.0.0.2";
    openFirewall = false;
  };

  services.redis.servers.immich.logLevel = "warning";

  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [2283];
}
