{...}: {
  services.immich = {
    enable = true;
    host = "10.0.0.2";
    openFirewall = true;
  };

  services.redis.servers.immich.logLevel = "warning";

  services.caddy.virtualHosts."photos.veracoechea.com".extraConfig = ''
    tls internal
    reverse_proxy 127.0.0.1:2283
  '';
}
