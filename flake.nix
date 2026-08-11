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
    roc-src = {
      url = "github:roc-lang/roc/94cbed386c51a8739ced3be76e7ab7b84dd22852";
      flake = false;
    };
  };

  outputs = { nixpkgs, flake-utils, rust-overlay, roc-src, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        inherit (pkgs) lib;

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

        mkRoc = optimize: pkgs.stdenv.mkDerivation {
          pname = "roc" + (if optimize == "ReleaseFast" then "" else "-" + lib.toLower optimize);
          version = roc-src.shortRev or "dirty";
          src = roc-src;

          # roc-lang/roc#10562, rebased onto the pin (the PR branches off an
          # older main and conflicts there, but the only conflicts were the
          # serialized-layout version bump and its golden hash, both taken
          # from the PR). It fixes the exponential specialization of open Try
          # chains (#10529), which otherwise makes our examples take minutes
          # to build. Drop this once the PR is merged and the pin moves past
          # it.
          patches = [ ./nix/roc-pr-10562.patch ];

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
            zig build roc -Doptimize=${optimize} \
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

        # ReleaseFast is the compiler we build/test the platform with: it is ~3x
        # faster end-to-end than a Debug/ReleaseSafe compiler on the example loop.
        # roc-safe keeps the safety-checked build around for chasing compiler bugs.
        roc = mkRoc "ReleaseFast";
        roc-safe = mkRoc "ReleaseSafe";

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
                cachix # ./cache.roc pushes that compiler to the binary cache
                zig
                wabt # provides wasm2wat for debugging
                rustToolchain # rustc + cargo + rustfmt, pinned, with wasm targets
                rust-analyzer
                lld
                wasm-pack
                wasmtime # run standalone wasm32-wasip1 repros
                simple-http-server
                watchexec
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
