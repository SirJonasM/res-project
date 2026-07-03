use std::env;
use std::path::PathBuf;

fn main() {
    // Put the linker script somewhere the linker can find it
    let out = &PathBuf::from(env::var_os("OUT_DIR").unwrap());
    std::fs::copy("app.ld", out.join("app.ld")).unwrap();
    
    println!("cargo:rustc-link-search={}", out.display());
    
    // Pass the linker script to the linker
    println!("cargo:rustc-link-arg=-Tapp.ld");

    // Re-run this build script if the linker script changes
    println!("cargo:rerun-if-changed=app.ld");
}
