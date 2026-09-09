# Omarchy Minimize

Status: agreed
Owner: Owen        Last decision: 2026-09-09
Supersedes: —

Contents: [0. TLDR](#0-tldr) · [1. Problem](#1-problem) · [2. Outcome](#2-outcome) · [3. Worked examples](#3-worked-examples) · [4. Invariants](#4-invariants) · [5. Mechanism](#5-mechanism) · [6. Acceptance](#6-acceptance) · [7. Build phases](#7-build-phases) · [8. Decisions](#8-decisions) · [9. Open questions](#9-open-questions) · [10. Out of scope](#10-out-of-scope)

## 0. TLDR
*(author: Owen, confirmed 2026-09-09 — protected: do not rewrite, expand, or paraphrase — human)*

**Outcome:** Build a native Omarchy plugin that hides windows in a special workspace, shows them in a right-edge sidebar with attention state, and restores them safely.

**Rules:**
- New windows go to `special:minimum`; exact aliases `special:minimized` and `special:scratchpad` are listed and individually restorable too.  → AT-3, AT-4, AT-7
- Clicking a row returns a plugin-owned window to its remembered workspace when safe, otherwise it restores here; a secondary action always restores it to the active workspace on the monitor that opened the panel.  → AT-3, AT-7
- “Done working” is represented honestly as “Needs attention” or “Updated”; no universal job-complete claim is made.  → AT-3
- V1 omits window thumbnails and refuses pinned/grouped cases before mutation unless live tests prove them safe.  → AT-3, AT-7
- Product files live under `omarchy-minimize/`; no existing plugin or `/usr/share/omarchy/` file is changed.  → AT-2, AT-8
- Use conflict-checked defaults `SUPER + M` (minimize) and `SUPER + ALT + M` (sidebar); do not rebind stock scratchpad keys.  → AT-1, AT-2
- Help and shortcut setup live inside the sidebar; opening them is read-only, and only an explicit Save or confirmed Remove changes the plugin's marked, conflict-checked binding block.  → AT-1, AT-2, AT-3
- A compositor-only rescue procedure can expose or restore `minimum`, `minimized`, and `scratchpad` windows even if the shell/plugin is unavailable.  → AT-4, AT-7
- Removal instructions restore owned windows and unset dynamic properties before plugin files are removed.  → AT-5
- Credit OmaVeil/NiflVeil as inspiration and explain why live state replaces `/tmp` cache authority.  → AT-3, AT-8

**How we'll know:** The disposable live probe restores the exact supported fixture addresses, refuses pinned and grouped fixtures before mutation, touches no pre-existing window, and cleans every fixture on exit.

**Scenarios:** 9 acceptance rows (§6), 7 worked examples (§3).

Agent notes:
1. Confirmed by Owen on 2026-09-09; its lines were copied from `ROADMAP.md` and `phase-4.md`, not silently paraphrased into product rules.
2. “New windows” in the first rule means newly minimized windows, not newly launched application windows.
3. The shortcut pair is a conflict-checked suggestion. On the inspected machine `Super+M` is already occupied, so the helper correctly makes no edit rather than treating the roadmap's earlier “currently free” assumption as fact.
4. The live probe exercises the same transaction builders against disposable windows; installed-shell UI and service lifecycle behavior remain separately covered by the headless QML harnesses.

## 1. Problem
*(human context extracted from the approved roadmap and ratified with §0 on 2026-09-09)*

Hyprland's stock Omarchy workflow provides a single scratchpad pair, but not a traditional per-window minimize list with exact restore, multi-monitor targeting, and honest attention state. Independent minimizers and the Dock use different special-workspace names and private caches. A shell reload, stale address, key conflict, or premature uninstall can therefore leave a window hidden or let a broad recovery action affect the wrong owner's window.

The stock behavior is concrete: `Super+Alt+S` silently moves the active window to `special:scratchpad`, and `Super+S` toggles that workspace (`/usr/share/omarchy/default/hypr/bindings/tiling.lua:27-28`). It remains useful and must keep working alongside this capability.

## 2. Outcome
*(human outcome detail extracted from the approved roadmap and ratified with §0 on 2026-09-09)*

**After this ships, it is true that:**

- A user can hide one eligible active window without changing the current numbered workspace, then find it in a native right-edge Omarchy sidebar.
- The bar and sidebar share one live list across monitors. Normal restore uses a
  live trusted origin first; explicit restore-here uses the active workspace on
  the monitor that opened the panel.
- Every compositor mutation is scoped to a validated address, PID, stable ID, source, and target; interrupted work resolves or rolls back without guessing.
- Windows from OmaVeil/NiflVeil, Dock, and the stock scratchpad are visible through an exact alias allowlist without importing their private state.
- Optional shortcuts, emergency rescue, and removal remain explicit, reversible, and ownership-aware.

**Why we need it:** Traditional minimize remains useful when a tiled workspace is temporarily crowded, but a convenience that steals focus, targets an address reused by another process, takes a key silently, or strands a hidden window is worse than having no minimizer. This outcome makes the workflow recoverable enough for daily use while preserving stock and external conventions.

The observable product rules live only in §0.

## 3. Worked examples
*(candidate human seed plus agent extensions)*

**Candidate human seed — happy path:** Owen is working on workspace 3 with a terminal and browser. He right-clicks the Minimize bar icon while the browser is active. The exact browser moves to `special:minimum`, workspace 3 stays visible, and one row appears. He later opens the icon from another monitor and presses Enter. The same browser returns to workspace 3 and receives focus.

**Agent extension — trusted origin and restore here:** Ana minimizes an editor from workspace 5, moves to workspace 2, opens the sidebar, and presses Enter. Workspace 5 still exists and the record still matches the same compositor instance, address, PID, and stable ID, so the editor returns to 5. Next time she uses Shift+Enter to deliberately restore it to workspace 2. If 5 had disappeared, a plain restore would report the fallback and restore to her panel's current workspace instead.

**Agent extension — interop without cache authority:** Ben uses the installed Dock and the stock scratchpad. A Dock window in `special:minimized` and a stock window in `special:scratchpad` both appear with distinct source labels beside a NiflVeil/OmaVeil-style window in `special:minimum`. A window in `special:dropterm` does not. Ben restores one exact row; Omarchy Minimize never opens `/tmp/minimize-state/windows.json` or the Dock's private metadata.

**Agent extension — reload/disconnect recovery:** Chen minimizes a terminal and the shell reloads between setting `focus_on_activate=0` and confirmation. On startup, the instance-scoped journal and the live client agree on the terminal's identity and workspace, so the service adopts the completed move. If that address now belongs to a different stable ID, the journal is discarded without sending a command to it. If the original window is still recoverable on its source workspace, its override is cleaned up.

**Agent extension — conflict and undo:** Devi already has `Super+M` bound to mail. She runs `configure-shortcuts add`; it reports that conflict, creates no backup, and leaves both suggested shortcuts absent. On another machine both chords are free, so the helper installs one marked pair, validates Hyprland, and later removes only that block. A synthetic configuration error restores the prior bytes.

**Agent extension — in-sidebar shortcut setup:** Jo opens Help, follows Configure shortcuts, types `mouse:276` for Minimize and `SUPER + ALT + M` for the sidebar, then chooses Save. Merely opening Help, opening Shortcuts, using Reset suggestions, or choosing Refresh changes no config. Save submits both exact drafts once; Remove requires a second confirmation and removes only the plugin-owned marked block.

**Agent extension — permission/removal path:** Maya wants to uninstall. While the service still runs, she waits for a ready, loaded, idle status, restores every entry marked `owned` from the exact accepted aliases, waits for every exact transaction, and verifies none remain. She sees warnings for externally owned Dock/scratchpad entries, removes the optional marked shortcut block, then removes the plugin. If the service is unavailable she stops rather than deleting first, and deliberately chooses either the compositor-only expose or all-alias rescue path.

Agent extension diff from the seed: adds origin fallback, cross-tool adoption, reload and address-reuse recovery, key conflict/rollback, and ownership-aware uninstall.

Why — what breaks without it: The single happy path would hide the lifecycle, interoperability, and removal edges most capable of losing a window or changing unrelated state.

## 4. Invariants
*(agent derives, human confirms)*

1. **A transaction must never target an address alone.** It must revalidate canonical address, PID, stable ID, mapping, and expected workspace inside the same Hyprland Lua request. Enforced by `CompositorTransaction.js:18-32,109-137,140-219` and the live probe identity guard at `scripts/live-smoke:171-227`; AT-7. **Boundary:** a client may close itself during the guarded request; the service reports disappearance and reconciles rather than recreating it.
2. **Live compatible workspace membership must remain the list authority.** Only `special:minimum`, `special:minimized`, and `special:scratchpad` qualify; stale records drop and other `special:*` names stay excluded. Enforced by `MinimizeModel.js:6-10,48-54,290-323` and `Service.qml:393-579`; AT-3/AT-4/AT-7. **Boundary:** the plugin cannot repair another tool's private cache after a user restores its live window here.
3. **An owned window must not be allowed to reveal itself by activation while hidden.** Set `focus_on_activate=0` before moving to `special:minimum`; after a successful restore move, focus first and unset last. Reload recovery reasserts the override only after proving the exact identity is still in one accepted hidden alias. Enforced by `CompositorTransaction.js:140-219` and `Service.qml:393-484,629-654`; AT-7. **Boundary:** external adopted entries are not assumed to carry this plugin's override, so ordinary restore does not clear property ownership it cannot prove.
4. **No compositor mutation may start without a durable pending journal.** Initial actions and every consequential stage are written before the next command, and service actions stay disabled while state is loading. Enforced by `Service.qml:283-335,393-484,615-669,1091-1187`; QML service smoke. **Boundary:** if `$XDG_RUNTIME_DIR` or atomic writing is unavailable, the action fails closed; the plugin does not promise persistence across compositor sessions.
5. **Failure recovery must not silently turn uncertainty into success.** Timeouts resolve from live membership, rollback keeps the same identity guard, and failed cleanup remains journaled and visible. Owned records moved externally remain in a private durable ledger until exact-workspace cleanup succeeds. Enforced by `Service.qml:486-583,701-1088` and `CompositorTransaction.js:198-266`; QML service smoke. **Boundary:** a compositor that cannot confirm either source or target can require manual rescue.
6. **Optional shortcut setup must never overwrite an occupied chord or unrelated config byte.** The suggested pair remains fill-only, while each action can instead record or accept a validated keyboard chord or numeric Hyprland mouse button. Opening Help/Shortcuts, recording, Reset suggestions, and live availability checks are read-only; only Save or a second confirmed Remove requests a mutation. Save stays gated on a matching free-pair preview, while apply/add/update repeat the check atomically under one helper lock, reject an internal collision, check one active binding snapshot, back up and validate every mutation, and fail closed on malformed ownership markers. Enforced by `ShortcutSettingsView.qml`, `Service.qml`, `bin/configure-shortcuts`, and shortcut/QML tests; AT-1/AT-2/AT-3. **Boundary:** conflicts are detected from the active binding snapshot Hyprland reports; physical `code:N` triggers, device buttons Qt does not expose, and opaque bindings that Hyprland itself omits require manual review.
7. **Uninstall must never knowingly strand a plugin-owned minimized window.** A service-side removal drain atomically rejects new minimizes before ownership inspection. All owned addresses still live in an accepted alias are then restored and verified before shortcut or plugin files are removed, and the final gate requires both the drain and an empty unresolved-owned cleanup ledger; external alias entries are warned and left to their owner. Enforced procedurally by `Service.qml:1104-1137`, the README Remove section, and `tests/acceptance/run:152-250`; AT-5. **Boundary:** the emergency all-alias rescue is intentionally broader and requires explicit user choice.
   The compositor-session journal preserves this drain across a shell reload. Acquisition is exclusive, and the README trap cancels only after its own script acquires the gate, so a competing removal attempt cannot reopen minimizing; covered by `Service.qml:1110-1160` and `tests/acceptance/run:241-257`.
8. **Attention labels must never claim application completion.** Urgency maps to “Needs attention”; a post-baseline title change maps to “Updated”; neither maps to “done.” Enforced by `MinimizeModel.js:236-249`, `WindowRow.qml:22-33`, and README wording checks in AT-3. **Boundary:** application-controlled urgency and title strings can be misleading; the plugin promises only faithful signal provenance.
9. **Window-controlled text must remain display data.** Titles/classes use `Text.PlainText`; generated Lua accepts only bounded validated identities and workspace selectors. Enforced by `WindowRow.qml:24-57,128-200`, `CompositorTransaction.js:18-69,109-137`, and QML/model smoke tests. **Boundary:** valid application text may still be visually confusing, so it is elided and never a command selector.
10. **Rows and idle service state must not poll the compositor per window.** One bounded debounce edge refreshes and reconciles an event burst; elapsed labels use a panel timer only while open. Enforced by `Service.qml:585-611,1300-1315`, `Panel.qml:320-325`, the 1,000-event service fixture, and the 100-row QML fixture. **Boundary:** opening the panel and Hyprland events intentionally request reconciliation.
11. **The plugin must remain an independent user plugin.** It has no install hook, edits no `/usr/share/omarchy` file, and ships no OmaVeil/NiflVeil binary, source, or cache dependency. Enforced structurally by `manifest.json:1-55`, the product-source/package scan in `tests/acceptance/run:260-279`, and AT-8. **Boundary:** interoperability relies on public live workspace names, and documentation may link to the projects credited as inspiration.

Why — what breaks without it: Removing any one of these constraints permits wrong-window mutation, focus theft, cache-stale rows, silent key takeover, false status claims, or hidden windows left behind after removal.

## 5. Mechanism
*(agent)*

### 5.1 Evidence baseline and implementation state

Evidence was refreshed on 2026-09-09 against Omarchy `4.0.2-1`, Hyprland `0.56.2-1` (`efb50993780079460b0cbed1363e2166a2de1d9f`), Quickshell `0.3.1-1`, and the v0.4.1 workspace. The initial public release snapshot is commit `308aa06`; the following SHA-256 pin keeps every reviewed runtime and test file independently auditable:

| File | SHA-256 prefix |
|---|---|
| `manifest.json` | `12995d2ba64c` |
| `package.json` | `40dfd310a979` |
| `AGENTS.md` | `0995b8424f90` |
| `README.md` | `46ef1b7e6be3` |
| `MinimizeModel.js` | `ec0848714a3e` |
| `CompositorTransaction.js` | `84816d49dd4c` |
| `Service.qml` | `6416277b65e5` |
| `Panel.qml` | `6629d3b9d93e` |
| `HelpView.qml` | `b5930b5144f4` |
| `ShortcutSettingsView.qml` | `159faefac85f` |
| `WindowRow.qml` | `c4355461ef59` |
| `bin/configure-shortcuts` | `ab169ec5667a` |
| `scripts/live-smoke` | `4201ea0ae08d` |
| `tests/live-smoke/transaction-step.cjs` | `89c2545c406a` |
| `tests/acceptance/run` | `f1a202eaa3ac` |
| `tests/QmlServiceHarness.qml` | `e9a15eb8683e` |
| `tests/QmlSmokeHarness.qml` | `d636097ae16e` |
| `tests/QmlNativeLoadHarness.qml` | `ad71aa41dc89` |
| `tests/qml-service-smoke.sh` | `bd8ed58eb6ea` |
| `tests/qml-smoke.sh` | `0ebb8a959cf8` |
| `tests/shortcuts/configure-shortcuts.test.sh` | `2b63e04e03a7` |
| `/usr/share/omarchy/default/hypr/bindings/tiling.lua` | `85aac24c8a44` |
| `/usr/share/omarchy/shell/services/PluginRegistry.qml` | `63371e4224f9` |

AT-9 verifies every repository-local row in this table. The dated `/usr/share`
rows record the inspected Omarchy installation as historical evidence; they are
not release gates across compatible system upgrades.

The implementation is complete, installed, and published while this outcome document remains `agreed`; that status records the human intent confirmed on 2026-09-09, while tests remain the authority for which behavior is green.

Why: Without an explicit package/hash baseline, a later shell API or concurrent working-tree change could be mistaken for the implementation reviewed here.

### 5.2 Native plugin boundary

`manifest.json:1-55` declares schema 1, stable id `osouthgate.minimize`, one session-wide `service`, one `bar-widget`, no install hook, no downloaded dependency, and a right-section singleton bar entry. Omarchy's installed registry accepts only relative non-traversing entry points (`/usr/share/omarchy/shell/services/PluginRegistry.qml:36-90`), while the installed third-party workflow clones into user config and runs no plugin hook or `sudo` (`/usr/share/omarchy/shell/README.md:94-125`).

`Panel.qml:101-113` resolves the shared service through `bar.shell.serviceFor("osouthgate.minimize")`; all bar copies read one list. `Panel.qml:125-132` derives restore-here from the clicked panel's screen monitor, preserving per-monitor targeting without duplicating state.

Existing primitive considered: the stock scratchpad. It already supplies reversible `Super+Alt+S`/`Super+S`, but exposes one workspace rather than a labelled exact-window drawer, has no trusted-origin metadata, and does not provide the service IPC contract. It stays intact as an adopted alias rather than becoming the plugin implementation.

Why: A separate process or duplicated per-monitor model would drift from Omarchy's service/bar lifecycle and make counts or restore targets disagree.

### 5.3 Live model, journal, and transactions

`MinimizeModel.js:290-323` reconciles current Hyprland clients with supplemental records. A matching record retains origin, ownership, minimize baseline, and latched attention; a live compatible window without matching trusted metadata is adopted as `owned: false`. Closed, arbitrary-special, instance-mismatched, or stable-ID-mismatched entries disappear. An owned identity moved externally to a normal workspace leaves the visible list but remains in the service's private ledger until its exact activation override is safely cleared.

Before a mutation, `Service.qml:1091-1187` plans one eligible active/selected client and calls `startAction`. `Service.qml:283-335,615-669` persists schema-2 records plus a bounded pending-stage journal before `runNextStep` can launch `hyprctl repl`. The journal advances before confirmation, post-restore, rollback, cleanup, protection, and timeout-resolution stages (`Service.qml:701-990`). `FileView` uses blocking, atomic writes below a sanitized compositor-instance path (`Service.qml:53-58,1261-1271`). Startup loads before accepting work, rejects another instance or corrupt schema, and recovers only after identity and live-workspace proof (`Service.qml:337-484`).

Transaction builders in `CompositorTransaction.js:109-137` emit bounded ASCII Lua and embed an exact object guard. Minimize refuses pinned/grouped/source drift, sets the activation override, moves silently, and verifies destination in one request (`140-158`). Restore verifies compatible membership, moves and confirms before a separate focus/unset request (`160-196`); Hyprland's synchronous focus-dispatch acknowledgement is the focus result, avoiding a racy same-request active-window observation while preserving target proof → focus → unset order. Cleanup proves the exact visible workspace before unsetting, interrupted-minimize protection proves one exact accepted alias before reasserting, and all resolution steps repeat the identity guard (`198-266`).

Existing primitive considered: address-only `hyprctl` commands. An address can be reused after close, so the implementation binds address to PID, compositor stable ID, mapping, instance, source, and target. Legacy dispatcher strings also do not match the installed Hyprland 0.56 Lua command surface.

Why: Moving first and checking later without an intent journal or stable identity can reveal the wrong window, lose the original origin, or leave `focus_on_activate=0` behind.

### 5.4 Sidebar and attention

`Panel.qml` implements the bar and semantic keyboard contract: left toggles, right minimizes, and middle restores latest. Plain row, Enter, Space and latest restore are origin-first; Shift-click/Shift+Enter are explicit restore-here; Restore all remains all-here. A queued single-window restore records a panel-local close intent: its authoritative `restored` completion closes that drawer, while refusal, partial failure, or manual close clears the intent and keeps recovery visible. Restore-all never sets that intent. The fixed-right `KeyboardPanel` now owns Windows, Help and Shortcuts pages with compact named header controls, Back-before-close navigation, F1/`?` Help, and a field-focus bypass that lets text editors receive letters, arrows, modifiers and Tab.

`HelpView.qml` provides bounded plain-text guidance for the mental model, controls, fallback, honest attention states, limitations and recovery. `ShortcutSettingsView.qml` keeps per-panel drafts local while observing one singleton configured/busy result, records keyboard combinations and the 27 non-wheel buttons Qt exposes, and shows a named live availability result beside each field. Save is disabled until both exact drafts match a successful free-pair preview. It exposes configured/absent/loading/error/success/remove-confirmation states and calls only the shared service's read/check/apply/remove API. Both pages use scrollable native controls and explicit accessibility metadata.

`WindowRow.qml:24-66` derives one honest label, source alias, origin availability, and elapsed value. It renders title, class, source, and state with `Text.PlainText`, accessible state/origin descriptions, and constrained layout (`WindowRow.qml:68-200`); row activation only emits the already-normalized row index/action (`203-214`). There is no compositor process or poll in a row.

Attention is deterministic: urgency latches first; otherwise a title unequal to the minimize baseline latches Updated (`MinimizeModel.js:236-249`). `acknowledge` resets the marker and moves the current title to the new baseline (`MinimizeModel.js:325-329`; `Service.qml:1001-1020`). This is signal tracking, not job inference.

Existing primitive considered: application thumbnails and generic “finished” heuristics. Thumbnails add capture/privacy/lifecycle complexity; arbitrary titles and urgency do not prove successful completion. V1 spends that complexity budget on exact lifecycle and clear labels.

Why: A visually familiar drawer is unsafe if its rows can execute application text, route to the wrong monitor, or overstate what an application actually signalled.

### 5.5 Shortcuts, recovery, and removal

`bin/configure-shortcuts` owns exactly one marked pair: no-argument `add` retains the suggested `Super+M` service-minimize and `Super+Alt+M` panel-toggle defaults. `status --json` reports configured or absent state without mutation. `check --json` canonicalizes both drafts, takes one live binding snapshot, excludes only the exact currently owned tuple, and returns per-field validity, availability, and every named conflict without a lock, backup, reload, or edit. `apply` repeats validation and selects add/update while holding a nonblocking plugin lock. `--minimize-binding` and `--sidebar-binding` accept canonicalized keyboard chords and `mouse:272` through `mouse:767`; unmodified left/right/middle buttons, wheel directions, physical `code:N`, duplicate actions, control characters, and Lua-capable punctuation are rejected before discovery or mutation. Numeric mouse actions deliberately use a normal one-shot bind rather than Hyprland's movement-only mouse binding mode.

The singleton service resolves the helper from the plugin source directory and launches exact argv arrays through a dedicated process—never shell evaluation. It serializes shortcut checks and mutations, schema-validates bounded JSON results, keeps availability separate from configured state, refreshes JSON status after every mutation, and broadcasts the same known/configured/busy/result state to every panel. A preview is advisory only: the locked Save path deliberately repeats conflict discovery to close the check-to-save race.

`update` requires at least one requested action and preserves the omitted action. It recognizes only the exact generated block, excludes at most one currently owned live tuple per action, reports all remaining conflicts, and replaces the block in place. Add, update, and remove resolve a binding-file symlink to its regular-file target, create a dated backup, atomically replace that target, reload Hyprland, check empty config errors, and restore prior bytes on failure or interruption. Setup remains opt-in because the manifest deliberately has no installation side effects; shortcut state is not modeled as a hot-reloaded widget setting with transactional side effects.

The README defines two plugin-independent Hyprland 0.56 paths. The first toggles each accepted special workspace for inspection. The second snapshots canonical address/PID/stable ID tuples; inside each Lua request it revalidates identity and accepted-alias membership, refuses pinned/grouped windows before mutation, moves to the active normal workspace, proves the exact destination before unsetting `focus_on_activate`, and finally verifies no accepted alias remains. Because that emergency action covers all accepted aliases, it explicitly warns that external windows move too.

Normal removal is narrower. `prepareRemoval` exclusively acquires a service-side drain in the same event loop that rejects subsequent minimize calls; the compositor-session journal preserves that drain across a shell reload. A competing removal attempt is refused, and its ownership-aware trap cannot cancel the first attempt's gate. The script then accepts service `status` only when ready, loaded, idle, and still draining, and fails before any mutation if the private unresolved-owned ledger is nonempty. It selects every `.owned == true` record still live in an accepted alias (including an owned identity reconciled into another alias); queues exact restores sequentially; waits for idle plus row disappearance and an empty unresolved ledger; and repeats those gates before removal. It then prints external-owner warnings, removes the shortcut block, and only then runs `omarchy plugin remove`; an exit/signal trap calls `cancelRemoval` on an aborted run only after that run successfully acquired the drain. Explicit cancellation or ending the compositor session clears the gate. `restoreAll` was considered and rejected for uninstall because its intended UI contract includes every listed compatible alias.

Existing primitive considered: reading `/tmp/minimize-state/windows.json` to recover ownership. OmaVeil/NiflVeil cache data is external, may be stale, and cannot establish the current compositor identity. Live membership plus this plugin's instance journal provides the narrower authority needed here.

Why: Installation and ordinary use are not recoverable if the only escape hatch is the UI being removed or if uninstall conflates plugin-owned and externally owned hidden windows.

### 5.6 Verification surfaces

The dependency-free Node suite checks normalization, exact aliasing, attention, restore planning, Lua escaping, identity guards, guarded cleanup/protection, and maximum request frames. Headless QML harnesses exercise journal/load/recovery, a 1,000-event debounce burst, simultaneous external restores, cleanup races and injected write/command failure, monitor loss, pending-action interleavings, native UI loading, visible shortcut/window states, all keyboard actions, accessibility, per-monitor targets, plain-text hostile titles, two-panel dirty drafts, and a 100-row no-per-row-poll list. The visual harness writes current-theme empty, populated, updated, urgent, long-list, Help, and Shortcuts captures. `tests/shortcuts/configure-shortcuts.test.sh` uses fake command/config paths for JSON status, locked apply, default/custom success, keyboard/mouse conflict reporting, canonicalization, in-place update with owned-binding exclusion, internal collision and hostile-input refusal, idempotence, malformed markers, backups, add/update/remove rollback, removal scope, and symlink preservation.

`scripts/live-smoke` capability-checks tools, session, Lua REPL, current workspace, and monitor, then discovers a second visible monitor. It creates uniquely classed disposable `foot` fixtures, records each exact address/PID/stable-ID identity, and runs the production restore planner before transaction builders for live-origin, missing-origin fallback, and explicit second-monitor restore-here cases. It also covers tiled, floating, fullscreen, title/urgent-like, close-hidden, multiple, pinned/grouped refusal, and all three rescue aliases. Every dispatched target must belong to the fixture registry, before/after pre-existing client identity sets must match, and the exit trap requires exact registered class/PID/address/stable-ID identity before closing a surviving fixture. Only unreaped child PIDs remain in the process-cleanup registry, preventing a later EXIT trap from signalling a reused PID.

`tests/acceptance/run` treats §6's nine ids as canonical, executes the README rescue and removal blocks against deterministic fakes (including restore failure, verification timeout, and unresolved ownership), runs the shortcut and capability-aware live probes, verifies every repository-local SHA-256 evidence pin, and asserts one `ok - AT-n` line per id for `AT-ALL` (`tests/acceptance/run:4-7,76-350`). An explicit live SKIP is evidence that the environment was not qualified, not proof of compositor behavior; a release transcript must distinguish it from a live pass.

Why: Unit-only evidence cannot prove compositor address isolation, while a live-only demo cannot cheaply force conflicts, malformed state, or rollback errors.

### 5.7 Considered and rejected

| Alternative | Why it loses |
|---|---|
| Rebind stock `Super+Alt+S` / `Super+S` | Breaks a familiar, recoverable Omarchy scratchpad and creates an upgrade conflict. |
| Install suggested shortcuts from a hook | Omarchy intentionally runs no plugin install hook; implicit key capture violates user control. |
| Store shortcuts as manifest widget settings | Hot-reloaded scalar settings do not provide a safe transactional Hyprland binding lifecycle and can drift from the active binding snapshot. |
| Treat a side-button action as a movement mouse bind | Hyprland reserves that mode for drag/resize dispatchers; minimize is a normal discrete bind. |
| Treat every `special:*` workspace as minimized | Adopts unrelated dropdowns and scratchpads without consent. |
| Use `restoreAll` during uninstall | Correctly restores the UI list but is too broad for ownership-aware removal. |
| Trust another tool's `/tmp` cache | Cache membership and reused addresses can diverge from the live compositor. |
| Vendor or call the OmaVeil/NiflVeil Rust binary | Adds a second state authority and packaging/runtime dependency without improving native shell integration. |
| Infer “done” from a title or urgency | Produces confident false completion claims for arbitrary applications. |
| Ship thumbnails in v1 | Adds capture/privacy/performance state before lifecycle safety is proven. |

Why: Recording the losing mechanisms prevents a future simplification from silently reintroducing the exact recovery and ownership failures this capability exists to avoid.

Why — what breaks without it: Without one end-to-end mechanism, the model, UI, helper, rescue instructions, and acceptance evidence could each be locally plausible while disagreeing about identity or ownership.

## 6. Acceptance
*(agent drafts, human confirms)*

| # | Given | When | Then | Runnable evidence |
|---|---|---|---|---|
| AT-1 | A binding file has no owned block and the requested default or custom keyboard/mouse pair is free or occupied | The sidebar previews availability or explicit Save applies both drafts | Read-only JSON canonicalizes both fields, names every live conflict and detects internal duplication without an edit or backup; one locked `apply` repeats the check and preserves the complete pair only when both triggers remain free | `bash tests/acceptance/run AT-1` |
| AT-2 | A binding file contains unrelated bytes, an exact default/custom owned block, or a simulated reload/configuration failure | The helper applies, updates, or removes its pair | Every real mutation is backed up, reloads and checks `configerrors`; update preserves block position, failure restores byte-for-byte, contention changes no bytes, and removal changes only the marked block | `bash tests/acceptance/run AT-2` |
| AT-3 | A new user needs to install, update, operate, configure, interoperate, and understand the plugin | They use in-sidebar Help/Shortcuts or read `README.md` | Help covers origin-first/default fallback, explicit restore-here, single-restore auto-close only after success, truthful attention semantics and recovery; recording captures keyboard/common mouse input, per-field live checks name conflicts and gate Save, opening/reset/check remains non-mutating, Remove is confirmed, and advanced raw mouse entry is documented | `bash tests/acceptance/run AT-3` plus QML UI/native smoke |
| AT-4 | Omarchy Minimize or the shell is unavailable while windows occupy any accepted alias | The user follows the compositor-only Recovery section | They can expose each alias or restore validated address/PID/stable-ID identities from all three aliases; the rescue rechecks membership, refuses pinned/grouped state, proves its destination, and unsets `focus_on_activate` without plugin IPC | `bash tests/acceptance/run AT-4` plus a disposable live rescue transcript |
| AT-5 | Plugin-owned windows, unresolved owned cleanup records, and externally owned alias windows can coexist before uninstall | The user follows the Remove section | A service-side drain rejects concurrent new minimizes; every owned address across accepted aliases is restored from ready/loaded/idle/draining service states and verified before files are removed; unresolved ownership stops removal with a safe next action; external aliases are warned, shortcut removal is scoped, and abort cancels the drain | `bash tests/acceptance/run AT-5` |
| AT-6 | An active compatible Hyprland session contains pre-existing user clients | The opt-in live probe runs, succeeds, fails, or is interrupted | It targets only uniquely classed fixture identities, records equal pre/post user address sets, restores baseline focus when possible, and leaves zero fixtures | `bash tests/acceptance/run AT-6` with `OMARCHY_MINIMIZE_LIVE=1` for a required live pass |
| AT-7 | Disposable origin-first, restore-here, origin-missing, tiled, floating, fullscreen, title/urgent-like, close-hidden, multiple, pinned, grouped, and three-alias fixtures exist | Production restore planning and transaction builders run against exact identities | Normal restore chooses a live origin even with another panel fallback; explicit restore-here targets that panel; missing origin names the here fallback; lifecycle/refusal/rescue cases remain exact and isolated | `bash tests/acceptance/run AT-7` with `OMARCHY_MINIMIZE_LIVE=1` |
| AT-8 | The package includes its production source, README, and license | Attribution and dependency checks run | OmaVeil/NiflVeil are credited while no runtime product source calls, embeds, or reads their Rust binary/source or `/tmp/minimize-state/windows.json` | `bash tests/acceptance/run AT-8` |
| AT-9 | This §6 table and the v0.4.1 runtime hash inventory are canonical | The runner executes `AT-ALL` | It maps exactly AT-1 through AT-9, verifies every local hash pin including Help/Shortcuts, and emits each canonical result exactly once before a 9/9 summary | `bash tests/acceptance/run AT-9`; `bash tests/acceptance/run AT-ALL` |

No §0 rule is tagged UNTESTED. AT-4 and AT-5 include documentation/static gates; a release decision should additionally preserve the requested live/manual transcripts rather than mistaking string presence for a witnessed recovery or uninstall.

Why — what breaks without it: Stable scenario IDs are the bridge from product rules to deterministic, live, and manual evidence; prose-only “works” claims cannot identify a missing recovery path.

## 7. Build phases
*(agent)*

1. **Model contract:** normalize exact aliases and identities; reconcile live records; define attention and restore planning; build guarded transaction steps. Greens the model portion of AT-7.
2. **Service authority:** load instance-scoped supplemental state, persist pending stages before effects, expose deterministic IPC, and recover timeout/reload paths. Greens the service portion of AT-7.
3. **Sidebar experience:** implement one shared count, fixed-right multi-monitor panel, honest rows, click/keyboard actions, visible states, hostile-title handling, and 100-row behavior. Greens the product surface asserted by AT-3 and AT-7.
4. **Recovery package:** add conflict-safe reversible shortcuts, complete user/recovery/removal documentation, attribution, canonical acceptance runner, and disposable live fixtures. Greens AT-1 through AT-9.
5. **Polish and hardening:** visually inspect all states, qualify accessibility and performance, rerun the full suite with a required live session, and pin a real project commit before release. Preserves AT-1 through AT-9.

Why — what breaks without it: Building UI before the identity/service contract or packaging before recovery evidence would make polished behavior depend on unsafe compositor mutations.

## 8. Decisions
*(agent-maintained register; human ratification remains authoritative)*

| # | Date | Decision | Owner | Why |
|---|---|---|---|---|
| D1 | 2026-09-08 | One native `service` plus one singleton right-side `bar-widget` under `osouthgate.minimize` | Owen | One authority serves all monitor copies and IPC callers. |
| D2 | 2026-09-08 | Create in `special:minimum`; adopt only `special:minimum`, `special:minimized`, and `special:scratchpad` | Owen | Covers OmaVeil/NiflVeil, Dock, and stock workflows without swallowing unrelated specials. |
| D3 | 2026-09-08 | Live compositor membership is canonical; session-scoped records supplement origin/attention only | Owen | Private caches become stale and cannot prove current identity. |
| D4 | 2026-09-09 | Default restore returns to a live trusted remembered workspace; Shift explicitly restores here, with panel→global fallback when origin is unavailable | Owen | Fixes wrong-monitor restores while preserving a deliberate current-context action. |
| D5 | 2026-09-08 | “Needs attention” and “Updated” are the only completion-adjacent labels | Owen | They state observable provenance without inventing job success. |
| D6 | 2026-09-08 | Pinned/grouped windows fail before mutation; thumbnails are omitted in v1 | Owen | Reduces lifecycle and privacy risk until live evidence supports expansion. |
| D7 | 2026-09-08 | `Super+M` and `Super+Alt+M` are opt-in conflict-checked suggestions, never install-time defaults | Owen | Live bindings differ; on the inspected system `Super+M` is occupied. |
| D8 | 2026-09-08 | Uninstall restores only proven owned records; emergency all-alias rescue is explicit and broader | Owen | Normal cleanup must not take ownership of Dock or stock windows. |
| D9 | 2026-09-08 | Credit OmaVeil/NiflVeil at the protocol/concept level without vendoring or cache dependency | Owen | Acknowledges prior work while retaining one native runtime authority. |
| D10 | 2026-09-09 | Confirm §0 verbatim and advance the capability outcome from `draft` to `agreed` | Owen | The protected outcome, rules, and success signal now have explicit human ownership. |
| D11 | 2026-09-09 | Keep the confirmed shortcut defaults as suggestions while allowing each trigger to be replaced with a conflict-checked keyboard chord or mouse button | Owen | A dedicated mouse button or a preferred Super-key chord makes minimize usable without forcing one fixed personal workflow. |
| D12 | 2026-09-09 | Put Help and shortcut drafts in the existing sidebar; page open/reset/refresh are read-only, Save is explicit, and owned-block removal is confirmed | Owen | Discoverability and personalization stay native without turning page navigation into a config mutation. |
| D13 | 2026-09-09 | Record one shortcut action at a time, show named live conflicts beside each field, gate Save on a fresh free-pair preview, and repeat conflict checking inside Save | Owen | Recording removes Linux input-code guesswork while preview plus atomic recheck keeps occupied bindings safe under concurrent changes. |
| D14 | 2026-09-09 | Keep the sidebar visible while a single restore is pending, close it after authoritative success, and retain it with the error on failure; restore-all stays open | Codex | A successful selection hands focus and visual context back to that window without leaving a stale drawer, while failures preserve recovery controls. |

Why — what breaks without it: Unrecorded choices are easily “simplified” into broad special-workspace adoption, silent keybinding changes, or cache coupling.

## 9. Open questions
*(answers append inline; never delete the question)*

Q1 — owner: Owen — **RESOLVED 2026-09-09**: Confirm the §0 candidate outcome, rules, and how-we'll-know lines verbatim so the protected human block can lose its pending marker and the document can advance beyond `draft`. Recommended: confirm as written because each line traces to the approved roadmap and all have acceptance coverage. Invariants at stake: product intent must not be silently authored by the implementing agent. Answer — Owen: “yes to the protected outcome.” The block was confirmed without changing its wording, and the document advanced to `agreed`.

Q2 — owner: maintainer — **RESOLVED 2026-09-09**: The canonical public repository is `https://github.com/osouthgate/omarchy-minimize`; the first verified baseline remains Omarchy 4.0.2 / Hyprland 0.56.2. Answer — Owen requested publication as `osouthgate/omarchy-minimize`. Invariants preserved: install instructions now use the executable canonical URL and the dispatcher APIs remain tied to the tested baseline.

Q3 — owner: maintainer — non-blocking: Should a future release add a service IPC method that restores only owned records for uninstall automation? Recommended: defer until it can preserve sequential verification and external-owner reporting; the documented status/restore loop is explicit and auditable today. Invariants at stake: ownership-aware removal and exact-address verification.

Why — what breaks without it: Recording the resolved intent question alongside the remaining publication choices prevents `agreed` from being mistaken for published or installed.

## 10. Out of scope
*(agent)*

- Detecting whether arbitrary application work “finished,” succeeded, or failed.
- Window thumbnails, preview capture, and process suspension.
- Minimizing pinned/grouped windows or automatically dismantling their state.
- Adopting arbitrary named special workspaces.
- Migrating, repairing, or deleting OmaVeil, NiflVeil, Dock, or scratchpad private metadata.
- Rebinding or removing stock `Super+Alt+S` / `Super+S`.
- Silently choosing an alternate chord when either suggested shortcut conflicts.
- Packaging or publishing a canonical Git repository URL.

Why — what breaks without it: These additions either require a separate product decision or weaken the narrow identity, ownership, and truthfulness guarantees of the shipped capability.
