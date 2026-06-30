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

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "github.com" = {
        IdentityFile = "~/.ssh/github_id";
        IdentitiesOnly = "yes";
        User = "git";
      };
    };
  };

  # DO NOT CHANGE
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;
}
