{
  config,
  lib,
  pkgs,
  ...
}:

let
  devices = [
    "10de:2783"
    "10de:22bc"
  ];
in
{
  boot = {
    kernelParams = [
      "vfio-pci.ids=${lib.concatStringsSep "," devices}"
    ];
    initrd.kernelModules = [
      "vfio_pci"
      "vfio"
      "vfio_iommu_type1"
    ];
    extraModprobeConfig = ''
      softdep nvidia pre: vfio-pci
      softdep drm pre: vfio-pci
      softdep nouveau pre: vfio-pci
    '';
    blacklistedKernelModules = [
      "nouveau"
      "nvidia"
      "nvidia_drm"
      "nvidia_modeset"
      "i2c_nvidia_gpu"
    ];
  };

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      ovmf = {
        enable = true;
        packages = [
          (pkgs.OVMFFull.override {
            secureBoot = true;
            tpmSupport = true;
          }).fd
        ];
      };
      vhostUserPackages = with pkgs; [ virtiofsd ];
    };
  };
  virtualisation.spiceUSBRedirection.enable = true;

  programs.virt-manager.enable = true;

  systemd.services.libvirt-net-default = {
    description = "Define & autostart the default NAT libvirt network";
    after = [ "libvirtd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.libvirt}/bin/virsh --connect qemu:///system net-define ${./default-net.xml}
        ${pkgs.libvirt}/bin/virsh --connect qemu:///system net-autostart default
        ${pkgs.libvirt}/bin/virsh --connect qemu:///system net-start default
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
