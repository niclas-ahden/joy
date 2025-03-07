{
  description = "Joy flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # NOTE: You can pin the version/commit of Roc by appending /<commit> to the URL like so:
    #
    #     roc.url = "github:roc-lang/roc/9fcd5a3fe88a1911ccd56ecf6e5df88c4f16c098";
    #
    # Remember to also pin `roc_std` to the same commit in `./Cargo.toml`.
    roc.url = "github:roc-lang/roc";
  };

  outputs = { nixpkgs, flake-utils, roc, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        rocPkgs = roc.packages.${system};
        rocFull = rocPkgs.full;

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
                rustc
                rustfmt
                rust-analyzer
                cargo
                lld
                wasm-pack
                simple-http-server
                inotify-tools
                watchexec
              ];

            # For vscode plugin https://github.com/ivan-demchenko/roc-vscode-unofficial
            shellHook = ''
              export ROC_LANGUAGE_SERVER_PATH=${rocFull}/bin/roc_language_server
            '';
          };
        };
      });
}
