{inputs, ...}: {
  imports = [
    inputs.dotfiles.homeManagerModules.default
  ];

  dotfiles = {
    shell.enable = true;
    neovim.enable = true;
    fonts.enable = true;
  };

  home.username = "fveracoechea";
  home.homeDirectory = "/home/fveracoechea";

  users.users.fveracoechea = {
    isNormalUser = true;
    description = "fveracoechea";
    extraGroups = ["networkmanager" "wheel" "audio" "docker" "dialout" "plugdev"];
  };

  # DO NOT CHANGE
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;
}
