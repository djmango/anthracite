{
  description = "Anthracite: patched FreeCAD and its development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      perSystem = { pkgs, lib, ... }:
        let build = import ./nix/package.nix { inherit pkgs lib; };
        in {
          devShells.default = pkgs.mkShell {
            inputsFrom = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ build.package ];
            packages = with pkgs; [ git just quilt cmake ninja pkg-config cargo rustc ];
            cmakeFlags = lib.optionals pkgs.stdenv.hostPlatform.isLinux build.package.cmakeFlags;
            PYTHONPATH = lib.optionalString pkgs.stdenv.hostPlatform.isLinux
              (pkgs.python3Packages.makePythonPath build.package.buildInputs);
          };
          checks.patch-series = build.source;
          checks.launcher = import ./nix/launcher-check.nix { inherit pkgs; };
          packages = { patched-source = build.source; } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            default = build.package;
            anthracite = build.package;
          };
          apps = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            default = {
              type = "app";
              meta.description = "Launch Anthracite's patched FreeCAD";
              program = "${build.package}/bin/FreeCAD";
            };
          };
        };
    };
}
