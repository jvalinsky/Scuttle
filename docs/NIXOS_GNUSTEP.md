# NixOS GNUstep Targets

## Supported Linux target

Scuttle now exposes two Nix-first Linux build targets on NixOS:

- `scuttle-cli`: headless CLI/runtime target
- `scuttle-gui`: GNUstep desktop app target

The canonical workflow is:

```bash
nix develop
nix build .#scuttle-cli
nix build .#scuttle-gui
nix run .#scuttle-cli -- status
nix run .#scuttle-gui
```

The flake also exposes Linux checks for the transport-aware targets:

```bash
nix flake check
```

## Build files

- `GNUmakefile`: CLI target
- `GNUmakefile.gui`: GNUstep GUI target
- `flake.nix`: packages, apps, and checks

## Linux platform adapters

- `Sources/SSBSecretStore.h` and `Sources/SSBSecretStore.m`: platform secret-store seam
- `Sources/SSBTransport.h` and `Sources/SSBTransport.m`: repo-owned transport seam with Apple and Linux backends
- `Sources/SSBKeychain.m`: compatibility facade over the active store
- `Sources/SSBRandom.h` and `Sources/SSBRandom.m`: portable random byte helper
- `App/SRPlatformUI.h`: shared AppKit/Foundation import surface
- `App/SRPlatformNotifications.h` and `App/SRPlatformNotifications.m`: user notification adapter

## Notes

- Linux GUI runs through GNUstep AppKit using `gnustep-gui` and `gnustep-back`.
- The Linux app target expects X11/XWayland.
- The legacy `SSBURLSession` shim is no longer part of the GNUstep CLI build; GNUstep Foundation is the intended implementation.
- `checks.scuttle-cli-smoke` verifies the CLI wrapper is built and invocable.
- `checks.scuttle-gui-smoke` verifies the GNUstep app bundle and launcher wrapper are emitted.
