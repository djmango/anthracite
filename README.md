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
- paste images with Cmd-V/Ctrl-V or use the composer’s attach button; previews are removable
  and remain visible in sent messages and replayed history
- an eyedropper-style CAD picker adds readable object/face/edge/vertex references to your draft
- existing coding-agent installations instead of a new agent harness
- streaming chat and CAD activity with approvals, requested input, plans and durable replay
- completed runs show only the final answer beneath an expandable “Worked for Xm Ys”
  summary; expand it for intermediate updates, tool calls/results, and the exact model-bound
  images. Click an image to enlarge it. These observations persist with conversation history.
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
- embedded SQLite persistence for external document identities, normalized event history and
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

Use the composer’s **+** button to attach images or files, or paste an image from the clipboard.
Images are sent as native Codex/OpenCode image inputs, not text descriptions. The sidebar previews
the exact normalized PNG sent to the agent. Other files are snapshotted under the XDG state
directory and passed as named local paths for the agent’s existing file tools; attaching a CAD
file does not automatically import it. Preparation runs off the GUI thread. Limits: eight
attachments, 8 MiB per selected file, images scaled to fit 2048×2048, 24 MiB combined encoded images.
Attachments persist with each thread’s draft. File snapshots remain until explicitly removed.

Click the **eyedropper**, then click a face, edge, vertex, or object in the viewport. FreeCAD’s
native selection resolves the hit; the composer shows its label, internal name and subelement as
one inline token, not a second attachment card. One Backspace (or deleting a selection containing
it) removes the whole token and its model reference; native editor undo restores both.
Escape or right-click cancels. The agent receives an exact revision-bound reference, geometry
summary and picked point in mm. Stale references block sending until removed and picked again;
the executor also rejects them if geometry changes later. Unsupported selections are reported,
never guessed. Scroll up or expand a work summary to pause auto-scroll; **↓ Latest** resumes it.

New turns leave room for the answer beneath your prompt. Reading older messages, expanding
activity, and resizing the dock preserve your reading position. You can draft the next message
while the agent works; Send waits for the current run to finish (no automatic queue or replay).
One composer button opens agent, model and reasoning settings, each with its own selection sheet.
The picker remains usable during a run: model/effort changes apply to the next submitted turn,
and a harness change connects after the current run finishes. An unconnected harness's model
catalog becomes available when it connects; the running harness's models are never substituted.
Message text is selectable and supports normal keyboard copying, without per-response Copy buttons.

The interaction standard is low acknowledgement latency and continuous, understandable state:

- Acknowledge input immediately, targeting visible feedback within 100 ms. Show pressed,
  selected, queued, or pending state without waiting for the provider; never imply CAD success
  before validation confirms it.
- Preserve reading position, focus, drafts, and spatial context. Transitions explain what changed;
  do not hide state changes behind animation or make content teleport.
- Discrete choices land crisply. Continuous motion uses short easing or restrained springs and
  yields immediately to a new gesture. Respect reduced motion; feedback must not depend on motion,
  sound, or haptics.
- Keep gestures consistent. Show honest progress, distinguish waiting from failure, and make
  errors explain a recovery action. Prefer feedback at the affected control over extra chat rows.
- Test acknowledgement, interruption, focus, scroll anchors, and reduced-motion behavior under
  streaming load. Track latency distributions and frame gaps separately from functional tests;
  passing tests alone does not establish that the sidebar feels good. The 100 ms target is an
  acceptance goal, not a measured guarantee of the current implementation.

Send/Sending/Stop share one fixed-size control. History and activity requests acknowledge loading
and suppress duplicate clicks. Explicit Latest navigation and activity expansion use short,
interruptible easing; settings and image overlays fade without delaying selection state.
On macOS, motion follows the native accessibility preference; elsewhere it follows the Qt style's
animation hint. `ReduceMotion=true` under `BaseApp/Preferences/Mod/Anthracite` disables Anthracite
motion on either platform. It is re-read when opening overlays, navigating Latest, and returning
to the application. Tests write rendered-frame acknowledgement samples to
`build/test-results/interaction-latency.json`; these are not display-scanout measurements or a
guarantee during blocking native CAD execution.

Long prompts and individual work entries expand on demand. History arrives in 60-message pages,
with work details in 20-entry pages and bounded render thumbnails. Paging changes only the chat
view, never the CAD document or its undo history. Rust still reconstructs the conversation from
stored events; this bounds UI transport/rendering, not database replay memory.

Inside that tool, `cad.render_views()` attaches axonometric, front, right, and top
PNG views for visual inspection. Pass a list such as `cad.render_views(["front", "rear"])`
to choose up to six views. `cad.render(view="current")` captures just one.
Geometry edits without an explicit render request automatically attach a compact overview and,
when there is one unambiguous visible result, a focused view. Failed optional capture is reported
separately and does not roll back a committed edit. Explicit render requests retain their normal
transactional failure behavior.

For intermediate edits, `cad.feedback(images=False)` skips automatic images for that call only.
Explicit renders and all validation still run; the observation records the skipped feedback.
Inspect the final result with `cad.review('Name')` or `cad.render_views()`.

CAD execution waits while a mouse button, popup, or modal dialog is active, then rechecks the
document revision. Native validity, incomplete post-recompute features, and native status messages
are checked without treating legitimate shapeless containers or empty sketches as broken solids.
Rust records operation IDs and execution stages independently of the GUI. After 60 seconds pending,
it records a warning, not a failure: native work may still be running. Further CAD calls are rejected
until the actual result arrives; a timeout neither rolls back nor retries an edit. A frozen GUI
cannot display updates until it resumes; recorded health events remain in the XDG event history.

`cad.explain(reference)` connects an exact pick to its native Body, Tip, profile, parameters,
expressions and upstream/downstream dependencies. `cad.review(reference)` also attaches focused
images, or a local-XY diagram for a sketch; an internal object name works too. Dependencies are
not proof of which sketch edge generated a face. Ambiguous design intent still needs clarification.
`cad.frame("Name")` describes local/world placement, origin, axes and native conversion examples.
Measurements, topology and picker points use world mm; sketch geometry uses local XY.
Every call reports `interveningChanges` since the previous call in this application session,
including native undo/redo and edits outside the executor, without guessing who made them.

`cad.api("Name", kind="methods", query="setDatum")` returns bounded native method documentation.
`kind="workbenches"` lists registered workbenches without activating them; `kind="modules"` lists
loaded common CAD modules. Explicit `cad.verify` checks can test `bodyTip`, `sketchDegreesOfFreedom`,
and `nativeFeatureHistory`; the latter only establishes a Body with a native parametric Tip and
a sketch, not complete editability or design correctness.

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
removed; session/event records remain in SQLite.

Visual inspection also supports `focus="Name"`, `highlight=["Name"]`, and
`section=("z", 5)` on viewport renders. Sections clip to the positive half-space
(here z >= 5 mm); they do not create a capped solid or change the model.
`cad.render_sketch("BaseSketch")` draws native sketch geometry and constraint labels
in local XY, including geometry indices and a paged constraint legend.
`cad.render_views(compare=True)` captures before/after images around the current edit;
use one such request as the final top-level statement, with literal arguments referring
to objects that exist before the edit.
Camera and temporary render styling are restored afterward.

Add `labels=True`, `axes=True`, and `dimensions=True` to viewport renders for
object-name callouts, orientation, and world-axis bounding dimensions in mm.
`highlight_changed=True` highlights geometry from the current edit or the last
recorded edit at the same revision. User edits invalidate that remembered set.
Labels carry native names and document revisions in `observation.renders`;
their projected centers are not pixel-selection targets or proof of visibility.

`cad.topology('Name', kind='faces', surface='Cylinder', offset=0, limit=25)`
returns paged native geometry candidates (`kind='edges'` queries curves).
Omit `surface` to see every geometry type. Each candidate has an explicit
document/object/subelement/revision reference with a document-lifetime token.
Pass the complete returned reference to
`cad.resolve_ref(reference)` inside Python, `cad.measure(reference)`, or a render's
`references=[reference]` for a callout. References expire on **any** document
revision change; finish an edit and inspect again rather than guessing a new index.

`cad.measure('Name')` reports native BRep size, volume, area and center of mass.
`cad.measure('A', 'B')` reports minimum distance and, for solids, common volume.
Results identify units, native provenance and shape tolerance. Zero distance
alone does not prove overlap; unavailable non-solid overlap is reported as null.

`cad.verify([{'object': 'BasePad', 'metric': 'size_mm',
'expected': [20, 20, 18], 'tolerance': 0.01}])` checks caller-declared expectations.
Numeric claims require an explicit tolerance in the metric's units. `type` and
`fullyConstrained` check native feature identity and sketch constraints separately.
Each result reports expected/measured values and pass/fail/unverifiable; an empty
or unsupported claim never passes. Standalone checks are read-only. Checks within
an edit run after final recompute and appear under `verification`; a failed design
check does not automatically undo an otherwise valid edit. Inspect and use guarded
undo when appropriate. `ok` means execution succeeded, not that all design checks passed.

Edit receipts distinguish changes observed before the executor's final recompute
from geometry changed by that recompute; they do not claim every early write was a
direct Python assignment. Errors include `nextActions` for inspection/recovery.

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

- QML owns the UI, with native docking, restoration and theming.
- Rust owns providers, protocols, process control, persistence and conversation/run state.
  One reducer produces the live and replayed timeline, including grouping and timing.
- A thin Qt bridge exposes Rust state/actions to QML. C++ is limited to FreeCAD registration,
  docking/restoration hooks, GUI-thread scheduling and native integration—not application logic.
- Python remains the model-facing FreeCAD action language.
- SQLite through [rusqlite](https://github.com/rusqlite/rusqlite) stores conversation events, provider
  thread state and document/session associations outside `.FCStd`. Any future in-document metadata
  must use upstream-supported FreeCAD mechanisms and round-trip safely through unmodified FreeCAD.
- The SQLite engine is bundled and pinned by Cargo, not supplied by the host. One Rust-owned
  connection uses cached statements, WAL, explicit transactions and `synchronous=FULL` for durable
  operation records. No database async runtime or connection pool is needed.
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
- `$XDG_STATE_HOME/anthracite`: `anthracite.sqlite3` and a readable `anthracite.events.jsonl` projection
- `$XDG_CACHE_HOME/anthracite`: disposable FreeCAD temporary data

SQLite is authoritative for sessions; the JSONL projection is for live inspection and is not a
recovery log. The SQLite store starts fresh; older databases are not imported and remain untouched.
Existing `build/profile` is also left untouched. Bundled preferences
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
