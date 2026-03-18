{
  description = "Scuttle: A modern Objective-C SSB implementation for macOS and Linux (GNUstep)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            # Ensure we can use non-free if needed for specific drivers/assets
            allowUnfree = true;
          };
        };

        # 2026 Best Practice: Using Clang with libobjc2 is mandatory for modern Obj-C
        stdenv = pkgs.clangStdenv;

        # GNUstep with maximum features enabled for 2026
        # We override standard gnustep to ensure libdispatch and ARC support are optimized
        gnustep = pkgs.gnustep.override {
          base = pkgs.gnustep.base.overrideAttrs (old: {
            # 2026: libdispatch integration is key for our codebase
            configureFlags = (old.configureFlags or [ ]) ++ [
              "--enable-libdispatch"
              "--enable-objc-arc"
              "--with-layout=gnustep"
            ];
            buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.libdispatch pkgs.libobjc ];
          });
        };

        # Shared dependencies across Darwin and Linux
        commonDeps = with pkgs; [
          openssl
          sqlite
          pkg-config
        ];

        # Linux-specific dependencies (GNUstep stack)
        linuxDeps = with pkgs; [
          gnustep.base
          gnustep.gui
          gnustep.back
          gnustep.make
          libdispatch
          libobjc
          # Graphics stack for GNUstep back
          xorg.libX11
          xorg.libXft
          cairo
          fontconfig
        ];

        # Darwin-specific dependencies
        darwinDeps = with pkgs; [
          darwin.apple_sdk.frameworks.Foundation
          darwin.apple_sdk.frameworks.AppKit
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.SystemConfiguration
        ];

      in
      {
        devShells.default = stdenv.mkDerivation {
          name = "scuttle-dev-shell";
          
          buildInputs = commonDeps 
            ++ (if pkgs.stdenv.isDarwin then darwinDeps else linuxDeps);

          shellHook = ''
            export PS1="\[\e[1;32m\][scuttle-dev]\[\e[0m\] \w \$ "
            
            if [ -e /etc/NIXOS ]; then
              # Linux/GNUstep specific setup
              # Sourcing GNUstep.sh is the "canonical" way to set up paths
              # In 2026 Nix, we ensure the environment variables are correctly mapped
              . ${gnustep.make}/share/GNUstep/Makefiles/GNUstep.sh
              export GNUSTEP_MAKEFILES=${gnustep.make}/share/GNUstep/Makefiles
              export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${pkgs.libobjc}/lib:${pkgs.libdispatch}/lib"
              echo "Objective-C (GNUstep) environment active on Linux."
            else
              echo "Objective-C environment active on Darwin."
            fi
            
            echo "Dependencies: Foundation, $(if [ -e /etc/NIXOS ]; then echo "GNUstep GUI"; else echo "AppKit"; fi), OpenSSL, SQLite."
          '';

          # Optimization: Export GNUSTEP_MAKEFILES for the build system
          GNUSTEP_MAKEFILES = if pkgs.stdenv.isDarwin then "" else "${gnustep.make}/share/GNUstep/Makefiles";
        };
      }
    );
}
