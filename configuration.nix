{inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
    inputs.dotfiles.nixosModules.default
  ];
}
