<h1 align="center">anthracite</h1>

<p align="center">
  an llm-native freecad fork where existing coding agents can work through freecad's real
  python api.
</p>

<details open>
<summary><strong>overview</strong></summary>

Anthracite makes FreeCAD's existing CAD implementation usable through a checked Python executor.
The kernel, PartDesign features, topology handling, recompute, constraints and assemblies remain
FreeCAD's responsibility. Model output is fallible code completion; the chat sidebar carries
requests and observations.

- a native, dockable QML sidebar alongside the 3D viewport
- existing coding-agent installations instead of a new agent harness
- streaming chat and CAD activity with approvals, requested input, plans and durable replay
- transactional, undoable changes with recompute, validation and structured diagnostics

FreeCAD's normal selection, commands, properties, task panels and viewport remain first class.
The document and its native objects are the inspectable state. Generated Python is a proposed
action, not a declarative or provably correct CAD transform.

</details>

<details open>
<summary><strong>status</strong></summary>

The working vertical slice is implemented end to end:

- a persistent native FreeCAD dock with a QML chat timeline and composer
- a transactional `freecad` Python executor with rollback, recompute, validation, structured
  change observations and external-edit revision checks
- a Rust process bridge for the existing Codex `app-server`, including streaming, interruption
  and dynamic tool calls
- a provider-neutral, line-delimited interaction protocol for approvals, requested input, plans,
  usage, activity and robust interleaved streaming
- embedded Turso persistence for external document identities, normalized event history and
  resuming the same Codex thread across FreeCAD sessions
- document-scoped conversation creation and navigation with per-thread persistent drafts
- safe session switching when the active FreeCAD document changes, including Save and Save As
- live Codex model/effort controls, per-thread selection persistence and compact expandable
  activity rows
- bounded viewport renders attached to the same transactional `freecad` tool observation for
  visual model verification
- a normalized context-window usage meter in the composer
- structured active-workbench and selected object/face/edge context, including geometry summaries
  for momentary topology references
- live Codex and OpenCode adapters, a native provider switcher and a local MCP bridge that gives
  OpenCode the same transactional `freecad` tool

Codex and OpenCode use the user's existing installations, authentication, configuration, models,
skills and normal tools. Anthracite starts their native server modes, normalizes their events and
adds only its FreeCAD tool. It does not add T3 Code's project registry, worktrees or simultaneous
project sessions: one provider operates on the one active FreeCAD document context. Claude Code is
deliberately not near-term work.

</details>

<details open>
<summary><strong>agent interface</strong></summary>

Anthracite adds one CAD-specific tool to the selected agent:

```text
freecad(<ordinary Python source>)
```

Inside that tool, `cad.render_views()` attaches axonometric, front, right, and top
PNG views for visual inspection. Pass a list such as `cad.render_views(["front", "rear"])`
to choose up to six views. `cad.render(view="current")` captures just one.
Images describe the final recomputed model, with ordered view metadata; rendering
restores the user's camera and bounds the combined pixel count and image payload.
Use images alongside object/geometry checks, never as proof of exact topology.

The model can inspect an editable feature tree with `cad.tree()` (or scope it to
`cad.tree("Body")`), readable properties with `cad.inspect("BasePad")`, and native
constraint indices, names and solver status with `cad.sketch("BaseSketch")`.
`cad.api(query="PartDesign")` discovers installed types; `cad.api("BasePad")`
returns property documentation and enum choices. Follow `nextOffset` for paged results.
`cad.guide()` lists on-demand native examples, and `cad.diagnostics()` reports
advisory editability warnings, not inferred design requirements.

Start a logical edit with `cad.action("Resize mounting holes")`. Results include
parameter changes, the feature tree, and guarded native undo/redo availability.
Call `cad.history()`, then use its returned values in a **standalone**
`cad.undo(action="id", revision=N)` or `cad.redo(action="id", revision=N)`.
History is limited to the last 20 tracked actions in the open document session;
intervening user edits, a changed native history stack, or an open transaction block recovery.
Read-only helper calls with literal arguments do not create undo entries or advance revisions.

Recovery checks native geometry and persisted parameters. Recompute may regenerate
FreeCAD's topology naming tables even when BREP geometry is identical; these changes
are reported in `topologyMappingsChanged` with `requiresInspection: true` and a new
revision. No old face/edge reference is silently rebound.

For recovery across restarts, standalone `cad.checkpoint("Before redesign")` saves
a normal `.FCStd` copy plus integrity/provenance metadata under
`$XDG_STATE_HOME/anthracite/checkpoints`. `cad.checkpoints()` lists them;
`cad.restore_checkpoint(checkpoint="id", revision=N)` opens a separate recovered
copy and preserves the original document. Checkpoints are retained until explicitly
removed; session/event records remain in Turso.

Visual inspection also supports `focus="Name"`, `highlight=["Name"]`, and
`section=("z", 5)` on viewport renders. Sections clip to the positive half-space
(here z >= 5 mm); they do not create a capped solid or change the model.
`cad.render_sketch("BaseSketch")` draws native sketch geometry and constraint labels
in local XY, including geometry indices and a paged constraint legend.
`cad.render_views(compare=True)` captures before/after images around the current edit;
use one such request as the final top-level statement, with literal arguments referring
to objects that exist before the edit.
Camera and temporary render styling are restored afterward.

The model writes normal FreeCAD Python using `App`, `Gui`, workbench modules and a thin `cad`
helper. Each call runs on the GUI thread inside a named transaction, recomputes and validates the
document, then commits or rolls back and returns the result, CAD changes and diagnostics.

Treat the agent as an operator of a checked Python executor. The user supplies design intent
and constraints; the model must not silently invent missing design requirements. Success is
established by executor observations and explicit checks, not the model's description. A valid
shape or successful recompute alone does not establish that a design meets its requirements.
Python is parsed and compiled, then checked through execution and FreeCAD validation; this is
not static typechecking. Transactions cover document changes, not arbitrary Python side effects.
If rollback fails or the observed state is not restored, the result reports that uncertainty
and advances the revision. Internal object names are stable identifiers; face/edge indices are
revision-specific references and must be inspected again after topology changes.

The document persists between calls while Python locals do not. Document revisions prevent stale
writes. Stable internal object names are reported alongside labels and shape summaries.

Use document/workbench APIs first, registered GUI commands second and thin helpers only for missing
ergonomics. Anthracite does not re-express FreeCAD as hundreds of JSON tools, invent a CAD language,
edit `.FCStd` XML directly or rely on screen coordinates.

</details>

<details open>
<summary><strong>upstream</strong></summary>

Anthracite is an independent soft fork of [FreeCAD](https://github.com/FreeCAD/FreeCAD), pinned to
commit `145529fe741292ff0b3977a01195bf0247425794`.

FreeCAD is materialized in ignored `build/src`; it is not vendored or tracked as a submodule.
Anthracite changes are explicit GNU Quilt patches under `patches/`, applied in the order recorded by
`patches/series`.

</details>

<details>
<summary><strong>architecture</strong></summary>

- QML and Qt Quick own the native sidebar experience.
- Rust owns self-contained provider, protocol, session, event, persistence and background work when
  that keeps the FreeCAD patch stack simple.
- C++/Qt owns FreeCAD registration, docking, GUI-thread scheduling and narrow native bridges.
- Python remains the model-facing FreeCAD action language.
- Embedded [Turso](https://github.com/tursodatabase/turso) stores conversation events, provider
  thread state and document/session associations outside `.FCStd`. Any future in-document metadata
  must use upstream-supported FreeCAD mechanisms and round-trip safely through unmodified FreeCAD.
- CAD calls also have durable `operations` records: exact Python, document/thread/tool identity,
  prepared revision, status, and executor results (changes, validation and errors). FreeCAD sends
  read-only context; Rust persists the running state before authorizing execution. Revisions are
  live-document counters, not cross-restart geometry identities.
- Database migrations and related event writes are transactional. FreeCAD's transaction and the
  database commit are separate: an unconfirmed outcome is never treated as success or replayed.
  The runtime exclusively locks its database; on restart, unfinished operations become `unknown`
  and the sidebar warns that inspection is required. `rejected` means execution was refused,
  unlike a confirmed `rolled_back` transaction. The `result_json` column retains diagnostics.

Keep new product code concentrated in `src/Mod/Anthracite`. Patch FreeCAD core only for narrow,
proven integration gaps.

</details>

<details>
<summary><strong>development</strong></summary>

With Nix flakes enabled, run `nix develop`, or run `direnv allow` once for automatic
activation through direnv's `use flake` integration. On Linux, `flake.lock` pins the complete
native dependency set: OCCT, Qt, Python, Coin3D and Rust. The development shell inherits the
same dependencies as the packaged application.

On macOS, Nix supplies workflow tools, Rust and Pixi. FreeCAD's own `pixi.toml` and
`pixi.lock`, included in the pinned upstream source, provide the compiler, Qt, Python and
CAD libraries together. Commands use `pixi run --locked` and FreeCAD's macOS CMake preset.
The environment lives in ignored `build/src/.pixi`; Homebrew CAD libraries are not used.
Dependencies normally come as binary packages; our patched FreeCAD and Rust runtime still
need compiling. Configuration reuses the earlier `build/src/build/debug` build directory.

On Linux, `nix build` builds the pinned FreeCAD commit with every patch in `patches/series`;
`nix run` launches that application. The flake uses nixpkgs' FreeCAD dependencies and vendors
the Rust runtime dependencies from the Cargo lockfile in the patch stack.
`nix build .#patched-source` checks source fetching and ordered patch application independently.
`nix build` / `nix run` package the application on Linux only; macOS uses the development
commands below with FreeCAD's environment. A pin bump also requires updating the source hash in
`nix/package.nix` and reviewing upstream's Pixi lockfile.

- `nix develop` enters the pinned development environment
- `just setup` checks tool/source/patch readiness without changing anything
- `just setup --fix` prepares missing source/submodules and applies remaining patches
- `just patches-apply` / `just patches-unapply` apply/unapply the full stack
- `just patch-apply-next` / `just patch-unapply-last` move one patch
- `just patch-edit sidebar` makes an existing semantic patch current
- `just patch-new feature-name` creates a new semantic patch when no existing patch owns the change
- `just patch-add src/path/to/file` adds a path not already owned by the current patch
- `just patch-refresh` turns source changes into the current patch
- `just validate` applies the full series in an isolated checkout

Patches describe current features and divergences, not their development history. Amend the
existing owning patch whenever possible; patch order belongs only in `patches/series`, so filenames
are never numbered. Keep each source file owned by one patch where practical. Make changes in
`build/src`, then refresh the patch. Do not leave implementation only in the ignored source tree.
FreeCAD version bumps are deliberate: change the pin, repair every patch in order, then build and
test.

With FreeCAD materialized and the patches applied, configure and build the complete application:

```sh
just build
just run
```

The development build lives in `build/src/build/debug` on macOS and `build/native` on Linux.
`just run` launches it without invoking CMake.
`just build` prepares compiler/dependency settings and CMake build files automatically,
then compiles incrementally. There is no separate configure command.
`just test` runs Rust runtime and launcher-signal tests with cargo-nextest, then checks
the executor, workbenches, QML reload and durable bridge using an isolated
profile and a deterministic local provider, without contacting a model service.
Workflow scripts and `tests/runtests.nu` orchestration use Nushell. Rust tests live
with the runtime (the `test-fixtures` feature enables its process-test executable);
assertions executed inside FreeCAD remain Python to use its embedded API directly.
The Nushell launcher uses the Rust runtime's small process supervisor to turn terminal
Ctrl-C into SIGTERM, with a five-second forced-stop fallback; it does not start an agent.
The packaged app and development launcher share `devutils/launch.nu` and these live paths
(with the standard XDG defaults when the variables are unset):

- `$XDG_CONFIG_HOME/anthracite`: FreeCAD preferences, dock layout, optional `qml/Main.qml`
- `$XDG_DATA_HOME/anthracite`: FreeCAD user data
- `$XDG_STATE_HOME/anthracite`: `anthracite.db` and a readable `anthracite.events.jsonl` projection
- `$XDG_CACHE_HOME/anthracite`: disposable FreeCAD temporary data

Turso is authoritative for sessions; the JSONL projection is for live inspection and is not a
recovery log. Existing `build/profile` and legacy databases are left untouched. Bundled preferences
apply only when creating a new profile; updates never replace the user's current dock layout.

To customize the sidebar, place a copy of the bundled `Main.qml` at the config path above and run
`Gui.runCommand("Anthracite_ReloadSidebar")` in FreeCAD's Python console. Reloading keeps the native
controller and provider session. Invalid QML leaves the previous view intact and reports errors.
The sidebar's `anthraciteQmlSource` QObject property identifies the active source. Remove the local
override and reload to return to the packaged UI. C++/Rust changes require rebuilding; ordinary
CAD actions, preferences, and QML iteration do not.

</details>

<details>
<summary><strong>influences</strong></summary>

- [T3 Code](https://github.com/pingdotgg/t3code) — existing-provider integration and primary UI/UX
  inspiration, translated into native QML
- [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent) — one powerful compositional action
  followed by a useful observation
- [Helium](https://github.com/imputnet/helium) — pinned upstream, disposable source and an ordered
  patch series
- [Autolith](https://github.com/lambda-symbolics/autolith) — inspectable live state, XDG paths,
  explicit runtime provenance, and local changes separate from packaged code

</details>

<details>
<summary><strong>vertical slice</strong></summary>

```text
prompt in the dockable QML sidebar
  → existing Codex or OpenCode installation
  → one freeform FreeCAD Python tool call
  → GUI-thread transaction, recompute and validation
  → structured CAD change observation
  → streamed result in the sidebar
```

Both providers adapt to the same runtime event protocol and share one FreeCAD executor and QML
surface.

</details>

<details>
<summary><strong>license</strong></summary>

Anthracite uses the same license as FreeCAD:
[GNU Lesser General Public License v2.1 or later](LICENSE).

</details>
