{ lib, pkgs, ... }:

let
  exporter = pkgs.callPackage ../pkgs/bme688-exporter { };
  tailscaleAddress = "100.67.147.81";
in
{
  systemd.user.services.bme688-exporter = {
    Unit.Description = "BME688 air quality exporter";
    Service = {
      ExecStart = "${lib.getExe exporter} --listen ${tailscaleAddress}:9688";
      StateDirectory = "bme688-exporter";
      # User units can't wait for tailscaled, so retry until its address exists.
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
