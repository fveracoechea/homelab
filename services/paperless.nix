{...}: {
  services.paperless = {
    enable = true;
    address = "10.0.0.2";
    passwordFile = null;
    settings = {
      PAPERLESS_URL = "http://10.0.0.2:28981";
      PAPERLESS_OCR_LANGUAGE = "eng";
      PAPERLESS_CONSUMER_IGNORE_PATTERN = [
        ".DS_STORE/*"
        "desktop.ini"
      ];
    };
  };

  networking.firewall.interfaces.enp8s0.allowedTCPPorts = [28981];
}
