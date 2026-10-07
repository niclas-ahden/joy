{
  description = "Joy flake";

  nixConfig = {
    extra-substituters = [ "https://niclas-ahden.cachix.org" ];
    extra-trusted-public-keys = [ "niclas-ahden.cachix.org-1:FdGli1vBk0cTuVJV27Tau/JvlbW+Ly3pRwFByyqdke0=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    # Roc compiler revision, keep the `?dir=src` at the end.
    roc-src.url = "github:roc-lang/roc/233bb124dc2ded5bcc0a551b1fdf0fa7a4dda0e9?dir=src";
    roc-nix = {
      url = "github:niclas-ahden/roc-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.roc-src.follows = "roc-src";
    };
  };

  outputs = { nixpkgs, flake-utils, rust-overlay, roc-nix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        inherit (pkgs) lib;

        inherit (roc-nix.packages.${system}) roc roc-safe;

        # Pinned rust for the wasm host (host/host.rs), with wasm std targets.
        rustToolchain = pkgs.rust-bin.stable."1.94.0".default.override {
          targets = [ "wasm32-unknown-unknown" "wasm32-wasip1" ];
        };

      in
      {
        formatter = pkgs.nixpkgs-fmt;

        packages = {
          inherit roc roc-safe;
          default = roc;
        };

        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs;
              [
                roc # the from-source Roc compiler (ReleaseFast)
                cachix # pushes that compiler to the binary cache
                wabt # provides wasm2wat for debugging
                binaryen # provides wasm-opt, shrinks the benchmarked wasm
                rustToolchain # rustc + cargo + rustfmt, pinned, with wasm targets
                rust-analyzer
                lld
                wasm-pack
                wasmtime # run standalone wasm32-wasip1 repros
                watchexec
                caddy # serves the todomvc template's dev and test servers
                nodejs_22 # runs the tests/check_*.mjs harnesses
                # Testing
                playwright-test
              ] ++ lib.optionals stdenv.hostPlatform.isLinux [
                inotify-tools
                gdb # backtraces of compiler hangs and crashes
              ];

            shellHook = ''
              export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
              export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
            '';
          };
        };
      });
}
