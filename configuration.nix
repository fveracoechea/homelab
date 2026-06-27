{inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
    inputs.dotfiles.nixosModules.default
  ];

  nix = {
    gc.automatic = true;
    optimise.automatic = true;
    gc.options = "--delete-older-than 30d";

    settings.experimental-features = ["nix-command" "flakes"];
    settings.trusted-users = ["root" "@wheel"];
  };

  networking = {
    firewall.enable = true;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      X11Forwarding = false;
    };
  };

  users.users.fveracoechea = {
    password = "12345";
    isNormalUser = true;
    description = "Francisco Veracoechea";
    extraGroups = ["wheel" "networkmanager" "docker"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB3gt/1eR57Gx6gI2PMyXcu0gMCq708ttjP54TLwR/fh fveracoechea@nixos"
    ];
  };
}
