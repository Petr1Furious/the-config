{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "ld2410-stream";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "LD2410 presence radar readings as a JSON-lines TCP stream";
    platforms = lib.platforms.linux;
    mainProgram = "ld2410-stream";
  };
}
