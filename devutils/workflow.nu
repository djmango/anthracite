#!/usr/bin/env nu
# SPDX-License-Identifier: LGPL-2.1-or-later
use quilt-env.nu *
const root = path self | path dirname | path dirname
const source = $root | path join build src
const patches = $root | path join patches

def --wrapped checked [program: string, ...arguments: string] {
    run-external $program ...$arguments
    if $env.LAST_EXIT_CODE != 0 { error make {msg: $"($program) failed: ($arguments | str join ' ')"} }
}
def pin [] { open --raw ($root | path join freecad_commit.txt) | str trim }
def require-source [] {
    if not ($source | path join .git | path exists) { error make {msg: 'Run just setup --fix first.'} }
    let actual = ^git -C $source rev-parse HEAD | str trim
    if $actual != (pin) { error make {msg: $"build/src is at ($actual), not (pin). Preserve its work before changing the base."} }
}
def series [] {
    open --raw ($patches | path join series) | lines | each { split row '#' | first | str trim } | where { $in != "" }
}
def safe-relative [value: string] {
    if ($value | str starts-with /) or '..' in ($value | split row /) or $value == "" {
        error make {msg: $"Unsafe relative path: ($value)"}
    }
}
def patch-name [value: string] {
    let name = if ($value | str ends-with .patch) { $value } else { $value + '.patch' }
    safe-relative $name
    if $name !~ '^[A-Za-z][A-Za-z0-9._/-]*\.patch$' { error make {msg: $"Invalid patch name: ($name)"} }
    $name
}
def top [] {
    let result = ^quilt --quiltrc - top | complete
    if $result.exit_code == 0 { $result.stdout | str trim } else { "" }
}
def validate-series [] {
    let entries = series
    if ($entries | uniq | length) != ($entries | length) { error make {msg: 'Duplicate patch in series.'} }
    for name in $entries {
        if (patch-name $name) != $name { error make {msg: $"Not a patch filename: ($name)"} }
        if not ($patches | path join $name | path exists) { error make {msg: $"Missing patch: ($name)"} }
    }
    for file in (glob ($patches | path join '**/*.patch')) {
        let name = $file | path relative-to $patches
        if $name not-in $entries { error make {msg: $"Patch missing from series: ($name)"} }
    }
    print $"Series is valid: ($entries | length) patches."
}

def --wrapped main [command: string, ...arguments: string] {
    if ($arguments | length) > 1 { error make {msg: 'Expected at most one argument.'} }
    let argument = $arguments | get -o 0 | default ""
    cd $root
    match $command {
        setup => {
            if $argument not-in ["" "--fix"] { error make {msg: 'Usage: just setup [--fix]'} }
            let fix = $argument == '--fix'
            $env.GIT_OPTIONAL_LOCKS = "0"
            let revision = pin
            if $revision !~ '^[0-9a-f]{40}$' { error make {msg: 'Invalid upstream commit hash.'} }
            let commands = [nix nu git just quilt cmake ninja cargo rustc] | append (if (sys host | get name) == "Darwin" { [pixi] } else { [] })
            mut missing = []
            for name in $commands {
                let found = which $name
                if ($found | is-empty) { $missing = $missing | append $name; print $"Missing tool: ($name)" }
            }
            if ($missing | is-not-empty) and $fix {
                if 'nix' in $missing or ($env.IN_NIX_SHELL? | is-not-empty) {
                    error make {msg: 'Required tools unavailable. Install Nix or repair the development shell first.'}
                }
                const script = path self
                exec nix develop --command nu --no-config-file $script setup --fix
            }
            validate-series
            if not ($source | path exists) {
                if not $fix { error make {msg: 'Source is missing. No changes made; run just setup --fix.'} }
                let reference = $root | path dirname | path join FreeCAD
                let options = if ($reference | path join .git | path exists) { [--reference-if-able $reference] } else { [] }
                mkdir ($source | path dirname)
                checked git clone --no-checkout ...$options (open --raw ($root | path join freecad_repo.txt) | str trim) $source
                checked git -C $source checkout --detach $revision
            }
            if 'git' in $missing { error make {msg: 'Git unavailable; remaining checks need nix develop. No changes made.'} }
            require-source
            let submodules = ^git -C $source submodule status --recursive | lines
            if ($submodules | any { $in | str starts-with '+' }) or ($submodules | any { $in | str starts-with 'U' }) {
                error make {msg: 'Submodule revisions differ from the pin. Preserve/review their work manually; setup will not reset them.'}
            }
            let uninitialized = $submodules | any { $in | str starts-with '-' }
            if $uninitialized and $fix { checked git -C $source submodule update --init --recursive }
            cd $source
            let applied = if ($source | path join .pc applied-patches | path exists) { open --raw ($source | path join .pc applied-patches) | lines } else { [] }
            let entries = series
            if $applied != ($entries | take ($applied | length)) { error make {msg: 'Applied patches do not match the series; inspect just status.'} }
            let pending = ($entries | length) - ($applied | length)
            print $"Pinned source: ($revision); patches applied: ($applied | length)/($entries | length)"
            if $fix and $pending > 0 { quilt push -a }
            if not $fix and (($missing | is-not-empty) or $uninitialized or $pending > 0) {
                error make {msg: 'Setup incomplete. No changes made; run just setup --fix.'}
            }
            print 'Setup ready. Next: just build, just test, just run.'
        }
        status => {
            print $"Pinned: (pin)"
            if not ($source | path exists) { print 'Source not materialized.'; return }
            checked git -C $source status --short
            cd $source
            for action in [applied unapplied] {
                let result = ^quilt --quiltrc - $action | complete
                print $"($action):\n($result.stdout)"
            }
        }
        validate-series => { validate-series }
        validate => {
            validate-series
            require-source
            let results = $root | path join build test-results
            mkdir $results
            let directory = mktemp -d -p $results patches.XXXXXX
            let checkout = $directory | path join source
            try {
                checked git clone --quiet --shared --no-checkout $source $checkout
                checked git -C $checkout checkout --quiet --detach (pin)
                for name in (series) {
                    checked git -C $checkout apply --check ($patches | path join $name)
                    checked git -C $checkout apply ($patches | path join $name)
                }
                checked git -C $checkout diff --check
            } catch { |err|
                error make {msg: $"Patch validation failed; checkout retained at ($directory): ($err.msg)"}
            }
            rm -r $directory
            print $"Validated (series | length) patches against (pin)."
        }
        require-source => { require-source }
        _ => {
            require-source
            cd $source
            match $command {
                patches-apply => { if (series | is-not-empty) and (top) != (series | last) { quilt push -a } }
                patches-unapply => { if (top) != "" { quilt pop -a } }
                patch-apply-next => { let result = ^quilt --quiltrc - next | complete; if $result.exit_code == 0 { quilt push } }
                patch-unapply-last => { if (top) != "" { quilt pop } }
                patch-new => {
                    let name = patch-name $argument
                    if (series | is-not-empty) and (top) != (series | last) { error make {msg: 'Run just patches-apply before creating a patch.'} }
                    mkdir ($patches | path join $name | path dirname)
                    quilt new $name
                }
                patch-edit => {
                    let name = patch-name $argument
                    if $name not-in (series) { error make {msg: $"Patch not in series: ($name)"} }
                    if (top) == $name { print 'Patch already current.'; return }
                    if (top) != "" { quilt pop -a }
                    quilt push $name
                }
                patch-add => {
                    safe-relative $argument
                    if (top) == "" { error make {msg: 'Select a patch first.'} }
                    let files = ^quilt --quiltrc - files | lines
                    if $argument not-in $files { quilt add $argument }
                }
                patch-diff => { quilt diff }
                patch-refresh => { quilt refresh }
                _ => { error make {msg: $"Unknown workflow command: ($command)"} }
            }
        }
    }
}
