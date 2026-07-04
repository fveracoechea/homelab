{...}: {
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    authKeyFile = "/var/lib/tailscale/auth-key";
    extraUpFlags = ["--login-server=https://vpn.veracoechea.com"];
  };
}
