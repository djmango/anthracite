# SPDX-License-Identifier: LGPL-2.1-or-later
# `use devutils/quilt-env.nu *` also makes these available interactively.
const root = path self | path dirname | path dirname
export-env {
    $env.ANTHRACITE_ROOT = $root
    $env.QUILT_PATCHES = $env.ANTHRACITE_ROOT | path join patches
    $env.QUILT_PUSH_ARGS = "--color=auto"
    $env.QUILT_DIFF_OPTS = "--show-c-function"
    $env.QUILT_PATCH_OPTS = "--unified --reject-format=unified"
    $env.QUILT_DIFF_ARGS = "-p ab --no-timestamps --no-index --color=auto"
    $env.QUILT_REFRESH_ARGS = "-p ab --no-timestamps --no-index --strip-trailing-whitespace"
    $env.QUILT_COLORS = "diff_hdr=1;32:diff_add=1;34:diff_rem=1;31:diff_hunk=1;33:diff_ctx=35:diff_cctx=33"
    $env.QUILT_SERIES_ARGS = "--color=auto"
    $env.QUILT_PATCHES_ARGS = "--color=auto"
    $env.LC_ALL = "C"
    if ($env.LESS? | is-not-empty) and ($env.QUILT_PAGER? == null) { $env.QUILT_PAGER = "less -FRX" }
}

export def --wrapped quilt [...arguments: string] {
    ^quilt --quiltrc - ...$arguments
    if $env.LAST_EXIT_CODE != 0 { error make {msg: $"Quilt failed: ($arguments | str join ' ')"} }
}
