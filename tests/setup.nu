# SPDX-License-Identifier: LGPL-2.1-or-later
# Exercise setup against disposable repositories, never the real build/src.
const root = path self | path dirname | path dirname
def --wrapped checked [program: string, ...arguments: string] {
    let result = run-external $program ...$arguments | complete
    if $result.exit_code != 0 { error make {msg: $"Fixture command failed: ($program): ($result.stderr)"} }
}
def main [] {
    use std/assert
    let results = $root | path join build test-results
    mkdir $results
    let directory = mktemp -d -p $results setup.XXXXXX
    let fixture = $directory | path join project
    let upstream = $directory | path join upstream
    mkdir ($fixture | path join devutils) ($fixture | path join patches) $upstream
    cp ($root | path join devutils workflow.nu) ($fixture | path join devutils)
    cp ($root | path join devutils quilt-env.nu) ($fixture | path join devutils)
    checked git init -q $upstream
    "before\n" | save ($upstream | path join model.txt)
    checked git -C $upstream add model.txt
    checked git -C $upstream -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -qm fixture
    let pin = ^git -C $upstream rev-parse HEAD | str trim
    $pin | save ($fixture | path join freecad_commit.txt)
    $upstream | save ($fixture | path join freecad_repo.txt)
    "feature.patch\n" | save ($fixture | path join patches series)
    "--- a/model.txt\n+++ b/model.txt\n@@ -1 +1 @@\n-before\n+after\n" | save ($fixture | path join patches feature.patch)
    let workflow = $fixture | path join devutils workflow.nu
    let absent = ^nu --no-config-file $workflow setup | complete
    assert ($absent.exit_code != 0)
    assert (not ($fixture | path join build | path exists)) 'Read-only setup created build/.'
    let prepared = ^nu --no-config-file $workflow setup --fix | complete
    assert equal $prepared.exit_code 0 $prepared.stderr
    let source = $fixture | path join build src
    let model = $source | path join model.txt
    assert equal (open --raw $model) "after\n" 'Setup did not apply the patch stack.'
    'user edit' | save -f $model
    let index = $source | path join .git index
    let before = open --raw $index | hash sha256
    let inspect = ^nu --no-config-file $workflow setup | complete
    assert equal $inspect.exit_code 0 $inspect.stderr
    assert equal (open --raw $index | hash sha256) $before 'Read-only setup changed the Git index.'
    assert equal (open --raw $model) 'user edit'
    let repeated = ^nu --no-config-file $workflow setup --fix | complete
    assert equal $repeated.exit_code 0 $repeated.stderr
    assert equal (open --raw $model) 'user edit' 'Setup overwrote dirty source.'
    ('0' | fill -w 40 -c '0') | save -f ($fixture | path join freecad_commit.txt)
    let mismatch = ^nu --no-config-file $workflow setup --fix | complete
    assert ($mismatch.exit_code != 0)
    assert equal (^git -C $source rev-parse HEAD | str trim) $pin 'Setup reset a mismatched checkout.'
    assert equal (open --raw $model) 'user edit'
    let invalid = ^nu --no-config-file $workflow setup --typo | complete
    assert ($invalid.exit_code != 0)
    rm -r $directory
    print 'Setup safety tests passed.'
}
