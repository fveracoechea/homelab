{inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
    inputs.dotfiles.nixosModules.default
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nixpkgs.system.allowUnfree = true;

  nix = {
    gc.automatic = true;
    optimise.automatic = true;
    gc.options = "--delete-older-than 30d";

    settings.experimental-features = ["nix-command" "flakes"];
    settings.trusted-users = ["root" "@wheel"];
  };

  dotfiles = {
    docker.enable = true;
    system-shell.enable = true;
    timezone.enable = true;
  };

  networking = {
    firewall.enable = true;
    hostName = "homelab";
    wireless.enable = true;
    networkmanager.enable = true;
  };

  programs.ssh.startAgent = true;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      # PasswordAuthentication = false;
      X11Forwarding = false;
    };
  };

  time.timeZone = "America/New_York";

  i18n = let
    locale = "en_US.UTF-8";
  in {
    defaultLocale = locale;
    extraLocaleSettings = {
      LC_ADDRESS = locale;
      LC_IDENTIFICATION = locale;
      LC_MEASUREMENT = locale;
      LC_MONETARY = locale;
      LC_NUMERIC = locale;
      LC_NAME = locale;
      LC_PAPER = locale;
      LC_TELEPHONE = locale;
      LC_MESSAGES = locale;
      LC_TIME = locale;
    };
  };

  services.xserver = {
    enable = true;
    xkb = {
      layout = "us";
      variant = "";
    };
    videoDrivers = ["modesetting"];
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

  # DO NOT CHANGE
  system.stateVersion = "26.05";
}
