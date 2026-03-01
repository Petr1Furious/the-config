{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.ollama = {
    enable = true;
    port = 11434;
    acceleration = "cuda";
    environmentVariables = {
      OLLAMA_LLM_LIBRARY = "cuda";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    };
  };

  environment.systemPackages = with pkgs; [
    ollama
  ];

  hardware.graphics.enable = true;
}
