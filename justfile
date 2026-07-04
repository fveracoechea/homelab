deploy-vps:
 nixos-rebuild switch --flake .#hostinger --target-host hostinger --sudo

deploy-homelab:
  nixos-rebuild switch --flake .#homelab --target-host homelab --sudo
