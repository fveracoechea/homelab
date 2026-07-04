{...}: {
  services.caddy = {
    enable = true;

    virtualHosts."10.0.0.2".extraConfig = ''
      tls internal
      bind 10.0.0.2
    '';
  };

  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [443];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [443];
}
