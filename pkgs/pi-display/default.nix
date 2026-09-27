{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "pi-display";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./tests
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Next trams and air quality on an SSD1306 OLED";
    platforms = lib.platforms.linux;
    mainProgram = "pi-display";
  };
}
