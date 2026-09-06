# SPDX-License-Identifier: LGPL-2.1-or-later
# Shared by the Nix package and the local development launcher.
set -euo pipefail

executable="$1"
shift
config_root="${XDG_CONFIG_HOME:-$HOME/.config}/anthracite"
data_root="${XDG_DATA_HOME:-$HOME/.local/share}/anthracite"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/anthracite"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/anthracite"
for directory in "$config_root" "$data_root" "$state_root" "$cache_root"; do
    if [[ "$directory" != /* ]]; then
        printf 'Anthracite requires absolute XDG paths: %s\n' "$directory" >&2
        exit 1
    fi
    mkdir -p "$directory"
done

# FreeCAD only accepts these overrides when their directories already exist.
export FREECAD_USER_HOME="$config_root"
export FREECAD_USER_DATA="$data_root"
export FREECAD_USER_TEMP="$cache_root"
export QSG_RHI_BACKEND=opengl
exec "$executable" --user-cfg "$config_root/user.cfg" --system-cfg "$config_root/system.cfg" "$@"
