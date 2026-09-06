# SPDX-License-Identifier: LGPL-2.1-or-later
{ pkgs, lib }:
let
  revision = lib.trim (builtins.readFile ../freecad_commit.txt);
  # Include submodules. Update this hash when changing freecad_commit.txt.
  upstream = assert lib.trim (builtins.readFile ../freecad_repo.txt)
    == "https://github.com/FreeCAD/FreeCAD.git";
    pkgs.fetchFromGitHub {
    owner = "FreeCAD";
    repo = "FreeCAD";
    rev = revision;
    fetchSubmodules = true;
    hash = "sha256-RP68rd19wX4gDD5PuRQ1J4Z9Qmp5HpEg6sC94RRMEdI=";
  };
  entries = builtins.filter (line: line != "") (
    map (line: lib.trim (builtins.head (lib.splitString "#" line)))
      (lib.splitString "\n" (builtins.readFile ../patches/series))
  );
  series = map (entry:
    if builtins.match "[A-Za-z][A-Za-z0-9_-]*\\.patch" entry == null then
      throw "Invalid Anthracite series entry: ${entry}"
    else ../patches + "/${entry}"
  ) entries;
  source = pkgs.applyPatches {
    name = "anthracite-source-${builtins.substring 0 12 revision}";
    src = upstream;
    patches = series;
    postPatch = ''
      cmp src/Mod/Anthracite/Runtime/Cargo.lock ${builtins.toFile "anthracite-Cargo.lock" cargoLock}
      test -f src/3rdParty/OndselSolver/CMakeLists.txt
    '';
  };

  # Cargo.lock is owned by agent-runtime.patch. Read its added-file contents
  # without keeping a second lockfile or building FreeCAD during evaluation.
  lockSections = lib.splitString "+++ b/src/Mod/Anthracite/Runtime/Cargo.lock\n"
    (builtins.readFile ../patches/agent-runtime.patch);
  lockHunk = builtins.head (lib.splitString "\n--- " (builtins.elemAt lockSections 1));
  lockLines = lib.splitString "\n" lockHunk;
  lockBody = builtins.filter (line: line != "") (builtins.tail lockLines);
  cargoLock = assert builtins.length lockSections == 2;
    assert lib.hasPrefix "@@ -0,0 " (builtins.head lockLines);
    assert builtins.all (lib.hasPrefix "+") lockBody;
    lib.concatMapStrings (line: lib.removePrefix "+" line + "\n") lockBody;
in {
  inherit source;
  package = pkgs.freecad.overrideAttrs (old: {
    pname = "anthracite";
    src = source;
    # Retain nixpkgs' platform integration patches after Anthracite's series.
    nativeBuildInputs = old.nativeBuildInputs ++ [
      pkgs.cargo pkgs.rustc pkgs.rustPlatform.cargoSetupHook
    ];
    buildInputs = old.buildInputs ++ [ pkgs.qt6.qtdeclarative ];
    cargoRoot = "src/Mod/Anthracite/Runtime";
    cargoDeps = pkgs.rustPlatform.importCargoLock { lockFileContents = cargoLock; };
    env = (old.env or { }) // { CARGO_NET_OFFLINE = "true"; };
    cmakeFlags = old.cmakeFlags ++ [ "-DBUILD_ANTHRACITE=ON" ];
    # A local builder can compile this too; parallelism follows Nix's cores setting.
    requiredSystemFeatures = [];
    postInstall = (old.postInstall or "") + ''
      # The branding template is relative to FreeCAD's application home.
      test -f "$out/Mod/Anthracite/AnthraciteDefaults.cfg"
      test -x "$out/Mod/Anthracite/anthracite-runtime"
      test -f "$out/bin/branding.xml"
    '';
    postFixup = (old.postFixup or "") + ''
      # Wrap the existing Qt/Python wrapper, preserving its complete native closure.
      mv "$out/bin/FreeCAD" "$out/bin/.anthracite-FreeCAD"
      makeWrapper ${pkgs.nushell}/bin/nu "$out/bin/FreeCAD" \
        --add-flags --no-config-file \
        --add-flags ${../devutils/launch.nu} \
        --add-flags "$out/bin/.anthracite-FreeCAD"
    '';
    meta = old.meta // {
      description = "FreeCAD with a checked Python executor and an embedded agent sidebar";
      mainProgram = "FreeCAD";
    };
  });
}
