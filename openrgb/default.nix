{
  config,
  lib,
  pkgs,
  ...
}:
{
  boot.kernelModules = [
    "i2c-dev"
    "i2c-piix4"
  ];

  boot.kernelParams = [ "acpi_enforce_resources=lax" ];

  services.udev.packages = [ pkgs.openrgb ];

  systemd.services.openrgb-profile = {
    description = "Disable RAM LEDs";
    after = [ "graphical-session.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.openrgb}/bin/openrgb -p ${./black.orp}";
      User = "root";
      RemainAfterExit = true;
    };
  };
}
