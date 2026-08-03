{...}: {
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    # Allow peers to initiate direct WireGuard connections (UDP 41641) instead of
    # falling back to the DERP relay - critical for iPhones on the home LAN.
    openFirewall = true;
    authKeyFile = "/var/lib/tailscale/auth-key";
    extraUpFlags = ["--login-server=https://vpn.veracoechea.com" "--accept-dns=false"];
    extraSetFlags = ["--advertise-routes=10.0.0.0/24" "--accept-dns=false"];
  };
}
