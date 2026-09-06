# SPDX-License-Identifier: LGPL-2.1-or-later
# Only a forwarding stub for launcher argument tests; signals use the real runtime.
def --wrapped main [...arguments: string] {
    use std/assert
    assert equal $arguments.0 '--supervise'
    exec $arguments.1 ...($arguments | skip 2)
}
