{
  description = "Joy flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Provides a pinned rust toolchain with extra std targets (e.g. wasm32-wasip1, needed
    # to build/run standalone wasm repros of the glue under wasmtime).
    rust-overlay.url = "github:oxalica/rust-overlay";
    # NOTE: You can pin the version/commit of Roc by appending /<commit> to the URL like so:
    #
    #     roc.url = "github:roc-lang/roc/9fcd5a3fe88a1911ccd56ecf6e5df88c4f16c098";
    #
    # Remember to also pin `roc_std` to the same commit in `./Cargo.toml`.
    roc.url = "github:roc-lang/roc/4c206185a278f3adf7a23e8336cc94cd849b358f";
  };

  outputs = { nixpkgs, flake-utils, rust-overlay, roc, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        rocPkgs = roc.packages.${system};
        rocFull = rocPkgs.full;

        # Pinned to match Cargo.toml's roc_std rev (rustc 1.94.0), plus wasm std targets.
        rustToolchain = pkgs.rust-bin.stable."1.94.0".default.override {
          targets = [ "wasm32-unknown-unknown" "wasm32-wasip1" ];
        };

      in
      {
        formatter = pkgs.nixpkgs-fmt;

        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs;
              [
                rocFull
                zig
                wabt # provides wasm2wat for debugging
                rustToolchain # rustc + cargo + rustfmt, pinned, with wasm targets
                rust-analyzer
                lld
                wasm-pack
                wasmtime # run standalone wasm32-wasip1 repros
                simple-http-server
                watchexec
                # Testing
                playwright-test
              ] ++ lib.optionals stdenv.hostPlatform.isLinux [
                inotify-tools
              ];

            # For vscode plugin https://github.com/ivan-demchenko/roc-vscode-unofficial
            shellHook = ''
              export ROC_LANGUAGE_SERVER_PATH=${rocFull}/bin/roc_language_server
              export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
              export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
            '';
          };
        };
      });
}
