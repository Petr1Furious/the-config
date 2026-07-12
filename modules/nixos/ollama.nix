{
  config,
  lib,
  pkgs-unstable,
  ...
}:
{
  services.ollama = {
    enable = true;
    port = 11434;
    package = pkgs-unstable.ollama-cuda;
    environmentVariables = {
      OLLAMA_LLM_LIBRARY = "cuda";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
      OLLAMA_CONTEXT_LENGTH = "${toString 65536}";
    };
  };

  environment.systemPackages = with pkgs-unstable; [
    ollama
  ];

  hardware.graphics.enable = true;
}
