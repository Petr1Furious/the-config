{
  config,
  lib,
  pkgs,
  ...
}:
{
  boot = {
    kernelModules = [
      "nvidia"
      "nvidia_uvm"

      "vfio_pci"
      "vfio"
      "vfio_iommu_type1"
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

  environment.systemPackages = [
    config.hardware.nvidia.package
  ];

  services.xserver.videoDrivers = [ "nvidia" ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      vhostUserPackages = with pkgs; [ virtiofsd ];
    };
    hooks.qemu."gpu-switch" = pkgs.runCommand "gpu-switch-hook" { } ''
      install -Dm755 ${./scripts/gpu-switch.sh} $out
    '';
  };
  virtualisation.spiceUSBRedirection.enable = true;

  programs.virt-manager.enable = true;

  systemd.services.libvirt-net-default = {
    description = "Define & autostart the default NAT libvirt network";
    after = [ "libvirtd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "setup-libvirt-network" ''
        ${pkgs.libvirt}/bin/virsh --connect qemu:///system net-define ${./default-net.xml}
        ${pkgs.libvirt}/bin/virsh --connect qemu:///system net-autostart default
        ${pkgs.libvirt}/bin/virsh --connect qemu:///system net-start default || true
      '';
    };
    restartIfChanged = true;
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.libvirt-domain-win11 = {
    description = "Define Windows 11 VM in libvirt";
    after = [ "libvirt-net-default.service" ];
    wants = [ "libvirt-net-default.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.libvirt}/bin/virsh --connect qemu:///system define ${./win11.xml}
      '';
    };
    restartIfChanged = true;
    wantedBy = [ "multi-user.target" ];
  };
}
