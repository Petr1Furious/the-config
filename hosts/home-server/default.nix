{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./mounts.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/qemu
    ../../modules/nixos/openrgb
    ../../modules/nixos/ollama.nix
    ../../modules/nixos/vscode-server.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "home-server";

  time.timeZone = lib.mkDefault "Europe/Moscow";

  users.users.petrtsopa.extraGroups = [
    "docker"
    "libvirtd"
  ];

  boot = {
    kernel.sysctl = {
      "kernel.yama.ptrace_scope" = 2;
      "vm.compaction_proactiveness" = 0;
    };
    kernelModules = [
      "nvidia"
      "nvidia_uvm"
    ];
    blacklistedKernelModules = [
      "nouveau"
      # prevent display stack from coming up on the host
      "nvidia_drm"
      "nvidia_modeset"
      "nvidiafb"
    ];
  };

  hardware.nvidia = {
    modesetting.enable = false;
    nvidiaPersistenced = false;
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # hardware.nvidia-container-toolkit.enable = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  environment.systemPackages = [
    config.hardware.nvidia.package
  ];

  networking.firewall.allowedTCPPorts = [
    22
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443
  ];

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }
  ];

  system.stateVersion = "24.11"; # Do not touch this value unless you know what you are doing.
}
