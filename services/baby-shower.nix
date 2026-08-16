{
  config,
  inputs,
  pkgs,
  ...
}: let
  domain = "baby.veracoechea.com";
  dataDir = "/var/lib/baby-shower";
  hostPort = 3001;
  package = pkgs.callPackage ../apps/baby-shower/package.nix {
    src = inputs.baby-shower;
  };
  image = pkgs.callPackage ../apps/baby-shower/image.nix {
    baby-shower = package;
  };
in {
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 root root - -"
  ];

  virtualisation.oci-containers.containers.baby-shower = {
    image = "baby-shower:latest";
    imageFile = image;
    ports = ["127.0.0.1:${toString hostPort}:3000"];
    volumes = ["${dataDir}:/data"];
    environmentFiles = ["${dataDir}/baby-shower.env"];
    environment = {
      MIGRATIONS_DIR = "/app/drizzle";
      NODE_ENV = "production";
      PORT = "3000";
    };
    extraOptions = [
      "--cap-drop=ALL"
      "--read-only"
      "--security-opt=no-new-privileges"
      "--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=64m"
    ];
  };

  security.acme.certs."${domain}" = {
    inherit domain;
    dnsProvider = "cloudflare";
    dnsResolver = "1.1.1.1:53";
    dnsPropagationCheck = true;
    group = config.services.caddy.group;
    environmentFile = "/var/lib/caddy/caddy.env";
    reloadServices = ["caddy.service"];
  };

  services.caddy.virtualHosts."${domain}".extraConfig = ''
    tls /var/lib/acme/${domain}/fullchain.pem /var/lib/acme/${domain}/key.pem
    reverse_proxy 127.0.0.1:${toString hostPort}
  '';
}
