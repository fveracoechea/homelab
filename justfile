deploy-vps:
 nixos-rebuild switch --flake .#hostinger --target-host hostinger --sudo

deploy-homelab:
  nixos-rebuild switch --flake .#homelab --build-host homelab --target-host homelab --sudo
