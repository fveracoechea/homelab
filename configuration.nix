{inputs, ...}: {
  imports = [
    ./hardware-configuration
    inputs.dotfiles.nixosModules.default
  ];
}
