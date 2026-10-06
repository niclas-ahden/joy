{
  description = "joy-todomvc";

  nixConfig = {
    extra-substituters = [ "https://niclas-ahden.cachix.org" ];
    extra-trusted-public-keys = [ "niclas-ahden.cachix.org-1:FdGli1vBk0cTuVJV27Tau/JvlbW+Ly3pRwFByyqdke0=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Roc compiler revision, keep the `?dir=src` at the end.
    roc-src.url = "github:roc-lang/roc/233bb124dc2ded5bcc0a551b1fdf0fa7a4dda0e9?dir=src";
    roc-nix = {
      url = "github:niclas-ahden/roc-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.roc-src.follows = "roc-src";
    };
  };

  outputs = { nixpkgs, flake-utils, roc-nix, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (roc-nix.packages.${system}) roc;
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        packages = {
          inherit roc;
          default = roc;
        };

        devShells =
          let
            testTools = [
              pkgs.caddy # serves www/ during ./watch.roc and ./tests.roc (see ./Caddyfile)
              pkgs.playwright-test # drives the browser during ./tests.roc
            ];
            playwrightHook = ''
              export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
              export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
            '';
          in
          {
            default = pkgs.mkShell {
              buildInputs = [ roc ] ++ testTools;
              shellHook = playwrightHook;
            };

            # Everything ./tests.roc needs except roc itself, for runs
            # against another compiler, like the nightly workflow. Prebuilt
            # in the public Nix cache, so no compiler builds here.
            tests = pkgs.mkShell {
              buildInputs = testTools;
              shellHook = playwrightHook;
            };
          };
      });
}
