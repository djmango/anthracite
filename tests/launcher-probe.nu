# SPDX-License-Identifier: LGPL-2.1-or-later
def --wrapped main [...arguments: string] {
    use std/assert
    assert equal $env.FREECAD_USER_HOME ($env.XDG_CONFIG_HOME | path join anthracite)
    assert equal $env.FREECAD_USER_DATA ($env.XDG_DATA_HOME | path join anthracite)
    assert equal $env.FREECAD_USER_TEMP ($env.XDG_CACHE_HOME | path join anthracite)
    assert equal $arguments [--user-cfg ($env.FREECAD_USER_HOME | path join user.cfg) --system-cfg ($env.FREECAD_USER_HOME | path join system.cfg) 'model with spaces.FCStd']
    for path in [$env.FREECAD_USER_HOME $env.FREECAD_USER_DATA $env.FREECAD_USER_TEMP] { assert ($path | path exists) }
}
