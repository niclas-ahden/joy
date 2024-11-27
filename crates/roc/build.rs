fn main() {
    // Re-run this build script if roc rebuild's the app
    println!("cargo:rerun-if-changed=libapp.a");

    // Look in the workspace root
    let root = helpers::workspace_root();
    println!(
        "cargo::warning=Searching for libapp.a in {}",
        root.display()
    );
    println!("cargo:rustc-link-search={}", root.display());

    // Link wit the app static library
    println!("cargo:rustc-link-lib=static=app");
}
