{
  lib,
  rustPlatform,
  requireFile,
  fetchFromGitHub,
  unzip,
}:

let
  bsec = requireFile {
    name = "bsec_v3-3-0-1.zip";
    sha256 = "19nllk2if3p3hvarlfcjd4i2jbmqq7ch2hvna9fhd45s6hsz1b5f";
    message = ''
      BSEC is proprietary and has to be downloaded from Bosch Sensortec by hand.
      Put bsec_v3-3-0-1.zip in the current directory and run:
        nix-store --add-fixed sha256 bsec_v3-3-0-1.zip
    '';
  };

  bme68x-api = fetchFromGitHub {
    owner = "boschsensortec";
    repo = "BME68x_SensorAPI";
    tag = "v4.4.8";
    hash = "sha256-1sIVMn2FcQ/ov2LS5zq48sS8LipPBpoFShYVuMO+/Tk=";
  };

  bsecVariant = "release_bin/IAQ";
  bsecConfig = "bme688_iaq_33v_3s_4d";
in
rustPlatform.buildRustPackage {
  pname = "bme688-exporter";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./build.rs
      ./csrc
      ./src
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [
    rustPlatform.bindgenHook
    unzip
  ];

  env = {
    BME68X_API_DIR = "${bme68x-api}";
    BSEC_CONFIG_NAME = bsecConfig;
  };

  preBuild = ''
    unzip -q ${bsec} '${bsecVariant}/*' -d bsec
    export BSEC_DIR=$PWD/bsec/${bsecVariant}
    export BSEC_CONFIG=$BSEC_DIR/config/bme688/${bsecConfig}/bsec_iaq.config
  '';

  meta = {
    description = "Prometheus exporter for a BME688 driven by Bosch BSEC";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
    mainProgram = "bme688-exporter";
  };
}
