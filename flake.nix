{
  description = "My fist NixOS Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    dotfiles.url = "github:fveracoechea/dotfiles";
    dotfiles.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    home-manager,
    dotfiles,
    disko,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      dotfilesPkgs = dotfiles.dotfilesPkgs.${system};
    };
  in {
    nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      modules = [
        ./hosts/homelab/configuration.nix
        home-manager.nixosModules.home-manager
        {
          nixpkgs.hostPlatform = system;
          nixpkgs.config.allowUnfree = true;
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.fveracoechea = import ./hosts/homelab/home.nix;
          home-manager.extraSpecialArgs = specialArgs;
        }
      ];
    };

    nixosConfigurations.hostinger = nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      modules = [
        disko.nixosModules.disko
        ./hosts/hostinger/configuration.nix
        {
          nixpkgs.hostPlatform = system;
          nixpkgs.config.allowUnfree = true;
        }
      ];
    };
  };
}
