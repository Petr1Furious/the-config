{ lib, ... }:

{
  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = lib.mkDefault "/dev/disk/by-id/nvme-eui.002538b951b2323c";
        content = {
          type = "gpt";
          partitions = {
            BOOT = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };

            ESP = {
              size = "1G";
              type = "EF00";
              priority = 2;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };

            root = {
              size = "100%";
              type = "FD00";
              priority = 3;
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };

      nvme1 = {
        type = "disk";
        device = lib.mkDefault "/dev/disk/by-id/nvme-eui.002538b951b23239";
        content = {
          type = "gpt";
          partitions = {
            BOOT = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };

            ESP = {
              size = "1G";
              type = "EF00";
              priority = 2;
            };

            root = {
              size = "100%";
              type = "FD00";
              priority = 3;
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };
    };

    mdadm = {
      root = {
        type = "mdadm";
        level = 0;
        metadata = "1.2";
        content = {
          type = "lvm_pv";
          vg = "pool";
        };
      };
    };

    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          root = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "defaults" ];
            };
          };
        };
      };
    };
  };
}
