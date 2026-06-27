{inputs, ...}: {
  imports = [
    inputs.dotfiles.homeManagerModules.default
  ];

  home.username = "fveracoechea";
  home.homeDirectory = "/home/fveracoechea";

  users.users.fveracoechea = {
    isNormalUser = true;
    description = "fveracoechea";
    extraGroups = ["networkmanager" "wheel" "audio" "docker" "dialout" "plugdev"];
  };

  # DO NOT CHANGE
  home.stateVersion = "24.05";
  programs.home-manager.enable = true;
}
