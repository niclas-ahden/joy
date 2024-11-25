fn main() {
    // Re-run this build script if roc rebuild's the app
    println!("cargo:rerun-if-changed=libapp.a");

    // Look in the workspace root
    println!("cargo:rustc-link-search=.");

    // Link wit the app static library
    println!("cargo:rustc-link-lib=static=app");
}
