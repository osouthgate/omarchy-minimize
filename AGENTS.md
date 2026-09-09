# AGENTS.md

## Scope

These instructions apply to `omarchy-minimize/` and every directory below it.
This is a native Omarchy shell plugin built with QML, JavaScript, Bash,
Quickshell, and Hyprland's Lua IPC.

## Product contract

- `special:minimum` is the only destination created by this plugin.
- List and individually restore only the exact aliases `special:minimum`,
  `special:minimized`, and `special:scratchpad`.
- Live Hyprland client membership is authoritative. The runtime journal may
  supplement origin, attention, ownership, and pending-transition metadata,
  but it must never override live identity or workspace state.
- Default restore returns a plugin-owned window to its live remembered normal
  workspace. Shift is the explicit restore-here action; a missing/untrusted
  origin safely falls back to the requesting panel, then global focus.
- Opening Help or Shortcuts is read-only. Only explicit Save or a second,
  confirmed Remove may mutate the helper-owned, conflict-checked binding block.
- Attention wording must remain observational: **Needs attention** for urgency
  and **Updated** for a post-minimize title change. Never claim that arbitrary
  application work completed or succeeded.
- Pinned and grouped windows are unsupported and must be refused before any
  compositor mutation.
- Window thumbnails and arbitrary `special:*` adoption remain out of scope.

## Safety invariants

1. Never target a window by address alone. Bind canonical address, PID,
   compositor stable ID, mapped state, and expected workspace inside the same
   guarded `hyprctl repl` request.
2. Validate every address and workspace before interpolating it into Lua.
   Titles, classes, events, and saved state are untrusted display data and must
   never become shell arguments or Lua source.
3. For an owned minimize, set `focus_on_activate=0` before moving to
   `special:minimum`. On restore, prove the destination, focus the exact window,
   and unset the property last.
4. Persist the pending transition before sending a compositor command. A write
   failure must fail closed without mutation.
5. Keep generated Lua requests within the tested Hyprland frame bound. The
   transaction suite currently enforces a maximum safe payload of 1,016 bytes.
6. Preserve the exclusive, compositor-session-scoped removal drain. It must
   survive a shell reload, reject new minimizes, refuse competing acquisition,
   and remain active when cancellation cannot be persisted.
7. Never clear another tool's dynamic property or private metadata. Ordinary
   uninstall restores only identities proven to be owned by this plugin.
8. Cleanup code must retain exact ownership. The live probe may signal only
   unreaped child PIDs it spawned and may close only a registered
   class/PID/address/stable-ID identity.

## System boundaries

- Do not edit `/usr/share/omarchy/`; it is reference-only package content.
- Do not edit files under `~/.config/`, install or enable this plugin, change
  keybindings, restart the shell, or run removal/rescue commands against real
  windows unless the user explicitly requests that system change.
- The manifest must keep no install hook. Optional shortcuts remain a separate,
  visible, conflict-checked action and must never assume either chord is free.
- Do not vendor a second minimizer, read another tool's cache as authority, or
  add downloaded runtime dependencies.
- Live tests create windows and can temporarily change focus. Run them
  sequentially, never concurrently with another live probe, and require their
  final isolation and cleanup markers.

## File map

- `MinimizeModel.js` — pure normalization, reconciliation, attention, and
  restore planning.
- `CompositorTransaction.js` — bounded exact-identity Lua transaction builders.
- `Service.qml` — singleton live authority, durable journal, IPC, recovery, and
  removal drain.
- `Panel.qml` / `WindowRow.qml` — bar widget, right-edge panel, keyboard and
  accessible row UI.
- `HelpView.qml` / `ShortcutSettingsView.qml` — scrollable help and explicit
  shortcut draft/apply/remove pages backed by singleton service state.
- `manifest.json` — native plugin declaration and settings.
- `bin/configure-shortcuts` — opt-in, reversible, conflict-safe bindings helper.
- `scripts/live-smoke` — destructive only to uniquely owned disposable fixtures.
- `tests/` — deterministic model, service, UI, shortcut, acceptance, and live
  fixtures.
- `README.md` — user operation, recovery, and removal authority.
- `docs/outcomes/omarchy-minimize.md` — product decisions and acceptance map.

## Change workflow

1. Read the affected production file, its focused tests, `README.md`, and the
   relevant outcome invariants before changing behavior.
2. Preserve existing user work and keep changes inside this plugin unless the
   user explicitly broadens scope.
3. Add a deterministic regression assertion for every lifecycle, identity,
   command-ordering, security, accessibility, or removal fix.
4. If an IPC method changes, update its exact inventory in the service smoke
   test and user documentation.
5. If a hash-pinned runtime file changes, recompute its SHA-256 prefix in the
   outcome document before running `AT-9` or `AT-ALL`.
6. Do not rewrite the protected §0 block in the outcome document without the
   owner's explicit verbatim confirmation. Append decisions or answers instead.
7. Keep production files free of debug logging, session TODO/FIXME markers,
   generated caches, machine-specific paths, and hardcoded light/dark palettes.

## Verification

Run commands from the directory containing `omarchy-minimize/`. Start with the
focused check, then use the complete deterministic set before handoff:

```bash
node --test omarchy-minimize/tests/minimize-model.test.cjs
npm --prefix omarchy-minimize test
omarchy plugin validate omarchy-minimize
bash omarchy-minimize/tests/qml-service-smoke.sh
bash omarchy-minimize/tests/qml-smoke.sh
bash omarchy-minimize/tests/shortcuts/configure-shortcuts.test.sh
bash omarchy-minimize/tests/acceptance/run AT-ALL
```

The acceptance runner may use the active compositor when its capabilities are
available. To force a deterministic no-live acceptance pass during focused
work, set `OMARCHY_MINIMIZE_LIVE=0`; this is not release evidence.

For a behavior-changing release, run the standalone live matrix last and
surface its exact-address, isolation, and cleanup lines:

```bash
OMARCHY_MINIMIZE_LIVE=1 bash omarchy-minimize/scripts/live-smoke
```

A live pass is valid only when it reports `exact-addresses=pass`,
`preexisting_touched=0`, and `LIVE_CLEANUP_PASS fixtures_remaining=0`.
