{ lib, pkgs, ... }:

let
  stream = pkgs.callPackage ../pkgs/ld2410-stream { };
  tailscaleAddress = "100.67.147.81";
in
{
  systemd.user.services.ld2410-stream = {
    Unit.Description = "LD2410 presence radar stream";
    Service = {
      ExecStart = "${lib.getExe stream} --listen ${tailscaleAddress}:2410";
      # User units can't wait for tailscaled, so retry until its address exists.
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
