{
  description = "js-framework-benchmark dev shell (runner + comparison entries)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        devShells.default = pkgs.mkShell {
          buildInputs = [
            # Benchmark runner toolchain
            pkgs.nodejs_22 # provides node + npm + npx for the official runner
            pkgs.jq
            pkgs.git

            # For comparison entries built from source:
            #   Elm (keyed/elm) -- the npm `elm` package ships a binary that won't run
            #   on NixOS, so provide the compiler via nix instead.
            pkgs.elmPackages.elm
          ] ++ pkgs.lib.optionals (!pkgs.stdenv.isDarwin) [
            pkgs.inotify-tools
          ];

          # The Joy entries need no toolchain from this shell: their build.sh
          # runs inside the Joy repo's own dev shell via direnv (the new roc
          # compiler + rustc live there).
          shellHook = ''
            # Use the nix-provided browsers for Playwright (the npm-downloaded ones don't
            # run on NixOS). NOTE: this nixpkgs ships playwright-driver 1.59.1 while
            # webdriver-ts pins playwright 1.58.2, so the npm side must be aligned to
            # 1.59.1 (bump webdriver-ts's playwright deps) for the browsers here to be
            # found.
            export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
            export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
            export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
          '';
        };
      });
}
