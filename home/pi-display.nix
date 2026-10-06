{ lib, pkgs, ... }:

let
  display = pkgs.callPackage ../pkgs/pi-display { };
in
{
  systemd.user.services.pi-display = {
    Unit = {
      Description = "OLED with next trams and air quality";
      After = [
        "bme688-exporter.service"
        "ld2410-stream.service"
      ];
    };
    Service = {
      ExecStart = lib.getExe display;
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
