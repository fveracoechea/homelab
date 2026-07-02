{
  description = "My fist NixOS Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    dotfiles.url = "github:fveracoechea/dotfiles";
    dotfiles.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    home-manager,
    dotfiles,
    ...
  } @ inputs: {
    nixosConfigurations.homelab = let
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        dotfilesPkgs = dotfiles.dotfilesPkgs.${system};
      };
    in
      nixpkgs.lib.nixosSystem {
        inherit specialArgs;

        modules = [
          ./host-settings/configuration.nix
          ./services/caddy.nix
          ./services/paperless.nix
          ./services/immich.nix
          ./services/vaultwarden.nix
          home-manager.nixosModules.home-manager
          {
            nixpkgs.hostPlatform = system;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            nixpkgs.config.allowUnfree = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.users.fveracoechea = import ./host-settings/home.nix;
            home-manager.extraSpecialArgs = specialArgs;
          }
        ];
      };
  };
}
