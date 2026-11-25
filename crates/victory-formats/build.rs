use std::{env, fs, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=LOAM_BCPACK_TABLES");
    println!("cargo:rustc-check-cfg=cfg(loam_bcpack_tables)");

    let Some(source) = env::var_os("LOAM_BCPACK_TABLES").map(PathBuf::from) else {
        return;
    };
    let destination = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo sets OUT_DIR"))
        .join("bcpack-tables.bin");
    fs::copy(&source, destination).unwrap_or_else(|error| {
        panic!("Could not copy the file supplied by LOAM_BCPACK_TABLES. {error}")
    });
    println!("cargo:rerun-if-changed={}", source.display());
    println!("cargo:rustc-cfg=loam_bcpack_tables");
}
