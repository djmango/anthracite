# AGENTS.md

## Sources of truth

- `README.md` is authoritative for the product, architecture, and patch
  workflow.
- `freecad_commit.txt` is the exact upstream base.
- `patches/series` is the exact order of Anthracite changes.

## Repository model

Anthracite is a patch-stack soft fork of FreeCAD.

- FreeCAD is materialized in ignored `build/src`; it is not vendored and is not
  a submodule.
- The committed product is the pin plus the ordered `.patch` files, not the
  contents or Git history of `build/src`.
- Keep new Anthracite functionality concentrated in
  `src/Mod/Anthracite` inside the FreeCAD tree.
- Patch FreeCAD core only when a narrow integration point is materially cleaner
  or more capable than keeping the change in the Anthracite module.
- Anthracite uses the same `LGPL-2.1-or-later` license as FreeCAD. New source
  files must carry that SPDX identifier and follow FreeCAD's license-header
  conventions.
- `.gitignore` is a strict whitelist. Any new intentional repository file or
  directory must also be explicitly admitted there.

Do not commit directly inside `build/src`, add it to this repository, or leave
an implementation only in that ignored tree.

## Working in this repository

Run commands from the repository root. Workflow scripts are Nushell; test runners
live in `tests/`, while FreeCAD-embedded assertions remain Python.

### Prepare, build, and run

- `just setup` is read-only: checks tools, the upstream pin, submodules, and the
  applied patch series. It makes no downloads, installs, or source edits.
- `just setup --fix` enters the Nix tooling shell if needed, materializes missing
  source/submodules, and applies remaining patches. It does **not** reset a
  mismatched checkout, overwrite dirty patch work, configure, or compile.
- `nix develop` (or direnv) supplies tools for subsequent commands.
- `just build` prepares/updates CMake settings automatically, then compiles
  incrementally. `just run` launches without building. No separate configure step.
- `just test` runs `tests/runtests.nu`: Rust tests via cargo-nextest, then isolated
  application/executor/bridge
  tests, no real model calls. Failure logs remain under `build/test-results/`.
  Runtime and process tests belong in Rust; only FreeCAD-embedded assertions
  need Python. Nushell handles orchestration and workflow-contract tests.
- `just status` shows source changes and patch state.
- macOS build: `build/src/build/debug`; Linux development build: `build/native`.
  Linux also supports packaged `nix build` / `nix run`.

### Amend a feature

```sh
just patch-edit sidebar       # select the existing owning patch
just patch-add path/in/freecad # only for files not already owned; BEFORE editing
# Edit build/src/path/in/freecad.
just patch-diff               # inspect the whole selected patch
just patch-refresh            # persist edits in the tracked .patch file
just patches-apply            # restore the complete stack before building/testing
just validate
just build
just test
```

- Patches describe current features/divergences, not development history.
  Amend the owner; use `just patch-new feature-name` only for a new concern.
- Before editing, use `just status` and search patch headers to find the owner:
  `rg -l '^\+\+\+ b/src/path/to/file$' patches/`. Source Git diffs include the
  whole applied stack; they are not the changes belonging to the current task.
- Use the wrappers, not bare Quilt: `quilt-env.nu` supplies the absolute patch
  path, `--quiltrc -`, and consistent refresh formatting. `.pc/` is Quilt's
  bookkeeping; never hand-edit or delete it to resolve an error.
- Keep each file owned by one patch where practical. For new files, register
  their nonexistent path with `patch-add` before creating them.
- Edit materialized source and refresh with Quilt; do not normally hand-edit
  generated patch hunks. Never leave implementation only in ignored `build/src`.
- After refreshing, inspect the outer repository's patch diff for unrelated
  changes before handing off. If Quilt refuses a push/pop, inspect and preserve
  the work; do not force it with `-f` or discard rejects/backups to proceed.
- Patch names are semantic and unnumbered; only `patches/series` defines order.
- `patches-apply` / `patches-unapply` apply/unapply the entire remaining stack;
  `patch-apply-next` / `patch-unapply-last` move one patch. These alter source,
  not the series order. Preserve/refresh dirty work before moving the stack.
- `validate-series` checks names/files/order-list integrity; `validate` also
  applies all patches to an isolated clean checkout. Neither replaces tests.
- Never reset, replace, or delete a dirty source checkout. An upstream pin bump
  requires preserving work, unapplying patches, deliberately replacing the base,
  repairing the series, configuring, building, and testing.

## Product constraints

- The interface and agent experience live inside FreeCAD.
- The UI is QML-first, with Qt Quick where useful. It must be a normal FreeCAD
  dock/sidebar: movable, resizable, closable, floatable, and restorable.
- The native 3D viewport and ordinary FreeCAD interactions remain first class.
- Integrate the user's existing Codex and OpenCode installations and preserve
  their authentication, configuration, models, skills, and normal tools. Do not
  build a new general-purpose agent harness. Keep provider work behind the
  normalized runtime adapter; Claude Code is not near-term. Never duplicate the
  CAD executor or QML surface per provider.
- Only one provider and active FreeCAD document context run at a time. Do not
  add T3 Code's project registry, worktrees, or simultaneous project sessions.
- Expose one CAD-specific model tool:
  `freecad(<ordinary FreeCAD Python source>)`.
- Treat the agent as an operator of a checked Python executor. Follow the user's design
  intent; do not silently invent requirements or equate successful recompute with design
  correctness. Ground success claims in executor observations and explicit checks.
- Python is the model's compositional action language. Prefer FreeCAD document
  and workbench APIs, then registered GUI commands, then thin helpers.
- Do not replace FreeCAD with hundreds of per-operation JSON tools, a custom CAD
  language, direct `.FCStd` XML mutation, or screen-coordinate automation.
- Each mutating Python call must run on the GUI thread inside a named FreeCAD
  transaction, recompute and validate, then commit or roll back and return a
  structured CAD-aware observation.
- Documents persist between calls; invisible Python locals do not.
- Treat document revisions, internal object names, and topology ambiguity as
  correctness concerns. Never silently guess a changed face or edge.
- Keep agent observations readable and paged: feature dependencies, parameters,
  constraints and editability diagnostics, not persistence hashes. Test follow-up
  parameter edits and native undo/redo, including intervening user edits and reported
  topology remapping; a valid final solid alone is not sufficient.

## Technology boundaries

- Linux: Nix owns all build/runtime dependencies. macOS: Nix supplies workflow
  tools, Rust and Pixi; FreeCAD's pinned `pixi.toml`/`pixi.lock` supply the native
  environment. Use its CMake preset and locked environment, not Homebrew CAD libs.
- Keep mutable configuration, session state, and local UI overrides under XDG paths.
  Launching or changing a dock must not require rebuilding FreeCAD. Local overrides
  must be identifiable and reloadable; native/executor changes still require checks.
- Use Rust whenever the work is naturally self-contained and doing so does not
  make the FreeCAD patch stack harder to maintain.
- Rust should own provider processes and protocol normalization, session/event
  state, Turso persistence, durable activity records, and non-GUI background
  work.
- C++/Qt should own FreeCAD registration, QObject/QML integration, docking,
  GUI-thread scheduling, and narrow bridges to FreeCAD `App` and `Gui`.
- Python remains the model-facing FreeCAD API. Do not create a large Rust
  binding layer where a direct FreeCAD Python call is clearer.
- Keep the Rust/native boundary narrow and stable.
- Use embedded [Turso](https://github.com/tursodatabase/turso) for conversation
  and session state. Keep Anthracite identity and session associations outside
  `.FCStd` by default. If document metadata is ever necessary, use only normal
  upstream-supported FreeCAD extension or property mechanisms and require
  verified open/save round-trip compatibility with unmodified FreeCAD.

## Reference repositories

- [vcad](https://github.com/ecto/vcad): modern, ground-up agentic CAD. Learn from
  its visual inspection feedback: model images from multiple viewpoints alongside
  structured observations. Use FreeCAD's viewport and APIs, not its replacement kernel.
- [Autolith](https://github.com/lambda-symbolics/autolith): inspectable live state,
  XDG storage, explicit runtime provenance, and a separation between packaged code
  and local changes. Apply those principles to FreeCAD's native runtime; Python
  actions remain checked calls into real CAD APIs, not a replacement CAD language.
- [FreeCAD](https://github.com/FreeCAD/FreeCAD): upstream application, source
  conventions, module system, Python APIs, transactions, commands, Qt/QML
  integration, and build/test patterns. Follow native FreeCAD patterns before
  inventing parallel abstractions.
- [Helium](https://github.com/imputnet/helium): copy the pinned-upstream,
  disposable-source, ordered-Quilt-series workflow. Do not copy browser-specific
  packaging or its separate platform-repository layering.
- [T3 Code](https://github.com/pingdotgg/t3code): copy the provider-driver model
  for existing agent installations and the interaction design: threads,
  streaming timeline, compact expandable activity, bottom composer, model and
  effort controls, approvals, plans, requested input, and persistent drafts.
  Translate those ideas into native QML; do not copy its React/WebSocket stack,
  project/worktree concepts, browser preview, or monolithic chat components.
- [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent): copy the narrow
  agent loop and small, powerful tool surface. Its broad shell action maps to
  Anthracite's broad FreeCAD Python action; its command observation maps to a
  transaction/diff/recompute/diagnostic/render observation. Preserve bounded
  execution and serializable trajectories.
## Initial implementation target

The first vertical slice is:

```text
prompt in a dockable QML sidebar
  → existing Codex or OpenCode installation
  → one freeform FreeCAD Python tool call
  → GUI-thread transaction and recompute
  → structured CAD change observation
  → streamed result in the sidebar
```

Keep work focused on proving this path before expanding the tool surface,
workbench coverage, or secondary UI.
