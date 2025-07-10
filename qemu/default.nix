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

  systemd.services.vfio-gpu-reset = {
    description = "Reset GPU using minimal QEMU";
    after = [ "systemd-modules-load.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "reset-gpu-qemu" ''
        echo "quit" | timeout 10s ${pkgs.qemu}/bin/qemu-system-x86_64 \
          -machine q35 \
          -device vfio-pci,host=01:00.0 \
          -device vfio-pci,host=01:00.1 \
          -nographic \
          -serial none \
          -monitor stdio <<< "quit" || true
      '';
      RemainAfterExit = true;
    };
  };
}
