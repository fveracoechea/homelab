{config, ...}: {
  services.caddy = {
    enable = true;
    virtualHosts."10.0.0.2".extraConfig = ''
      tls internal
      bind 10.0.0.2
      reverse_proxy 127.0.0.1:${toString config.services.vaultwarden.config.ROCKET_PORT}
    '';
  };

  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [443];
}
