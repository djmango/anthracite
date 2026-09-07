{
  description = "Anthracite: patched FreeCAD and its development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      perSystem = { pkgs, lib, ... }:
        let
          build = import ./nix/package.nix { inherit pkgs lib; };
          linux = pkgs.stdenv.hostPlatform.isLinux;
        in {
          devShells.default = (if linux then pkgs.mkShell else pkgs.mkShellNoCC) ({
            inputsFrom = lib.optionals linux [ build.package ];
            packages = (with pkgs; [ git just quilt nushell cmake ninja pkg-config cargo cargo-nextest rustc rustfmt swig ])
              ++ lib.optionals (!linux) [ pkgs.pixi ];
          } // lib.optionalAttrs linux {
            cmakeFlags = build.package.cmakeFlags;
            PYTHONPATH = pkgs.python3Packages.makePythonPath build.package.buildInputs;
            QT_PLUGIN_PATH = lib.makeSearchPath pkgs.qt6.qtbase.qtPluginPrefix
              [ pkgs.qt6.qtbase pkgs.qt6.qtsvg ];
            NIXPKGS_QT6_QML_IMPORT_PATH = lib.makeSearchPath pkgs.qt6.qtbase.qtQmlPrefix
              [ pkgs.qt6.qtdeclarative pkgs.qt6.qtwebengine ];
            COIN_GL_NO_CURRENT_CONTEXT_CHECK = "1";
          });
          checks.patch-series = build.source;
          checks.launcher = import ./nix/launcher-check.nix { inherit pkgs; };
          packages = { patched-source = build.source; } // lib.optionalAttrs linux {
            default = build.package;
            anthracite = build.package;
          };
          apps = lib.optionalAttrs linux {
            default = {
              type = "app";
              meta.description = "Launch Anthracite's patched FreeCAD";
              program = "${build.package}/bin/FreeCAD";
            };
          };
        };
    };
}
