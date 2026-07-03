use std::env;
use std::path::PathBuf;

fn main() {
    // Put the linker script somewhere the linker can find it
    let out = &PathBuf::from(env::var_os("OUT_DIR").unwrap());
    std::fs::copy("boot.ld", out.join("boot.ld")).unwrap();
    
    println!("cargo:rustc-link-search={}", out.display());
    
    // Pass the linker script to the linker
    println!("cargo:rustc-link-arg=-Tboot.ld");

    // Re-run this build script if the linker script changes
    println!("cargo:rerun-if-changed=boot.ld");
}
