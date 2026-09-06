# SPDX-License-Identifier: LGPL-2.1-or-later
{ pkgs }:
let
  probe = pkgs.writeShellScript "anthracite-launch-probe" ''
    set -euo pipefail
    test "$FREECAD_USER_HOME" = "$XDG_CONFIG_HOME/anthracite"
    test "$FREECAD_USER_DATA" = "$XDG_DATA_HOME/anthracite"
    test "$FREECAD_USER_TEMP" = "$XDG_CACHE_HOME/anthracite"
    test "$1" = --user-cfg
    test "$2" = "$XDG_CONFIG_HOME/anthracite/user.cfg"
    test "$3" = --system-cfg
    test "$4" = "$XDG_CONFIG_HOME/anthracite/system.cfg"
    test "$5" = 'model with spaces.FCStd'
  '';
in pkgs.runCommand "anthracite-launcher-check" { nativeBuildInputs = [ pkgs.bash ]; } ''
  export XDG_CONFIG_HOME="$TMPDIR/config"
  export XDG_DATA_HOME="$TMPDIR/data"
  export XDG_STATE_HOME="$TMPDIR/state"
  export XDG_CACHE_HOME="$TMPDIR/cache"
  bash ${../devutils/launch.sh} ${probe} 'model with spaces.FCStd'
  printf 'user layout\n' > "$XDG_CONFIG_HOME/anthracite/user.cfg"
  bash ${../devutils/launch.sh} ${probe} 'model with spaces.FCStd'
  test "$(cat "$XDG_CONFIG_HOME/anthracite/user.cfg")" = 'user layout'
  if XDG_CONFIG_HOME=relative bash ${../devutils/launch.sh} ${probe}; then
    exit 1
  fi
  touch "$out"
''
