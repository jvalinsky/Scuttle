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
          config.allowUnfree = true;
        };

        # 2026 Best Practice: Using Clang with libobjc2 is mandatory for modern Obj-C
        stdenv = pkgs.clangStdenv;

        # Define specific versions/overrides for GNUstep to ensure ARC and Dispatch
        libobjc = pkgs.gnustep-libobjc; # libobjc2
        libdispatch = pkgs.swift-corelibs-libdispatch;
        
        # Override gnustep-base to ensure it builds with the features we need
        gnustep-base-custom = pkgs.gnustep-base.overrideAttrs (old: {
          configureFlags = (old.configureFlags or []) ++ [
            "--enable-libdispatch"
            "--enable-objc-arc"
            "--with-layout=gnustep"
          ];
          buildInputs = (old.buildInputs or []) ++ [ libobjc libdispatch ];
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

      in
      {
        devShells.default = stdenv.mkDerivation {
          name = "scuttle-dev-shell";
          
          buildInputs = commonDeps 
            ++ (if pkgs.stdenv.isDarwin then darwinDeps else linuxDeps);

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
          GNUSTEP_MAKEFILES = if pkgs.stdenv.isDarwin then "" else "${pkgs.gnustep-make}/share/GNUstep/Makefiles";
        };
      }
    );
}
