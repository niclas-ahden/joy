fn main() {
    // Re-run this build script if Roc rebuilds the app
    println!("cargo:rerun-if-changed=libapp.a");

    // We used to look for `libapp.a` in the workspace root like so:
    //
    //     let root = helpers::workspace_root();
    //
    // That'd be Joy's root directory and all `examples/*` and small apps we wrote were _inside_
    // the `joy` directory. However, now we want to use Joy as a dependency and keep our projects
    // separate (as one normally would).
    //
    // We now vendor `joy` as a dependency and end up with a directory structure like so:
    //
    //     my-app
    //     ├── joy     <--- Vendored dependency
    //     ├── client
    //     ├── server
    //     ├── shared
    //     └── www
    //
    // When we compile our application `libapp.a` will end up in `my-app/libapp.a` and we need a
    // way to let the Joy build know about its location. Enter: `JOY_PROJECT_ROOT`. We set that env
    // var to the root of our project (`JOY_PROJECT_ROOT=/some-path/my-app`) and now we know where
    // to look. You could conveniently set the env var in your project's build script like so:
    //
    //     export JOY_PROJECT_ROOT=$(pwd)
    let root = std::env::var("JOY_PROJECT_ROOT")
        .expect("JOY_PROJECT_ROOT must be set (to your project's absolute root)");

    // NOTE: Useful for troubleshooting:
    // println!("cargo::warning=Searching for libapp.a in {}", root);

    println!("cargo:rustc-link-search={}", root);

    // Link with the app static library
    println!("cargo:rustc-link-lib=static=app");
}
