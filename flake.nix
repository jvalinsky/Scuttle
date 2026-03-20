{
  description = "Scuttle: A modern Objective-C SSB implementation for macOS and Linux (GNUstep)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      overlays = import ./overlays { inherit nixpkgs; };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # 2026 Best Practice: Using Clang with libobjc2 is mandatory for modern Obj-C
        stdenv = pkgs.clangStdenv;

        # Define specific versions/overrides for GNUstep to ensure ARC and Dispatch
        libobjc = pkgs.gnustep-libobjc; # libobjc2
        libdispatch = pkgs.swift-corelibs-libdispatch;

        # Override gnustep-base to ensure it builds with the features we need
        gnustep-base-custom = pkgs.gnustep-base.overrideAttrs (old: {
          configureFlags = (old.configureFlags or [ ]) ++ [
            "--enable-libdispatch"
            "--enable-objc-arc"
            "--with-layout=gnustep"
          ];
          buildInputs = (old.buildInputs or [ ]) ++ [
            libobjc
            libdispatch
          ];
        });

        commonDeps = with pkgs; [
          openssl
          sqlite
          pkg-config
        ];

        linuxDeps = [
          pkgs.gnustep-make
          gnustep-base-custom
          pkgs.gnustep-gui
          pkgs.gnustep-back
          libobjc
          libdispatch
          pkgs.libx11
          pkgs.libxft
          pkgs.cairo
          pkgs.fontconfig
          pkgs.xvfb-run
        ];

        darwinDeps = with pkgs; [
          darwin.apple_sdk.frameworks.Foundation
          darwin.apple_sdk.frameworks.AppKit
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.SystemConfiguration
          darwin.apple_sdk.frameworks.Network
        ];

        # Go for building go-ssb-room
        goDeps = with pkgs; [
          go
        ];

        gnustepEnv = ''
          . ${pkgs.gnustep-make}/share/GNUstep/Makefiles/GNUstep.sh
          export GNUSTEP_MAKEFILES=${pkgs.gnustep-make}/share/GNUstep/Makefiles
          export LD_LIBRARY_PATH="${libobjc}/lib:${libdispatch}/lib:${gnustep-base-custom}/lib:$LD_LIBRARY_PATH"
          export GNUSTEP_PATHLIST="${pkgs.gnustep-back}/lib/GNUstep:${pkgs.gnustep-gui}/lib/GNUstep:${gnustep-base-custom}/lib/GNUstep:$GNUSTEP_PATHLIST"
        '';

        mkScuttleTarget =
          {
            pname,
            makefile,
            executableName,
            appBundleName ? null,
          }:
          stdenv.mkDerivation {
            inherit pname;
            version = "0.1.0";
            src = ./.;

            nativeBuildInputs = with pkgs; [
              pkg-config
              gnumake
              gnustep-make
              makeWrapper
            ];

            buildInputs = commonDeps ++ linuxDeps;

            dontConfigure = true;

            buildPhase = ''
              runHook preBuild
              ${gnustepEnv}
              make -f ${makefile}
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              ${gnustepEnv}
              mkdir -p "$out/bin" "$out/Applications"

              binPath="$(find . -type f -name '${executableName}' -perm -111 | head -n 1 || true)"
              if [ -n "$binPath" ]; then
                install -m755 "$binPath" "$out/bin/${executableName}"
              fi

              if [ -n "${if appBundleName == null then "" else appBundleName}" ]; then
                appPath="$(find . -type d -name '${if appBundleName == null then "" else appBundleName}.app' | head -n 1 || true)"
                if [ -n "$appPath" ]; then
                  cp -R "$appPath" "$out/Applications/"
                  cat > "$out/bin/scuttle-gui" <<EOF
#!${pkgs.runtimeShell}
export GNUSTEP_PATHLIST="${pkgs.gnustep-back}/lib/GNUstep:${pkgs.gnustep-gui}/lib/GNUstep:${gnustep-base-custom}/lib/GNUstep:\$GNUSTEP_PATHLIST"
export LD_LIBRARY_PATH="${libobjc}/lib:${libdispatch}/lib:${gnustep-base-custom}/lib:\$LD_LIBRARY_PATH"
exec "$out/Applications/${if appBundleName == null then "" else appBundleName}.app/${if appBundleName == null then "" else appBundleName}" "\$@"
EOF
                  chmod +x "$out/bin/scuttle-gui"
                fi
              fi
              runHook postInstall
            '';
          };

        linuxPackages =
          if pkgs.stdenv.isLinux then
            rec {
              scuttle-cli = mkScuttleTarget {
                pname = "scuttle-cli";
                makefile = "GNUmakefile";
                executableName = "scuttle-cli";
              };

              scuttle-gui = mkScuttleTarget {
                pname = "scuttle-gui";
                makefile = "GNUmakefile.gui";
                executableName = "ScuttleRoom";
                appBundleName = "ScuttleRoom";
              };

              default = scuttle-cli;
            }
          else
            { };

        linuxApps =
          if pkgs.stdenv.isLinux then
            {
              scuttle-cli = flake-utils.lib.mkApp {
                drv = linuxPackages.scuttle-cli;
                exePath = "/bin/scuttle-cli";
              };
              scuttle-gui = flake-utils.lib.mkApp {
                drv = linuxPackages.scuttle-gui;
                exePath = "/bin/scuttle-gui";
              };
              default = flake-utils.lib.mkApp {
                drv = linuxPackages.scuttle-cli;
                exePath = "/bin/scuttle-cli";
              };
            }
          else
            { };

        linuxChecks =
          if pkgs.stdenv.isLinux then
            {
              scuttle-cli-build = linuxPackages.scuttle-cli;
              scuttle-gui-build = linuxPackages.scuttle-gui;

              scuttle-cli-smoke = pkgs.runCommand "scuttle-cli-smoke"
                {
                  nativeBuildInputs = [ pkgs.bash ];
                }
                ''
                  test -x ${linuxPackages.scuttle-cli}/bin/scuttle-cli
                  ${linuxPackages.scuttle-cli}/bin/scuttle-cli >/dev/null 2>&1 || true
                  touch $out
                '';

              scuttle-gui-smoke = pkgs.runCommand "scuttle-gui-smoke"
                {
                  nativeBuildInputs = [
                    pkgs.bash
                    pkgs.coreutils
                  ];
                }
                ''
                  test -x ${linuxPackages.scuttle-gui}/bin/scuttle-gui
                  test -d ${linuxPackages.scuttle-gui}/Applications/ScuttleRoom.app
                  test -x ${linuxPackages.scuttle-gui}/Applications/ScuttleRoom.app/ScuttleRoom
                  touch $out
                '';
            }
          else
            { };

      in
      {
        packages = linuxPackages;

        apps = linuxApps;

        checks = linuxChecks;

        devShells.default = stdenv.mkDerivation {
          name = "scuttle-dev-shell";

          buildInputs = commonDeps ++ (if pkgs.stdenv.isDarwin then darwinDeps else linuxDeps);

          shellHook = ''
            export PS1="\[\e[1;32m\][scuttle-dev]\[\e[0m\] \w \$ "
            export PATH="$HOME/.local/bin:$PATH"

            if [ -e /etc/NIXOS ]; then
              # Linux/GNUstep specific setup
              . ${pkgs.gnustep-make}/share/GNUstep/Makefiles/GNUstep.sh
              export GNUSTEP_MAKEFILES=${pkgs.gnustep-make}/share/GNUstep/Makefiles
              
              # Ensure backend and libraries are in the search path
              export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${libobjc}/lib:${libdispatch}/lib:${gnustep-base-custom}/lib"
              
              # Append paths for bundle discovery
              export GNUSTEP_PATHLIST="${pkgs.gnustep-back}/lib/GNUstep:${pkgs.gnustep-gui}/lib/GNUstep:${gnustep-base-custom}/lib/GNUstep:''${GNUSTEP_PATHLIST}"
              
              echo "Objective-C (GNUstep) environment active on Linux (ARC/Dispatch enabled)."
            else
              echo "Objective-C environment active on Darwin."
            fi

            echo "Dependencies: Foundation, OpenSSL, SQLite, libdispatch."
          '';

          # Optimization: Export GNUSTEP_MAKEFILES for the build system
          GNUSTEP_MAKEFILES =
            if pkgs.stdenv.isDarwin then "" else "${pkgs.gnustep-make}/share/GNUstep/Makefiles";
        };

        devShells.go-ssb-room = stdenv.mkDerivation {
          name = "go-ssb-room-dev";

          buildInputs = with pkgs; [
            go
            gcc
            pkg-config
          ];

          shellHook = ''
            export PS1="\[\e[1;35m\][go-ssb-room]\[\e[0m\] \w \$ "
            export GOPATH=$HOME/go
            export PATH="$GOPATH/bin:$PATH"

            echo "Go environment for go-ssb-room (Go $(go version | awk '{print $3}'))"
            echo "To build the room server:"
            echo "  cd third-party/go-ssb-room/cmd/server && go build -tags dev"
            echo "  ./server -mode open -lishttp :3000 -lismux :8008"
          '';
        };
      }
    );
}
