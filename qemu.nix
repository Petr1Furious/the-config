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
}
