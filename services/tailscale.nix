{...}: {
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    authKeyFile = "/var/lib/tailscale/auth-key";
    extraSetFlags = ["--advertise-routes=10.0.0.0/24"];
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [443];
}
