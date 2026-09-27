use std::env;
use std::path::PathBuf;

fn path_from_env(name: &str) -> PathBuf {
    println!("cargo:rerun-if-env-changed={name}");
    env::var_os(name)
        .map(PathBuf::from)
        .unwrap_or_else(|| panic!("{name} is not set"))
}

fn main() {
    let bsec = path_from_env("BSEC_DIR");
    let bme68x = path_from_env("BME68X_API_DIR");
    let config = path_from_env("BSEC_CONFIG");
    println!("cargo:rerun-if-env-changed=BSEC_CONFIG_NAME");
    println!("cargo:rerun-if-changed={}", config.display());
    println!("cargo:rerun-if-changed=csrc/wrapper.h");

    cc::Build::new()
        .file(bme68x.join("bme68x.c"))
        .include(&bme68x)
        .compile("bme68x");

    println!(
        "cargo:rustc-link-search=native={}",
        bsec.join("bin/RaspberryPi/PiFour_Armv8").display()
    );
    println!("cargo:rustc-link-lib=static=algobsec");
    println!("cargo:rustc-link-lib=m");

    bindgen::Builder::default()
        .header("csrc/wrapper.h")
        .clang_arg(format!("-I{}", bsec.join("inc").display()))
        .clang_arg(format!("-I{}", bme68x.display()))
        .allowlist_function("bsec_.*|bme68x_.*")
        .allowlist_type("bsec_.*|bme68x_.*")
        .allowlist_var("BSEC_.*|BME68X_.*")
        .derive_default(true)
        .generate()
        .expect("failed to generate BSEC/BME68x bindings")
        .write_to_file(PathBuf::from(env::var("OUT_DIR").unwrap()).join("bindings.rs"))
        .expect("failed to write bindings");
}
