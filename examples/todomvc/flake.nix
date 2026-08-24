{
  description = "joy-todomvc";

  nixConfig = {
    extra-substituters = [ "https://niclas-ahden.cachix.org" ];
    extra-trusted-public-keys = [ "niclas-ahden.cachix.org-1:FdGli1vBk0cTuVJV27Tau/JvlbW+Ly3pRwFByyqdke0=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    roc-src = {
      url = "github:roc-lang/roc/f8aa2b12f8a4079a11b3b7926a49d2cb3ecff697";
      flake = false;
    };
  };

  outputs = { nixpkgs, flake-utils, roc-src, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        version = roc-src.shortRev or "dirty";

        zig = pkgs.zig_0_16;

        vendored = pkgs.callPackage "${roc-src}/build.zig.zon.nix" { inherit zig; };

        bootstrapBase = "https://github.com/roc-lang/roc-bootstrap/releases/download/zig-0.16.0-binaryen";
        hostBootstrap = {
          "x86_64-linux" = { pkgHash = "N-V-__8AAGJLMhhn8pu3uyxtKTIlha8CxCjE6TNpLYvvj-cz"; file = "x86_64-linux-musl.tar.xz"; sha256 = "sha256-rvj4CqOfLibgPjdxDDFl9Rspwr9NOqQDNuqZqCmdiiQ="; };
          "aarch64-linux" = { pkgHash = "N-V-__8AACK4KheKSiltX0PPURTNh0CvJhsopNXzcXpvq9pS"; file = "aarch64-linux-musl.tar.xz"; sha256 = "sha256-Uienx53sFqoov9R3r1Rl8MOOuevyDfRFTTQdEy1FLxw="; };
          "x86_64-darwin" = { pkgHash = "N-V-__8AAJrG0hG7ZWMT8yxRBa17ivn77bWqDpseO904PYT7"; file = "x86_64-macos-none.tar.xz"; sha256 = "sha256-itVlXxuYFxdOSYm2dasTI0NXgzi5vCIu9k7otvLLd2s="; };
          "aarch64-darwin" = { pkgHash = "N-V-__8AAKS-VRH7JXsaDHpnFPSd-B5fSdtnDbh0XrfnncWc"; file = "aarch64-macos-none.tar.xz"; sha256 = "sha256-SDwhz/eUhlhEJght1kX5ng0Z6JiFNWIk30H3rgpxUyw="; };
        }.${system};

        hostBootstrapPkg = pkgs.runCommand "roc-host-bootstrap-${system}"
          {
            src = pkgs.fetchurl {
              url = "${bootstrapBase}/${hostBootstrap.file}";
              hash = hostBootstrap.sha256;
            };
          } ''
          mkdir -p "$out/${hostBootstrap.pkgHash}"
          tar -xf "$src" -C "$out/${hostBootstrap.pkgHash}" --strip-components=1
        '';

        roc-deps = pkgs.symlinkJoin {
          name = "roc-zig-packages";
          paths = [ vendored hostBootstrapPkg ];
        };

        roc = pkgs.stdenv.mkDerivation {
          pname = "roc";
          inherit version;
          src = roc-src;

          # To patch the compiler, drop a diff in nix/ and list it here, e.g.
          #
          #   patches = [ ./nix/roc-pr-12345.patch ];

          nativeBuildInputs = [ zig ];

          dontConfigure = true;

          buildPhase = ''
            export HOME=$TMPDIR
          '' + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
            # Zig finds macOS frameworks by running xcrun, which no nix build
            # has on its PATH, so linking CoreFoundation/CoreServices for the
            # watch module fails. Zig does read these two nixpkgs variables, so
            # point them at the SDK the darwin stdenv already provides. Don't
            # reach for --sysroot instead, it turns this detection off.
            export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE:-} -iframework $SDKROOT/System/Library/Frameworks"
            export NIX_LDFLAGS="''${NIX_LDFLAGS:-} -L$SDKROOT/usr/lib"
          '' + ''

            # `--system` points Zig at the prevendored package set (looked up by
            # bare hash), so the build never touches the network. Zig still
            # wants writable cache dirs, so keep those under $TMPDIR.
            zig build roc -Doptimize=ReleaseFast \
              --system ${roc-deps} \
              --cache-dir $TMPDIR/zig-local-cache \
              --global-cache-dir $TMPDIR/zig-global-cache
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp zig-out/bin/roc $out/bin/
          '' + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
            # roc links the apps it builds against a libSystem.tbd stub it ships
            # itself, and looks for it next to the binary. Same layout as the
            # official nightlies.
            cp -R src/cli/darwin $out/bin/darwin
          '';

          meta = {
            description = "Roc";
            homepage = "https://github.com/roc-lang/roc";
            license = lib.licenses.upl;
            mainProgram = "roc";
            platforms = lib.platforms.unix;
          };
        };

      in
      {
        formatter = pkgs.nixpkgs-fmt;

        packages = {
          inherit roc roc-deps;
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
