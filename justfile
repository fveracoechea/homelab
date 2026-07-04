deploy-vps:
 nixos-rebuild switch --flake .#hostinger --target-host hostinger --sudo


deploy-homelap:
  nixos-rebuild switch --flake .#homelab --target-host homelab --sudo
