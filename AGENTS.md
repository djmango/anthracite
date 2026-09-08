# AGENTS.md

README is the user-facing build/run guide. This file records durable intent and contributor
rules; code and tests define API details. `freecad_commit.txt` pins upstream and
`patches/series` alone defines patch order. Avoid duplicate feature inventories and decision logs.

## Intent and boundaries

- FreeCAD is the CAD system; the model operates it through one checked
  `freecad(<ordinary Python>)` tool. Prefer document/workbench APIs, then registered GUI
  commands, then thin helpers—not a replacement kernel, CAD DSL, per-operation tool catalog,
  direct `.FCStd` XML editing, or screen-coordinate automation.
- Preserve editable native feature trees. Successful recompute or a valid solid is not design
  correctness: follow user intent, expose missing requirements, and support claims with explicit
  checks. Keep observations readable and paged: dependencies, parameters, constraints, diagnostics,
  and viewport images. Images are feedback, not proof of exact geometry or topology.
- Mutating calls run on the GUI thread inside named transactions, recompute and validate, then
  commit or roll back. Python compilation/execution is not static typechecking; transactions do
  not undo arbitrary Python side effects. Report failed or incomplete rollback honestly.
- Documents persist; Python locals do not. Internal object names and revision-bound topology
  references matter. Reject stale references and report ambiguity/remapping; never guess a new
  face or edge after an edit, undo, or document replacement.
- Use existing Codex/OpenCode installations, preserving auth, configuration, models, skills, and
  ordinary tools. One normalized provider adapter feeds one executor and UI. Do not build a new
  general-purpose harness, add simultaneous project/worktree sessions, or add Claude Code yet.
  One provider operates on the active FreeCAD document context at a time.
- QML owns presentation and interaction. Chat is fixed to the right, resizable, showable/hideable,
  and restorable; never floating. Native FreeCAD editing and the viewport remain first class.
  Keep the thread lean: final answer under expandable timed work, model-bound images visible,
  selectable text, inline CAD references, no redundant branding or Copy buttons.
- Acknowledge inputs immediately (target ~100 ms); preserve focus, drafts, reading position, and
  spatial continuity. Motion must be interruptible and respect reduced motion. Never imply CAD
  success before validation. Show honest progress and actionable errors; tests alone do not prove
  the UI feels smooth. Settings changed during a run apply to the next run.
- Use `#080808` backgrounds and `#A06666` accents with Qt palettes/native styling. Keep existing
  FreeCAD icons; new Anthracite controls use bundled Iconoir icons, not runtime downloads.

## Technology choices

- Rust owns providers, protocols, processes, persistence, and conversation/run state, including
  grouping and replay. Use it where self-contained and maintainable, not to wrap all FreeCAD APIs.
  Python remains the model-facing CAD API. Keep C++/Qt bridges thin: registration, docking,
  GUI-thread scheduling, and narrow native integration. Do not add bindings just to replace
  working glue or build a parallel C++ application.
- SQLite via `rusqlite`: bundled engine, cached statements, WAL, `synchronous=FULL`, one connection
  owned by the Rust runtime off the GUI thread. No pool or database async runtime is needed.
  Persist operation intent before authorizing execution. Database and FreeCAD commits are separate:
  uncertain outcomes require inspection, never automatic replay or a success claim. A timeout does
  not mean an edit failed or rolled back; do not retry while native execution may still be running.
- Keep session identity outside `.FCStd` for upstream compatibility. Any future in-document
  metadata must use upstream-supported mechanisms and pass unmodified FreeCAD round-trip tests.
- Mutable preferences, sessions, and identifiable/reloadable UI overrides live under XDG paths
  (see README). Changing a dock or QML must not require a full rebuild. SQLite is authoritative;
  the JSONL event projection is for inspection, not recovery.
- Linux: Nix owns native dependencies and tooling. macOS: Nix supplies tools, Rust, and Pixi;
  upstream's pinned `pixi.toml`/`pixi.lock` and CMake preset supply native dependencies. Use the
  locked environment, not host/Homebrew CAD libraries. Keep dependency provenance explicit.

## Patch workflow

The product is the pin plus ordered patches, not the Git history of ignored `build/src`.
FreeCAD is neither vendored nor a submodule. Never commit there or leave implementation only there.
Keep product code in `src/Mod/Anthracite`; patch core only for a materially cleaner narrow hook.

Run commands from the repository root; use Nushell scripts, not Bash.
New source uses `LGPL-2.1-or-later` SPDX and FreeCAD license-header conventions.

`nix develop` (or direnv) supplies tools. `just setup` is read-only; `just setup --fix` prepares
missing source/submodules and applies patches, without overwriting dirty or mismatched checkouts.
`just build` configures automatically and builds incrementally; `just run` never builds.

Before editing, run `just status` and find the file's owner:
`rg -l '^\+\+\+ b/src/path/to/file$' patches/`. Source Git diffs include the entire applied stack,
not just your work. Patches describe features/divergences, not change history; amend the owner.

```sh
just patch-edit sidebar       # select owner; later patches temporarily unapply
just patch-add path/in/freecad # BEFORE editing a file not already owned
# Edit build/src/path/in/freecad.
just patch-diff               # inspect the whole owning patch
just patch-refresh            # persist source edits in the tracked patch
just patches-apply            # restore the full stack
just validate
just build
just test
```

- Use `patch-new feature-name` only for a new concern; names are semantic and unnumbered.
  Keep one owner per file where practical. Register nonexistent paths before creating new files.
- Use wrappers, not bare Quilt: `quilt-env.nu` fixes patch paths and refresh formatting.
  Do not normally edit generated hunks. Never hand-edit/delete `.pc/`, force push/pop with `-f`,
  or discard rejects/backups to bypass conflicts. Preserve and inspect blocked work.
- `patches-apply`/`patches-unapply` move the whole stack; `patch-apply-next`/`patch-unapply-last`
  move one patch, not series order. Refresh dirty work before moving the stack.
- Inspect the outer `jj diff` after refresh for unrelated changes. Never reset, replace, or delete
  dirty source. Pin bumps require preserving work, unapplying patches, deliberately replacing the
  base, repairing the series, updating `nix/package.nix`'s source hash, reviewing upstream locks,
  then building and testing.

## Verification and Rust conventions

- `just validate` applies the series to an isolated clean checkout; `validate-series` only checks
  names/files/order-list integrity. Neither replaces build or tests.
- `just test` runs `tests/runtests.nu`: Rust via cargo-nextest, then isolated FreeCAD GUI,
  executor, and provider-bridge tests without real model calls. Logs: `build/test-results/`.
  Runtime/process tests belong in Rust; embedded FreeCAD assertions remain Python; Nushell owns
  orchestration and workflow tests. Documentation-only edits need link/diff checks, not a rebuild.
- Test follow-up parameter edits, native undo/redo, intervening user edits, stale references,
  reported topology remapping, and uncertain execution—not just final-solid validity. UI checks
  should cover focus, scroll stability, input acknowledgement, interruption, and reduced motion.
- Prefer `cargo clippy` over `cargo check` for Rust checks; use cargo-nextest for tests.
  Follow existing formatting and naming; use clear, proportionate identifiers without unnecessary
  abbreviations or verbosity. Use `let ... else` when it clarifies early exits. Imports and macro
  names should improve readability; avoid blanket style churn and speculative annotations.
- Handle expected runtime failures with `Result`, not panics. Reserve `.expect()` for genuine
  structural invariants and explain why failure is impossible. Never use it for fallible external
  state such as I/O, channels, or user input. `.unwrap()` is fine in tests/fuzz harnesses, not
  production. No mandatory keywords or mechanical string extraction rules for error messages.

## References: what to learn

- [FreeCAD](https://github.com/FreeCAD/FreeCAD)
- [Helium](https://github.com/imputnet/helium): a good refernece for using quilt to create a patch based fork
- [T3 Code](https://github.com/pingdotgg/t3code): existing-provider drivers and thread UX—streaming,
  compact work summaries, images, drafts, approvals, and settings. Translate into QML, not React,
  WebSockets, browser previews, project registries, or worktrees.
- [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent): narrow compositional action loop
  with bounded execution and useful, serializable observations; our action language is FreeCAD Python.
- [Blender MCP](https://github.com/ahujasid/blender-mcp): scene/object inspection, viewport feedback,
  and Python into the real app; retain our checked execution, rollback, and topology safeguards.
- [FreeCAD MCP](https://github.com/neka-nat/freecad-mcp): native integration and model inspection;
  adapt into the existing tool, not a parallel executor or per-operation tool catalog.
- [vcad](https://github.com/ecto/vcad): modern ground-up agentic CAD's multi-view visual feedback;
  use FreeCAD's viewport/kernel, not its replacement CAD runtime.
- [Autolith](https://github.com/lambda-symbolics/autolith): inspectable live state, XDG paths,
  explicit provenance, and packaged code separate from reloadable local changes.
