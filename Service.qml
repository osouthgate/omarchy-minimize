import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "MinimizeModel.js" as Model
import "CompositorTransaction.js" as Transaction

Item {
  id: root

  width: 0
  height: 0
  visible: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null

  // Deterministic compositor adapter used only by the QML smoke harness.
  property bool testMode: false
  property var testClients: []
  property var testActiveClient: null
  property var testWorkspaces: []
  property var testFocusedWorkspace: ({ id: 1, name: "1" })
  property string testInstanceSignature: "test-instance"
  property var testCommandLog: []
  property string testPersistedText: ""
  property bool testStateWriteFailure: false
  property int testRefreshCount: 0
  property int testReconcileCount: 0
  property var testShortcutCommandLog: []
  property bool testShortcutStartFailure: false

  property int transitionTimeoutMs: 1800
  property var entries: []
  property var supplementalRecords: []
  property var pendingAction: null
  property var currentStep: null
  property var restoreQueue: []
  property var restoreQueueTarget: null
  property string lastOperation: "Ready"
  property string lastError: ""
  property bool loaded: false
  property bool stateReady: testMode
  property bool loadingState: !testMode
  property bool removalDrain: false
  property bool stateSaveFailed: false
  property var lastRawEvent: ({ name: "", data: "" })
  property bool shortcutStateKnown: false
  property bool shortcutConfigured: false
  property bool shortcutBusy: false
  property bool shortcutMutationActive: false
  property string minimizeShortcut: ""
  property string sidebarShortcut: ""
  property string shortcutLastOperation: ""
  property string shortcutLastError: ""
  property string shortcutPendingKind: ""
  property string shortcutDeferredKind: ""
  property bool shortcutDeferredOk: false
  property string shortcutDeferredMessage: ""
  property bool shortcutCheckKnown: false
  property bool shortcutPairAvailable: false
  property var shortcutMinimizeCheck: ({})
  property var shortcutSidebarCheck: ({})
  property string shortcutCheckError: ""

  readonly property bool busy: pendingAction !== null
  readonly property int count: entries.length
  readonly property int urgentCount: countAttention(Model.ATTENTION_URGENT)
  readonly property int updatedCount: countAttention(Model.ATTENTION_UPDATED)
  readonly property int unresolvedOwnedCount: unresolvedOwnedEntries().length
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  readonly property string instanceSignature: testMode
    ? testInstanceSignature : String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "")
  readonly property string safeInstanceName: instanceSignature.replace(/[^A-Za-z0-9._-]/g, "_")
  readonly property string statePath: runtimeDir && safeInstanceName
    ? runtimeDir + "/omarchy-minimize-" + safeInstanceName + ".json" : ""
  readonly property string shortcutHelperPath: testMode
    ? "/fixture/plugin/bin/configure-shortcuts"
    : String(manifest && manifest.__sourceDir || "") + "/bin/configure-shortcuts"

  signal operationFinished(string code, bool ok)
  signal shortcutOperationFinished(string code, bool ok)

  function result(ok, code, message, extra) {
    var value = {
      ok: ok === true,
      code: String(code || ""),
      message: String(message || "")
    }
    var fields = extra || ({})
    for (var key in fields) value[key] = fields[key]
    return value
  }

  function boundedShortcutText(value) {
    return String(value || "").replace(/\u0000/g, "").trim().slice(0, 2048)
  }

  function shortcutStatusArgv() {
    return [shortcutHelperPath, "status", "--json"]
  }

  function appendShortcutCommand(argv) {
    var log = testShortcutCommandLog.slice()
    log.push(argv.slice())
    testShortcutCommandLog = log
  }

  function parseShortcutStatus(output) {
    var value
    try {
      value = JSON.parse(String(output || ""))
    } catch (error) {
      return root.result(false, "invalid-shortcut-status",
        "Shortcut status returned invalid JSON.")
    }
    if (!value || value.ok !== true || typeof value.configured !== "boolean")
      return root.result(false, "invalid-shortcut-status",
        "Shortcut status did not match the expected schema.")
    var minimizeValue = String(value.minimizeBinding || "")
    var sidebarValue = String(value.sidebarBinding || "")
    if (minimizeValue.length > 128 || sidebarValue.length > 128
        || (value.configured && (!minimizeValue || !sidebarValue)))
      return root.result(false, "invalid-shortcut-status",
        "Shortcut status contained invalid binding values.")
    return root.result(true, "shortcut-status", "Shortcut status loaded.", {
      configured: value.configured,
      minimizeBinding: value.configured ? minimizeValue : "",
      sidebarBinding: value.configured ? sidebarValue : ""
    })
  }

  function parseShortcutCheck(output) {
    var value
    try {
      value = JSON.parse(String(output || ""))
    } catch (error) {
      return root.result(false, "invalid-shortcut-check",
        "Shortcut availability returned invalid JSON.")
    }
    if (!value || value.ok !== true || typeof value.pairAvailable !== "boolean"
        || typeof value.duplicate !== "boolean" || !value.minimize || !value.sidebar)
      return root.result(false, "invalid-shortcut-check",
        "Shortcut availability did not match the expected schema.")

    function checkedField(field) {
      if (!field || typeof field.input !== "string" || typeof field.binding !== "string"
          || typeof field.valid !== "boolean" || typeof field.available !== "boolean"
          || !Array.isArray(field.conflicts) || typeof field.message !== "string") return null
      if (field.input.length > 128 || field.binding.length > 128 || field.message.length > 512
          || field.conflicts.length > 32) return null
      var conflicts = []
      for (var i = 0; i < field.conflicts.length; i++) {
        if (typeof field.conflicts[i] !== "string" || field.conflicts[i].length > 256) return null
        conflicts.push(field.conflicts[i])
      }
      return ({
        input: field.input,
        binding: field.binding,
        valid: field.valid,
        available: field.available,
        conflicts: conflicts,
        message: field.message
      })
    }

    var minimize = checkedField(value.minimize)
    var sidebar = checkedField(value.sidebar)
    if (!minimize || !sidebar)
      return root.result(false, "invalid-shortcut-check",
        "Shortcut availability contained invalid field values.")
    return root.result(true, "shortcut-check", "Shortcut availability checked.", {
      minimize: minimize,
      sidebar: sidebar,
      duplicate: value.duplicate,
      pairAvailable: value.pairAvailable
    })
  }

  function clearShortcutCheck() {
    shortcutCheckKnown = false
    shortcutPairAvailable = false
    shortcutMinimizeCheck = ({})
    shortcutSidebarCheck = ({})
    shortcutCheckError = ""
  }

  function launchShortcutProcess(argv) {
    if (testMode) {
      root.appendShortcutCommand(argv)
      if (testShortcutStartFailure) {
        testShortcutStartFailure = false
        root.finishShortcutProcess(127, "", "Shortcut helper could not be started.")
        return false
      }
      return true
    }
    shortcutProc.command = argv
    shortcutProc.running = true
    shortcutProcessStartGuard.restart()
    return true
  }

  function startShortcutOperation(kind, argv, mutation) {
    if (shortcutBusy)
      return root.result(false, "shortcut-busy",
        "Another shortcut operation is still running.")
    if (mutation === true && busy)
      return root.result(false, "window-busy",
        "A window transition is still running; wait before changing shortcuts.")
    if (mutation === true && removalDrain)
      return root.result(false, "removal-draining",
        "Removal preparation is active; cancel it before changing shortcuts.")
    if (!shortcutHelperPath || shortcutHelperPath === "/bin/configure-shortcuts")
      return root.result(false, "missing-shortcut-helper",
        "The shortcut helper path is unavailable.")
    shortcutBusy = true
    shortcutMutationActive = mutation === true
    shortcutPendingKind = kind
    shortcutDeferredKind = ""
    shortcutDeferredOk = false
    shortcutDeferredMessage = ""
    if (kind === "check") root.clearShortcutCheck()
    else shortcutLastError = ""
    if (kind === "status") shortcutLastOperation = "Reading shortcut settings."
    var launched = root.launchShortcutProcess(argv)
    if (!launched && !shortcutBusy)
      return root.result(false, "shortcut-start-failed",
        shortcutLastError || "Shortcut helper could not be started.")
    return root.result(true, "shortcut-queued", kind === "status"
      ? "Reading shortcut settings." : "Updating shortcut settings.")
  }

  function applyShortcutStatus(parsed) {
    if (!parsed.ok) {
      shortcutStateKnown = false
      return false
    }
    shortcutStateKnown = true
    shortcutConfigured = parsed.configured === true
    minimizeShortcut = parsed.minimizeBinding
    sidebarShortcut = parsed.sidebarBinding
    return true
  }

  function finishShortcutProcess(exitCode, stdoutText, stderrText) {
    shortcutProcessStartGuard.stop()
    var kind = shortcutPendingKind
    if (!kind || !shortcutBusy) return
    var output = root.boundedShortcutText(stdoutText)
    var errorText = root.boundedShortcutText(stderrText)

    if (kind === "apply" || kind === "remove") {
      shortcutDeferredKind = kind
      shortcutDeferredOk = Number(exitCode) === 0
      shortcutDeferredMessage = shortcutDeferredOk
        ? (output || (kind === "apply" ? "Shortcuts saved." : "Shortcuts removed."))
        : (errorText || output || "The shortcut change failed; no unverified setting was accepted.")
      shortcutPendingKind = "refresh"
      if (testMode) root.launchShortcutProcess(root.shortcutStatusArgv())
      else Qt.callLater(function() { root.launchShortcutProcess(root.shortcutStatusArgv()) })
      return
    }

    if (kind === "check") {
      var checked = Number(exitCode) === 0
        ? root.parseShortcutCheck(output)
        : root.result(false, "shortcut-check-failed",
            errorText || output || "Shortcut availability could not be checked.")
      shortcutBusy = false
      shortcutMutationActive = false
      shortcutPendingKind = ""
      shortcutCheckKnown = checked.ok === true
      shortcutPairAvailable = checked.ok === true && checked.pairAvailable === true
      shortcutMinimizeCheck = checked.ok === true ? checked.minimize : ({})
      shortcutSidebarCheck = checked.ok === true ? checked.sidebar : ({})
      shortcutCheckError = checked.ok === true ? "" : checked.message
      shortcutOperationFinished("check", checked.ok === true)
      return
    }

    var parsed = Number(exitCode) === 0
      ? root.parseShortcutStatus(output)
      : root.result(false, "shortcut-status-failed",
          errorText || output || "Shortcut status could not be read.")
    var statusOk = root.applyShortcutStatus(parsed)

    if (kind === "refresh" && shortcutDeferredKind) {
      var completedKind = shortcutDeferredKind
      var completedOk = shortcutDeferredOk
      var completedMessage = shortcutDeferredMessage
      shortcutBusy = false
      shortcutMutationActive = false
      shortcutPendingKind = ""
      shortcutDeferredKind = ""
      shortcutDeferredMessage = ""
      if (completedOk) {
        shortcutLastOperation = completedMessage
        shortcutLastError = statusOk ? ""
          : "Shortcuts changed, but their current status could not be refreshed: " + parsed.message
      } else {
        shortcutLastOperation = "No shortcut setting was changed."
        shortcutLastError = completedMessage
      }
      shortcutOperationFinished(completedKind, completedOk)
      return
    }

    shortcutBusy = false
    shortcutMutationActive = false
    shortcutPendingKind = ""
    if (statusOk) {
      shortcutLastOperation = shortcutConfigured
        ? "Shortcut settings loaded." : "Optional shortcuts are not configured."
      shortcutLastError = ""
    } else {
      shortcutLastOperation = "Shortcut status is unknown."
      shortcutLastError = parsed.message
    }
    shortcutOperationFinished("status", statusOk)
  }

  function refreshShortcutStatus() {
    return root.startShortcutOperation("status", root.shortcutStatusArgv(), false)
  }

  function checkShortcuts(minimizeBinding, sidebarBinding) {
    var minimizeValue = String(minimizeBinding || "")
    var sidebarValue = String(sidebarBinding || "")
    if (minimizeValue.length > 128 || sidebarValue.length > 128)
      return root.result(false, "shortcut-too-long", "Shortcut values must be 128 characters or fewer.")
    return root.startShortcutOperation("check", [
      shortcutHelperPath, "check",
      "--minimize-binding", minimizeValue,
      "--sidebar-binding", sidebarValue,
      "--json"
    ], false)
  }

  function saveShortcuts(minimizeBinding, sidebarBinding) {
    var minimizeValue = String(minimizeBinding || "")
    var sidebarValue = String(sidebarBinding || "")
    if (!minimizeValue || !sidebarValue)
      return root.result(false, "empty-shortcut", "Both shortcut fields are required.")
    if (minimizeValue.length > 128 || sidebarValue.length > 128)
      return root.result(false, "shortcut-too-long", "Shortcut values must be 128 characters or fewer.")
    return root.startShortcutOperation("apply", [
      shortcutHelperPath, "apply",
      "--minimize-binding", minimizeValue,
      "--sidebar-binding", sidebarValue
    ], true)
  }

  function removeShortcuts() {
    return root.startShortcutOperation("remove", [shortcutHelperPath, "remove"], true)
  }

  function countAttention(attention) {
    var total = 0
    for (var i = 0; i < entries.length; i++)
      if (entries[i].attention === attention) total++
    return total
  }

  function workspaceSnapshot(workspace) {
    if (!workspace) return ({ id: 0, name: "" })
    if (typeof workspace === "string" || typeof workspace === "number")
      return ({ id: Number(workspace) || 0, name: String(workspace) })
    return ({
      id: Number(workspace.id) || 0,
      name: String(workspace.name === undefined ? "" : workspace.name)
    })
  }

  function ownField(object, key, fallback) {
    return object && Object.prototype.hasOwnProperty.call(object, key)
      ? object[key] : fallback
  }

  function compositorAddress(value) {
    var address = String(value || "").trim()
    // Quickshell's native toplevel address omits Hyprland JSON's 0x prefix.
    if (/^[0-9a-fA-F]+$/.test(address)) return "0x" + address
    return address
  }

  function clientSnapshot(toplevel) {
    if (!toplevel) return null
    var ipc = toplevel.lastIpcObject || ({})
    var wayland = toplevel.wayland || ({})
    var workspace = toplevel.workspace || ipc.workspace || ({})
    var monitorValue = root.ownField(toplevel, "monitor", ipc.monitor)
    if (monitorValue && typeof monitorValue === "object")
      monitorValue = monitorValue.id
    return {
      address: root.compositorAddress(toplevel.address || ipc.address || ""),
      workspace: root.workspaceSnapshot(workspace),
      monitor: Number(monitorValue),
      pid: Number(root.ownField(toplevel, "pid", ipc.pid)),
      stableId: String(root.ownField(toplevel, "stableId", ipc.stableId) || ""),
      class: String(root.ownField(toplevel, "class", ipc.class) || wayland.appId || ""),
      initialClass: String(root.ownField(toplevel, "initialClass", ipc.initialClass)
        || wayland.appId || ""),
      title: String(toplevel.title || ipc.title || ""),
      initialTitle: String(root.ownField(toplevel, "initialTitle", ipc.initialTitle) || ""),
      urgent: toplevel.urgent === true || ipc.urgent === true,
      pinned: root.ownField(toplevel, "pinned", false) === true || ipc.pinned === true,
      grouped: root.ownField(toplevel, "grouped", ipc.grouped) || []
    }
  }

  function liveClients() {
    var source
    if (testMode) source = testClients
    else source = Hyprland.toplevels && Hyprland.toplevels.values
      ? Hyprland.toplevels.values : []
    var result = []
    for (var i = 0; i < source.length; i++) {
      var snapshot = root.clientSnapshot(source[i])
      if (snapshot) result.push(snapshot)
    }
    return result
  }

  function activeClient() {
    return root.clientSnapshot(testMode ? testActiveClient : Hyprland.activeToplevel)
  }

  function availableWorkspaces() {
    var source
    if (testMode) source = testWorkspaces
    else source = Hyprland.workspaces && Hyprland.workspaces.values
      ? Hyprland.workspaces.values : []
    var result = []
    for (var i = 0; i < source.length; i++) result.push(root.workspaceSnapshot(source[i]))
    return result
  }

  function focusedWorkspace() {
    return root.workspaceSnapshot(testMode ? testFocusedWorkspace : Hyprland.focusedWorkspace)
  }

  function originAvailable(origin) {
    var target = Model.normalWorkspaceTarget(origin)
    return target !== "" && Model.workspaceExists(target, root.availableWorkspaces())
  }

  function resolveLiveRestoreTarget(requested) {
    var workspaces = root.availableWorkspaces()
    var requestedTarget = Model.normalWorkspaceTarget(requested)
    if (requestedTarget && Model.workspaceExists(requestedTarget, workspaces))
      return { ok: true, target: requestedTarget, fallback: false, reason: "" }
    var current = root.focusedWorkspace()
    var currentTarget = Model.normalWorkspaceTarget(current)
    if (currentTarget && Model.workspaceExists(currentTarget, workspaces)) {
      return {
        ok: true,
        target: currentTarget,
        fallback: true,
        reason: "The requested workspace is no longer available; restoring to the current workspace instead."
      }
    }
    return {
      ok: false,
      target: "",
      fallback: false,
      reason: "No live normal workspace is available; switch to one, choose Reconcile, and retry."
    }
  }

  function entryByAddress(address) {
    var normalized = Model.normalizeAddress(address)
    for (var i = 0; i < entries.length; i++)
      if (entries[i].address === normalized) return entries[i]
    return null
  }

  function liveByAddress(address) {
    var normalized = Model.normalizeAddress(address)
    var clients = root.liveClients()
    for (var i = 0; i < clients.length; i++)
      if (Model.normalizeAddress(clients[i].address) === normalized) return clients[i]
    return null
  }

  function sameRecordIdentity(left, right) {
    var a = Transaction.recordIdentity(left)
    var b = Transaction.recordIdentity(right)
    return a && b
      && a.address === b.address && a.pid === b.pid && a.stableId === b.stableId
      && String(left && left.instanceSignature || "")
        === String(right && right.instanceSignature || "")
  }

  function hasRecordIdentity(records, record) {
    var values = Array.isArray(records) ? records : []
    for (var i = 0; i < values.length; i++)
      if (root.sameRecordIdentity(values[i], record)) return true
    return false
  }

  function forgetSupplementalRecord(record) {
    var retained = []
    for (var i = 0; i < supplementalRecords.length; i++)
      if (!root.sameRecordIdentity(supplementalRecords[i], record))
        retained.push(supplementalRecords[i])
    supplementalRecords = retained
  }

  function publicEntry(record) {
    return {
      address: record.address,
      title: record.title,
      className: record.className,
      sourceWorkspace: record.sourceWorkspace,
      origin: record.origin,
      monitor: record.monitor,
      minimizedAt: record.minimizedAt,
      attention: record.attention,
      attentionLabel: Model.attentionLabel(record.attention),
      owned: record.owned === true,
      recovered: record.recovered === true
    }
  }

  function unresolvedOwnedEntries() {
    var result = []
    var clients = root.liveClients()
    for (var i = 0; i < supplementalRecords.length; i++) {
      var record = supplementalRecords[i]
      if (!record || record.owned !== true) continue
      var visible = false
      for (var j = 0; j < entries.length; j++) {
        if (root.sameRecordIdentity(record, entries[j])) {
          visible = true
          break
        }
      }
      if (!visible) {
        var publicRecord = root.publicEntry(record)
        for (var c = 0; c < clients.length; c++) {
          if (Model.recordMatchesClient(record, clients[c], instanceSignature)) {
            publicRecord.sourceWorkspace = Model.workspaceName(clients[c].workspace)
            publicRecord.monitor = Model.normalizeClient(clients[c]).monitor
            break
          }
        }
        result.push(publicRecord)
      }
    }
    return result
  }

  function statusObject() {
    var visibleEntries = []
    for (var i = 0; i < entries.length; i++) visibleEntries.push(root.publicEntry(entries[i]))
    var unresolved = root.unresolvedOwnedEntries()
    return {
      ok: true,
      code: "status",
      loaded: loaded,
      stateReady: stateReady,
      busy: busy,
      removalDrain: removalDrain,
      count: count,
      urgent: urgentCount,
      updated: updatedCount,
      unresolvedOwnedCount: unresolved.length,
      lastOperation: lastOperation,
      lastError: lastError,
      entries: visibleEntries,
      unresolvedOwned: unresolved
    }
  }

  function statusJson() {
    return JSON.stringify(root.statusObject())
  }

  function pendingJournal(action) {
    if (!action || (action.type !== "minimize" && action.type !== "restore")) return null
    var address = Model.normalizeAddress(action.address)
    var identity = Transaction.recordIdentity(action.record)
    var allowedStages = {
      "initial": true,
      "confirm-minimize": true,
      "confirm-restore": true,
      "post-restore": true,
      "rollback": true,
      "recovery-cleanup": true,
      "recovery-protect": true,
      "timeout-resolve": true,
      "restore-resolve": true
    }
    if (!address || !identity || allowedStages[String(action.stage || "")] !== true) return null
    return {
      type: action.type,
      stage: String(action.stage),
      address: address,
      target: String(action.target || ""),
      record: JSON.parse(JSON.stringify(action.record)),
      stepIndex: Math.max(0, Number(action.stepIndex) || 0),
      overrideApplied: action.overrideApplied === true
    }
  }

  function statePayload() {
    var owned = []
    for (var i = 0; i < supplementalRecords.length; i++) {
      if (supplementalRecords[i].owned === true) owned.push(supplementalRecords[i])
    }
    return JSON.stringify({
      schemaVersion: 2,
      instanceSignature: instanceSignature,
      removalDrain: removalDrain === true,
      records: owned,
      pending: root.pendingJournal(pendingAction)
    }, null, 2) + "\n"
  }

  function persistState() {
    var payload = root.statePayload()
    if (testMode) {
      if (testStateWriteFailure) return false
      testPersistedText = payload
      return true
    }
    if (!stateReady || loadingState || !statePath) return false
    stateSaveFailed = false
    stateFile.setText(payload)
    // FileView.blockWrites makes onSaveFailed synchronous for this tiny tmpfs file.
    return !stateSaveFailed
  }

  function initializeEmptyState(message) {
    if (stateReady && !loadingState) return
    loadingState = true
    supplementalRecords = []
    pendingAction = null
    removalDrain = false
    stateReady = true
    loadingState = false
    lastOperation = "Minimize state initialized."
    if (message) lastError = String(message)
    root.reconcileNow()
  }

  function loadStateText(text) {
    loadingState = true
    if (!String(text || "").trim()) {
      supplementalRecords = []
      pendingAction = null
      removalDrain = false
      stateReady = true
      loadingState = false
      lastOperation = "Minimize state ready."
      lastError = ""
      root.reconcileNow()
      return root.result(true, "state-empty", "No saved minimize metadata was present.")
    }
    var parsed
    try {
      parsed = JSON.parse(String(text || ""))
    } catch (error) {
      supplementalRecords = []
      pendingAction = null
      removalDrain = false
      stateReady = true
      loadingState = false
      lastOperation = "Saved minimize state ignored."
      lastError = "Saved minimize metadata was unreadable and has been ignored."
      root.reconcileNow()
      return root.result(false, "invalid-state", lastError)
    }
    if (!parsed || (parsed.schemaVersion !== 1 && parsed.schemaVersion !== 2)
        || String(parsed.instanceSignature || "") !== instanceSignature
        || !Array.isArray(parsed.records)) {
      supplementalRecords = []
      pendingAction = null
      removalDrain = false
      stateReady = true
      loadingState = false
      lastOperation = "Saved minimize state ignored."
      lastError = "Saved minimize metadata belongs to another compositor session and has been ignored."
      root.reconcileNow()
      return root.result(false, "state-mismatch", lastError)
    }
    supplementalRecords = parsed.records
    removalDrain = parsed.schemaVersion === 2 && parsed.removalDrain === true
    stateReady = true
    loadingState = false
    lastOperation = removalDrain
      ? "Removal drain restored; new minimizes are disabled."
      : "Saved minimize state loaded."
    lastError = ""
    root.recoverPendingJournal(parsed.pending || null)
    return root.result(true, "state-loaded", "Saved metadata reconciled with live windows.")
  }

  function resolveStateLoad(text) {
    if (stateReady) return
    root.loadStateText(text)
  }

  function recoverPendingJournal(journal) {
    pendingAction = null
    if (!journal) {
      root.reconcileNow()
      return
    }

    var type = String(journal.type || "")
    var address = Model.normalizeAddress(journal.address)
    var record = journal.record || null
    var identity = Transaction.recordIdentity(record)
    if ((type !== "minimize" && type !== "restore") || !address || !identity
        || address !== Model.normalizeAddress(record && record.address)) {
      lastError = "An invalid interrupted transition was discarded without targeting a window."
      root.reconcileNow()
      return
    }

    var client = root.liveByAddress(address)
    if (!client || !Model.recordMatchesClient(record, client, instanceSignature)) {
      lastError = "An interrupted transition no longer matched the same live window and was discarded."
      root.reconcileNow()
      return
    }

    var clientWorkspace = Model.normalizeClient(client).workspace
    if (type === "minimize" && Model.isCompatibleWorkspace(clientWorkspace)) {
      root.beginProtection({
        type: "minimize",
        address: address,
        record: record,
        target: clientWorkspace,
        overrideApplied: false,
        failureCode: "interrupted-transition",
        failureMessage: "An interrupted minimize needs its activation protection confirmed; choose Reconcile to retry.",
        deferredError: ""
      })
      return
    }

    var target = Model.normalWorkspaceTarget(journal.target)
    if (type === "restore" && !Model.isCompatibleWorkspace(clientWorkspace)
        && target && Model.normalWorkspaceTarget(clientWorkspace) === target) {
      var postStep = Transaction.postRestoreStep(record, target, record.owned === true)
      if (postStep && root.startAction({
        type: "restore",
        stage: "post-restore",
        address: address,
        record: record,
        target: target,
        steps: [postStep],
        stepIndex: 0,
        overrideApplied: record.owned === true,
        deferredError: ""
      })) {
        lastOperation = "Finishing an interrupted restore."
        return
      }
    }

    if (type === "restore" && Model.isCompatibleWorkspace(clientWorkspace)) {
      lastError = "A restore was interrupted before the window moved; it remains minimized."
      root.reconcileNow()
      return
    }

    if (record.owned === true || journal.overrideApplied === true) {
      var cleanupTarget = type === "minimize"
        ? String(journal.target || "special:minimum")
        : Model.normalWorkspaceTarget(clientWorkspace)
      var cleanup = type === "minimize"
        ? Transaction.rollbackMinimizeStep(record,
          String(journal.target || "special:minimum"))
        : Transaction.cleanupStep(record, cleanupTarget)
      if (cleanup && root.startAction({
        type: type,
        stage: "recovery-cleanup",
        address: address,
        record: record,
        target: cleanupTarget,
        steps: [cleanup],
        stepIndex: 0,
        overrideApplied: true,
        failureCode: "interrupted-transition",
        failureMessage: "An interrupted transition was safely cleaned up; retry the action.",
        deferredError: ""
      })) return
    }

    lastError = "An interrupted external restore was reconciled from live compositor state."
    root.reconcileNow()
  }

  function reconcileNow() {
    if (!stateReady || loadingState) {
      return root.statusObject()
    }
    if (testMode) testReconcileCount++
    var candidates = supplementalRecords.slice()

    // One immutable compositor snapshot feeds both visible rows and the
    // durable owned ledger. A pending record is never promoted into that
    // ledger by observation alone: terminal transaction branches own that.
    var clients = root.liveClients()
    var liveByNormalizedAddress = ({})
    for (var c = 0; c < clients.length; c++) {
      var liveAddress = Model.normalizeAddress(clients[c] && clients[c].address)
      if (liveAddress && !liveByNormalizedAddress[liveAddress])
        liveByNormalizedAddress[liveAddress] = clients[c]
    }
    var pendingRecord = pendingAction && pendingAction.record
      ? pendingAction.record : null
    var pendingMinimize = pendingAction && pendingAction.type === "minimize"
    var reconciled = Model.reconcile(clients, candidates, instanceSignature, Date.now())
    var next = []
    for (var n = 0; n < reconciled.length; n++) {
      if (!(pendingMinimize && root.sameRecordIdentity(reconciled[n], pendingRecord)))
        next.push(reconciled[n])
    }

    // Keep every still-live owned identity until a guarded cleanup succeeds,
    // even when it is no longer a visible minimized row. This is the private,
    // persisted drain that prevents simultaneous external restores from
    // losing activation-override ownership.
    var retainedRecords = next.slice()
    var strandedRecords = []
    var blockedRecords = []
    for (var s = 0; s < candidates.length; s++) {
      var candidate = candidates[s]
      if (!candidate || candidate.owned !== true) continue
      var strandedClient = liveByNormalizedAddress[Model.normalizeAddress(candidate.address)]
      if (!strandedClient || !Model.recordMatchesClient(candidate, strandedClient,
          instanceSignature)) continue
      var isCurrentPending = pendingRecord
        && root.sameRecordIdentity(candidate, pendingRecord)
      if (!Model.isCompatibleWorkspace(strandedClient.workspace)) {
        if (!root.hasRecordIdentity(retainedRecords, candidate)) retainedRecords.push(candidate)
        if (!isCurrentPending) {
          if (Model.normalWorkspaceTarget(strandedClient.workspace))
            strandedRecords.push(candidate)
          else
            blockedRecords.push(candidate)
        }
      } else if (pendingMinimize && isCurrentPending
          && !root.hasRecordIdentity(retainedRecords, candidate)) {
        // Recovery-protection records remain durable but hidden until the
        // exact guarded set-property command succeeds.
        retainedRecords.push(candidate)
      }
    }

    entries = next
    supplementalRecords = retainedRecords
    loaded = true
    var actionBeforeConfirmation = pendingAction
    root.confirmPendingFromLive()
    if (actionBeforeConfirmation && pendingAction !== actionBeforeConfirmation)
      return root.statusObject()
    root.persistState()
    if (strandedRecords.length > 0 && !pendingAction) {
      var strandedRecord = strandedRecords[0]
      var currentStranded = liveByNormalizedAddress[Model.normalizeAddress(strandedRecord.address)]
      var strandedTarget = Model.normalWorkspaceTarget(currentStranded && currentStranded.workspace)
      var cleanup = Transaction.cleanupStep(strandedRecord, strandedTarget)
      if (cleanup) root.startAction({
        type: "restore",
        stage: "recovery-cleanup",
        address: strandedRecord.address,
        record: strandedRecord,
        target: strandedTarget,
        steps: [cleanup],
        stepIndex: 0,
        overrideApplied: true,
        failureCode: "externally-restored",
        failureMessage: "A window was restored outside Minimize; its owned activation override was cleared.",
        deferredError: ""
      })
    } else if (blockedRecords.length > 0 && !pendingAction) {
      lastOperation = "Owned window cleanup is waiting for a visible workspace."
      lastError = blockedRecords.length + " owned window"
        + (blockedRecords.length === 1 ? " is" : "s are")
        + " on an unsupported special workspace. Move "
        + (blockedRecords.length === 1 ? "it" : "them")
        + " to a normal workspace, then choose Reconcile; do not remove the plugin yet."
    } else if (!pendingAction
        && lastOperation === "Owned window cleanup is waiting for a visible workspace.") {
      lastOperation = "Live window state reconciled."
      lastError = ""
    }
    return root.statusObject()
  }

  function scheduleReconcile(eventName, eventData) {
    lastRawEvent = {
      name: String(eventName || "").slice(0, 128),
      data: String(eventData || "").slice(0, 1024)
    }
    // One restart per event, but one native refresh/reconcile per completed
    // burst. No timer repeats while idle.
    reconcileDebounce.restart()
  }

  function runScheduledReconcile() {
    if (testMode) {
      testRefreshCount++
    } else if (typeof Hyprland.refreshToplevels === "function") {
      Hyprland.refreshToplevels()
    }
    root.reconcileNow()
  }

  function appendCommand(step) {
    var log = testCommandLog.slice()
    log.push({
      kind: step.kind,
      operations: step.operations ? step.operations.slice() : [step.kind],
      argv: step.argv.slice(),
      lua: step.argv.length > 2 ? step.argv[2] : ""
    })
    testCommandLog = log
  }

  function startAction(action) {
    if (!stateReady || loadingState) return false
    pendingAction = action
    currentStep = null
    lastError = ""
    if (!root.persistState(true)) {
      pendingAction = null
      lastError = "The transition journal could not be saved; no compositor command was sent."
      return false
    }
    root.runNextStep()
    return true
  }

  function beginProtection(action) {
    var step = Transaction.ensureHiddenOverrideStep(action && action.record)
    if (!action || !step) {
      lastError = "Activation protection could not be validated; use Recovery before restoring this window."
      return false
    }
    action.stage = "recovery-protect"
    action.steps = [step]
    action.stepIndex = 0
    if (!root.hasRecordIdentity(supplementalRecords, action.record)) {
      var protectedRecords = supplementalRecords.slice()
      protectedRecords.push(action.record)
      supplementalRecords = protectedRecords
    }
    pendingAction = action
    currentStep = null
    lastOperation = "Confirming protection for a minimized window."
    lastError = ""
    if (!root.persistState(true)) {
      lastOperation = "Window protection still needs attention."
      lastError = "Protection could not be journaled, so no compositor command was sent; choose Reconcile to retry."
      operationFinished("protection-pending", false)
      return false
    }
    root.runNextStep()
    return true
  }

  function runNextStep() {
    if (!pendingAction || currentStep) return
    var steps = pendingAction.steps || []
    if (pendingAction.stepIndex >= steps.length) {
      root.stageCommandsFinished()
      return
    }
    var step = steps[pendingAction.stepIndex]
    if (!step || !step.argv) {
      root.finishFailure("invalid-command", "A validated compositor command could not be built.")
      return
    }
    currentStep = step
    if (testMode) {
      root.appendCommand(step)
      return
    }
    actionProc.command = step.argv
    actionProc.running = true
    processStartGuard.restart()
  }

  function semanticFailureMessage(reply) {
    var code = String(reply || "").trim()
    if (code.indexOf("REFUSE:MISSING") === 0) return "The exact window disappeared before Hyprland could change it."
    if (code.indexOf("REFUSE:STALE") === 0) return "The window address now belongs to a different live identity."
    if (code.indexOf("REFUSE:PINNED") === 0) return "The window became pinned before the transition."
    if (code.indexOf("REFUSE:GROUPED") === 0) return "The window joined a group before the transition."
    if (code.indexOf("REFUSE:SOURCE") === 0) return "The window moved away from its captured source workspace."
    if (code.indexOf("REFUSE:MEMBERSHIP") === 0) return "The window is no longer in a supported minimized workspace."
    if (code.indexOf("REFUSE:TARGET") === 0) return "The restored window did not remain on the requested workspace."
    if (code === "ERROR:MOVE_ROLLED_BACK")
      return "Hyprland rejected the move and the window was returned safely."
    if (code === "ERROR:MOVE_ROLLBACK_FAILED")
      return "Hyprland could not prove that the failed move was fully rolled back."
    if (code === "ERROR:LOST_AFTER_MOVE")
      return "The original window identity disappeared during the move; no replacement was targeted."
    if (code === "ERROR:FOCUS")
      return "The window was restored, but Hyprland did not confirm focus."
    if (code === "ERROR:UNSET" || code === "ERROR:FOCUS_AND_UNSET")
      return "The window moved, but its activation override could not be fully cleared."
    if (code.indexOf("ERROR:") === 0)
      return "Hyprland rejected part of the guarded transaction (" + code.slice(6) + ")."
    return "Hyprland did not confirm the guarded transaction: " + (code || "empty response")
  }

  function expectedReply(step, reply) {
    var expected = step && step.successReplies ? step.successReplies : []
    for (var i = 0; i < expected.length; i++)
      if (expected[i] === reply) return true
    return false
  }

  function handleCommandExit(exitCode, stdoutText, stderrText) {
    if (!pendingAction || !currentStep) return
    processStartGuard.stop()
    var action = pendingAction
    var step = currentStep
    currentStep = null
    var stdoutReply = String(stdoutText || "").trim()
    var stderrReply = String(stderrText || "").trim()
    var reply = stdoutReply || stderrReply
    if (exitCode !== 0) {
      root.handleStepFailure(action, step, Number(exitCode), stderrReply || stdoutReply)
      return
    }
    if (!/^(OK|REFUSE|ERROR):[A-Z][A-Z0-9_]*$/.test(reply)) {
      root.handleStepFailure(action, step, 0,
        "Hyprland returned a malformed guarded-transaction response.")
      return
    }
    if (!root.expectedReply(step, reply)) {
      if (reply === "ERROR:MOVE" && step.kind === "guarded-minimize") {
        action.overrideApplied = true
        pendingAction = action
        root.startRollback("command-failed", root.semanticFailureMessage(reply))
        return
      }
      if (reply === "ERROR:MOVE" && step.kind === "guarded-restore") {
        root.startRestoreResolution(action, root.semanticFailureMessage(reply))
        return
      }
      if (step.kind === "guarded-post-restore" && reply === "ERROR:FOCUS") {
        root.finishPartialFailure("restored-with-focus-error",
          root.semanticFailureMessage(reply), "Window restored, but focus was not confirmed.")
        return
      }
      if (step.kind === "guarded-post-restore" && reply.indexOf("REFUSE:") === 0) {
        root.finishPartialFailure("post-restore-refused",
          root.semanticFailureMessage(reply), "The window moved before final restore cleanup.")
        return
      }
      if (reply === "ERROR:MOVE_ROLLBACK_FAILED" && step.kind === "guarded-minimize"
          && root.sameLiveIdentity(action.record)) {
        root.startRollback("move-rollback-failed", root.semanticFailureMessage(reply))
        return
      }
      if (reply.indexOf("REFUSE:") === 0 || step.kind === "guarded-minimize") {
        root.finishFailure(reply.indexOf("REFUSE:") === 0
          ? "transaction-refused" : "command-failed", root.semanticFailureMessage(reply))
        return
      }
      root.handleStepFailure(action, step, 0, root.semanticFailureMessage(reply))
      return
    }
    if (step.kind === "resolve-minimize") {
      if (reply === "OK:MINIMIZED") root.beginProtection(action)
      else root.finishFailure("transition-timeout",
        "Hyprland did not confirm the minimize move; the activation override was removed.")
      return
    }
    if (step.kind === "guarded-minimize-rollback") {
      if (reply === "OK:MINIMIZED") root.beginProtection(action)
      else {
        action.stepIndex++
        pendingAction = action
        root.persistState(true)
        root.runNextStep()
      }
      return
    }
    if (step.kind === "resolve-restore") {
      if (reply === "OK:RESTORE_MOVED") {
        action.stage = "post-restore"
        action.steps = [Transaction.postRestoreStep(action.record, action.target,
          action.record.owned === true)]
        action.stepIndex = 0
        pendingAction = action
        root.persistState(true)
        root.runNextStep()
      } else {
        root.finishFailure(action.failureCode || "command-failed",
          action.failureMessage || "The restore move was rolled back safely.")
      }
      return
    }
    if (step.kind === "guarded-minimize") action.overrideApplied = true
    action.stepIndex++
    pendingAction = action
    root.persistState(true)
    root.runNextStep()
  }

  function handleStepFailure(action, step, exitCode, detail) {
    var suffix = String(detail || "").trim()
      ? " " + String(detail || "").trim() : ""
    var message = exitCode === 0 ? String(detail || "")
      : "Hyprland rejected " + step.kind + " (exit " + exitCode + ")." + suffix
    if (step.kind === "guarded-cleanup" || step.kind === "guarded-minimize-rollback"
        || step.kind === "guarded-ensure-hidden") {
      action.stage = step.kind === "guarded-ensure-hidden"
        ? "recovery-protect" : "recovery-cleanup"
      action.steps = [step.kind === "guarded-minimize-rollback"
        ? Transaction.rollbackMinimizeStep(action.record, action.target)
        : step.kind === "guarded-ensure-hidden"
          ? Transaction.ensureHiddenOverrideStep(action.record)
          : Transaction.cleanupStep(action.record, action.target)]
      action.stepIndex = 0
      pendingAction = action
      lastOperation = step.kind === "guarded-ensure-hidden"
        ? "Window protection still needs attention."
        : "Window cleanup still needs attention."
      lastError = message
      root.persistState(true)
      operationFinished("cleanup-pending", false)
      return
    }
    if (action.type === "minimize" && (action.overrideApplied
        || step.kind === "guarded-minimize")
        && root.sameLiveIdentity(action.record)) {
      root.startRollback("command-failed", message)
      return
    }
    if (action.stage === "post-restore" && action.record.owned === true
        && root.sameLiveIdentity(action.record)) {
      root.startRollback("restored-with-cleanup-error", message)
      return
    }
    root.finishFailure("command-failed", message)
  }

  function stageCommandsFinished() {
    var action = pendingAction
    if (!action) return
    if (action.stage === "initial" && action.type === "minimize") {
      action.stage = "confirm-minimize"
      pendingAction = action
      root.persistState(true)
      confirmationTimer.restart()
      root.reconcileNow()
      return
    }
    if (action.stage === "initial" && action.type === "restore") {
      action.stage = "post-restore"
      action.steps = [
        Transaction.postRestoreStep(action.record, action.target,
          action.record.owned === true)
      ]
      action.stepIndex = 0
      pendingAction = action
      root.persistState(true)
      root.runNextStep()
      return
    }
    if (action.stage === "post-restore") {
      if (action.deferredError)
        root.finishFailure("restored-with-focus-error", action.deferredError)
      else
        root.finishSuccess("restored", action.successMessage || "Window restored.")
      return
    }
    if (action.stage === "rollback") {
      root.finishFailure(action.failureCode || "rolled-back",
        action.failureMessage || "The minimize action was rolled back.")
      return
    }
    if (action.stage === "recovery-cleanup") {
      root.forgetSupplementalRecord(action.record)
      if (action.failureCode === "externally-restored")
        root.finishSuccess("external-restore-cleaned",
          action.failureMessage || "External restore cleanup completed.")
      else
        root.finishFailure(action.failureCode || "interrupted-transition",
          action.failureMessage || "An interrupted transition was safely cleaned up; retry the action.")
      return
    }
    if (action.stage === "recovery-protect") {
      root.finishAuthoritativeMinimize(action)
    }
  }

  function sameLiveIdentity(record) {
    var client = root.liveByAddress(record && record.address)
    return client ? Model.recordMatchesClient(record, client, instanceSignature) : false
  }

  function confirmPendingFromLive() {
    var action = pendingAction
    if (!action || (action.stage !== "confirm-minimize" && action.stage !== "confirm-restore"))
      return
    var client = root.liveByAddress(action.address)
    if (!client) return
    if (!Model.recordMatchesClient(action.record, client, instanceSignature)) {
      confirmationTimer.stop()
      root.finishFailure("identity-changed",
        "The original window disappeared; no further command was sent to its reused address.")
      return
    }

    if (action.stage === "confirm-minimize"
        && Model.workspaceName(client.workspace) === action.target) {
      confirmationTimer.stop()
      root.finishAuthoritativeMinimize(action)
      return
    }

    if (action.stage === "confirm-restore"
        && !Model.isCompatibleWorkspace(client.workspace)
        && Model.normalWorkspaceTarget(client.workspace) === action.target) {
      confirmationTimer.stop()
      action.stage = "post-restore"
      action.steps = [
        Transaction.postRestoreStep(action.record, action.target,
          action.record.owned === true)
      ]
      action.stepIndex = 0
      pendingAction = action
      root.persistState(true)
      root.runNextStep()
    }
  }

  function startRollback(code, message) {
    var action = pendingAction
    if (!action) return
    confirmationTimer.stop()
    action.stage = "rollback"
    action.failureCode = code
    action.failureMessage = message
    action.steps = [action.type === "minimize"
      ? Transaction.rollbackMinimizeStep(action.record, action.target)
      : Transaction.cleanupStep(action.record, action.target)]
    action.stepIndex = 0
    pendingAction = action
    root.persistState(true)
    root.runNextStep()
  }

  function startRestoreResolution(action, message) {
    confirmationTimer.stop()
    var resolver = Transaction.resolveRestoreStep(action.record, action.target)
    if (!resolver) {
      root.finishPartialFailure("restore-resolution-failed", message,
        "The restore move could not be resolved automatically.")
      return
    }
    action.stage = "restore-resolve"
    action.failureCode = "command-failed"
    action.failureMessage = message
    action.steps = [resolver]
    action.stepIndex = 0
    pendingAction = action
    root.persistState(true)
    root.runNextStep()
  }

  function expirePending() {
    if (!pendingAction) return
    root.reconcileNow()
    if (!pendingAction) return
    var action = pendingAction
    if (action.type === "minimize" && action.overrideApplied) {
      var resolver = Transaction.resolveMinimizeStep(action.record, action.target)
      if (!resolver) {
        root.finishFailure("transition-timeout",
          "The minimize transition timed out, but no safe resolver could be built.")
        return
      }
      action.stage = "timeout-resolve"
      action.steps = [resolver]
      action.stepIndex = 0
      pendingAction = action
      currentStep = null
      root.persistState(true)
      root.runNextStep()
      return
    }
    root.finishFailure("transition-timeout",
      "Hyprland did not confirm the exact window transition; no further window was targeted.")
  }

  function finishAuthoritativeMinimize(action) {
    confirmationTimer.stop()
    pendingAction = null
    currentStep = null
    var confirmed = JSON.parse(JSON.stringify(action.record))
    var live = root.liveByAddress(action.address)
    var liveWorkspace = live && Model.recordMatchesClient(action.record, live, instanceSignature)
      ? Model.workspaceName(live.workspace) : ""
    confirmed.sourceWorkspace = Model.isCompatibleWorkspace(liveWorkspace)
      ? liveWorkspace : action.target
    var next = []
    for (var i = 0; i < supplementalRecords.length; i++)
      if (!root.sameRecordIdentity(supplementalRecords[i], confirmed))
        next.push(supplementalRecords[i])
    next.push(confirmed)
    supplementalRecords = next
    loaded = true
    lastOperation = "Window minimized."
    lastError = ""
    root.persistState(true)
    root.reconcileNow()
    operationFinished("minimized", true)
    if (!testMode) root.scheduleReconcile("authoritative-minimize", confirmed.address)
  }

  function finishSuccess(code, message) {
    confirmationTimer.stop()
    var completed = pendingAction
    pendingAction = null
    currentStep = null
    if (code === "restored" && completed && completed.record) {
      var retained = []
      for (var i = 0; i < supplementalRecords.length; i++)
        if (!root.sameRecordIdentity(supplementalRecords[i], completed.record))
          retained.push(supplementalRecords[i])
      supplementalRecords = retained
    }
    lastOperation = message
    lastError = ""
    root.reconcileNow()
    operationFinished(code, true)
    root.continueRestoreQueue()
  }

  function finishFailure(code, message) {
    confirmationTimer.stop()
    pendingAction = null
    currentStep = null
    lastOperation = "No window was changed."
    lastError = message
    root.reconcileNow()
    operationFinished(code, false)
    restoreQueue = []
    restoreQueueTarget = null
  }

  function finishPartialFailure(code, message, operation) {
    confirmationTimer.stop()
    var completed = pendingAction
    pendingAction = null
    currentStep = null
    if (code === "restored-with-focus-error" && completed && completed.record) {
      var retained = []
      for (var i = 0; i < supplementalRecords.length; i++)
        if (!root.sameRecordIdentity(supplementalRecords[i], completed.record))
          retained.push(supplementalRecords[i])
      supplementalRecords = retained
    }
    lastOperation = String(operation || "The window changed, but the transition was incomplete.")
    lastError = message
    root.reconcileNow()
    operationFinished(code, false)
    restoreQueue = []
    restoreQueueTarget = null
  }

  function retryRecovery() {
    if (!pendingAction
        || (pendingAction.stage !== "recovery-cleanup"
          && pendingAction.stage !== "recovery-protect") || currentStep)
      return false
    lastError = ""
    if (!root.persistState(true)) {
      lastOperation = "Recovery still needs attention."
      lastError = "Recovery could not be journaled, so no compositor command was sent; choose Reconcile to retry."
      operationFinished("recovery-pending", false)
      return false
    }
    root.runNextStep()
    return true
  }

  function reconcileAndRetry() {
    root.reconcileNow()
    if (root.retryRecovery())
      return root.result(true, "recovery-retried", "Retrying the guarded recovery step.")
    if (pendingAction && (pendingAction.stage === "recovery-cleanup"
        || pendingAction.stage === "recovery-protect"))
      return root.result(false, "recovery-pending",
        lastError || "Recovery is still running; wait, then choose Reconcile again.")
    if (!pendingAction && unresolvedOwnedCount === 0) {
      lastOperation = "Live window state reconciled."
      lastError = ""
    }
    return root.result(true, "reconciled", "Minimized windows reconciled with live state.")
  }

  function prepareRemoval() {
    if (!stateReady || loadingState)
      return root.result(false, "state-loading",
        "Minimize state is still loading; no removal drain was started.")
    if (removalDrain)
      return root.result(false, "removal-already-draining",
        "Another removal attempt already owns the drain; finish or explicitly cancel that attempt first.", {
          removalDrain: true,
          busy: busy
        })
    if (busy)
      return root.result(false, "busy",
        "A window transition is still in progress; wait for it, then retry removal.")
    if (shortcutMutationActive)
      return root.result(false, "shortcut-busy",
        "A shortcut change is still running; wait for it, then retry removal.")
    var previousRemovalDrain = removalDrain
    removalDrain = true
    lastOperation = "Removal drain active; new minimizes are disabled."
    lastError = ""
    if (!root.persistState(true)) {
      removalDrain = previousRemovalDrain
      lastOperation = "Removal drain was not started."
      lastError = "The removal drain could not be journaled; no removal action is safe yet."
      return root.result(false, "state-write-failed", lastError)
    }
    root.reconcileNow()
    return root.result(true, "removal-draining",
      "Removal drain active; new minimizes are disabled.", {
        removalDrain: true,
        busy: busy
      })
  }

  function cancelRemoval() {
    removalDrain = false
    lastOperation = "Removal drain cancelled."
    lastError = ""
    if (!root.persistState(true)) {
      removalDrain = true
      lastOperation = "Removal drain is still active."
      lastError = "The removal-drain cancellation could not be journaled; retry or end this compositor session."
      return root.result(false, "state-write-failed", lastError)
    }
    return root.result(true, "removal-cancelled",
      "Removal drain cancelled; minimizing is available again.")
  }

  function minimize() {
    if (!stateReady || loadingState)
      return root.result(false, "state-loading", "Minimize state is still loading; try again shortly.")
    if (removalDrain)
      return root.result(false, "removal-draining",
        "Removal preparation is active; finish removal or cancel it before minimizing.")
    if (shortcutMutationActive)
      return root.result(false, "shortcut-busy",
        "A shortcut change is still running; wait before minimizing a window.")
    if (busy) return root.result(false, "busy", "Another window transition is still in progress.")
    var planned = Model.planMinimize(root.activeClient(), instanceSignature, Date.now())
    if (!planned.ok) return planned
    var step = Transaction.minimizeStep(planned.record, planned.destination)
    if (!step)
      return root.result(false, "invalid-command", "The compositor command could not be validated.")
    if (!root.startAction({
      type: "minimize",
      stage: "initial",
      address: planned.address,
      record: planned.record,
      target: planned.destination,
      steps: [step],
      stepIndex: 0,
      overrideApplied: false,
      deferredError: ""
    })) return root.result(false, "state-write-failed", lastError)
    return root.result(true, "queued", "Minimizing window.", { address: planned.address })
  }

  function restoreAddress(address, workspace, originRequested, fromQueue) {
    if (!stateReady || loadingState)
      return root.result(false, "state-loading", "Minimize state is still loading; try again shortly.")
    if (shortcutMutationActive)
      return root.result(false, "shortcut-busy",
        "A shortcut change is still running; wait before restoring a window.")
    if (busy) return root.result(false, "busy", "Another window transition is still in progress.")
    var normalized = Model.normalizeAddress(address)
    if (!normalized) return root.result(false, "invalid-address", "The requested window address is invalid.")
    var record = root.entryByAddress(normalized)
    if (!record) return root.result(false, "not-minimized", "That window is no longer minimized.")
    var client = root.liveByAddress(normalized)
    if (!client || !Model.recordMatchesClient(record, client, instanceSignature)) {
      root.reconcileNow()
      return root.result(false, "stale-window", "The saved entry no longer identifies the same live window.")
    }
    var normalizedClient = Model.normalizeClient(client)
    if (normalizedClient.pinned)
      return root.result(false, "pinned-window", "Unpin this window before restoring it.")
    if (normalizedClient.grouped)
      return root.result(false, "grouped-window", "Remove this window from its group before restoring it.")

    var panelFallback = workspace === undefined || workspace === null || String(workspace) === ""
      ? null : workspace
    var fallback = Model.normalWorkspaceTarget(panelFallback)
      ? panelFallback : root.focusedWorkspace()
    var planned = Model.planRestore(record, fallback, originRequested === true,
      root.availableWorkspaces())
    if (!planned.ok) return planned
    var resolvedTarget = root.resolveLiveRestoreTarget(planned.target)
    if (!resolvedTarget.ok)
      return root.result(false, "no-visible-workspace", resolvedTarget.reason)
    if (resolvedTarget.fallback) {
      planned.target = resolvedTarget.target
      planned.usedOrigin = false
      planned.reason = originRequested === true
        ? "Original workspace is unavailable; restoring to the current workspace instead."
        : resolvedTarget.reason
    }
    var step = Transaction.restoreMoveStep(record, planned.target)
    if (!step) return root.result(false, "invalid-target", "The restore workspace is invalid.")
    if (!root.startAction({
      type: "restore",
      stage: "initial",
      address: normalized,
      record: record,
      target: planned.target,
      steps: [step],
      stepIndex: 0,
      overrideApplied: record.owned === true,
      successMessage: planned.reason || "Window restored.",
      fromQueue: fromQueue === true,
      deferredError: ""
    })) return root.result(false, "state-write-failed", lastError)
    return root.result(true, "queued", planned.reason || "Restoring window.", {
      address: normalized,
      target: planned.target,
      usedOrigin: planned.usedOrigin
    })
  }

  function restore(address, workspace) {
    return root.restoreAddress(address, workspace, true, false)
  }

  function restoreOrigin(address, fallbackWorkspace) {
    return root.restore(address, fallbackWorkspace)
  }

  function restoreHere(address, workspace) {
    return root.restoreAddress(address, workspace, false, false)
  }

  function restoreLast(workspace) {
    if (busy) return root.result(false, "busy", "Another window transition is still in progress.")
    if (entries.length === 0) return root.result(false, "empty", "There are no minimized windows.")
    var latest = entries[0]
    for (var i = 1; i < entries.length; i++)
      if (Number(entries[i].minimizedAt) > Number(latest.minimizedAt)) latest = entries[i]
    var target = workspace === undefined || workspace === null ? root.focusedWorkspace() : workspace
    return root.restore(latest.address, target)
  }

  function restoreAll(workspace) {
    if (!stateReady || loadingState)
      return root.result(false, "state-loading", "Minimize state is still loading; try again shortly.")
    if (shortcutMutationActive)
      return root.result(false, "shortcut-busy",
        "A shortcut change is still running; wait before restoring windows.")
    if (busy) return root.result(false, "busy", "Another window transition is still in progress.")
    if (entries.length === 0) return root.result(true, "empty", "There are no minimized windows.", { count: 0 })
    var target = workspace === undefined || workspace === null ? root.focusedWorkspace() : workspace
    var resolvedTarget = root.resolveLiveRestoreTarget(target)
    if (!resolvedTarget.ok)
      return root.result(false, "no-visible-workspace", resolvedTarget.reason)
    var queue = []
    for (var i = 0; i < entries.length; i++) queue.push(entries[i].address)
    restoreQueue = queue
    restoreQueueTarget = root.workspaceSnapshot(resolvedTarget.target)
    root.continueRestoreQueue()
    return root.result(true, "queued-all", resolvedTarget.fallback
      ? "The requested workspace disappeared; restoring " + queue.length + " windows here instead."
      : "Restoring " + queue.length + " windows.", {
      count: queue.length
    })
  }

  function continueRestoreQueue() {
    if (busy) return
    if (restoreQueue.length === 0) {
      restoreQueueTarget = null
      return
    }
    var queue = restoreQueue.slice()
    var address = queue.shift()
    restoreQueue = queue
    var response = root.restoreAddress(address, restoreQueueTarget, false, true)
    if (!response.ok) {
      lastError = response.message
      restoreQueue = []
      restoreQueueTarget = null
    }
  }

  function acknowledge(address) {
    if (!stateReady || loadingState)
      return root.result(false, "state-loading", "Minimize state is still loading; try again shortly.")
    var normalized = Model.normalizeAddress(address)
    if (!normalized) return root.result(false, "invalid-address", "The requested window address is invalid.")
    var next = []
    var found = false
    for (var i = 0; i < supplementalRecords.length; i++) {
      if (supplementalRecords[i].address === normalized) {
        next.push(Model.acknowledge(supplementalRecords[i]))
        found = true
      } else {
        next.push(supplementalRecords[i])
      }
    }
    if (!found) return root.result(false, "not-minimized", "That window is no longer minimized.")
    supplementalRecords = next
    root.reconcileNow()
    return root.result(true, "acknowledged", "Attention marker cleared.", { address: normalized })
  }

  function testCompleteCommand(exitCode, detail) {
    if (!testMode || !currentStep)
      return root.result(false, "no-test-command", "No simulated command is pending.")
    root.handleCommandExit(Number(exitCode), String(detail || ""))
    return root.result(true, "test-command-complete", "Simulated command completed.")
  }

  function testExpirePending() {
    root.expirePending()
    return root.statusObject()
  }

  function testCompleteShortcut(exitCode, stdoutText, stderrText) {
    if (!testMode || !shortcutBusy)
      return root.result(false, "no-test-shortcut", "No simulated shortcut command is pending.")
    root.finishShortcutProcess(Number(exitCode), String(stdoutText || ""), String(stderrText || ""))
    return root.result(true, "test-shortcut-complete", "Simulated shortcut command completed.")
  }

  FileView {
    id: stateFile
    path: root.testMode ? "" : root.statePath
    watchChanges: false
    blockWrites: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.resolveStateLoad(text())
    onLoadFailed: root.resolveStateLoad("")
    onSaveFailed: root.stateSaveFailed = true
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.handleCommandExit(Number(exitCode), String(actionStdout.text || ""),
        String(actionStderr.text || ""))
    }
  }

  Process {
    id: shortcutProc
    stdout: StdioCollector { id: shortcutStdout; waitForEnd: true }
    stderr: StdioCollector { id: shortcutStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishShortcutProcess(Number(exitCode), String(shortcutStdout.text || ""),
        String(shortcutStderr.text || ""))
    }
  }

  Timer {
    id: processStartGuard
    interval: 250
    repeat: false
    onTriggered: {
      if (root.currentStep && !actionProc.running)
        root.handleCommandExit(127, "", "hyprctl could not be started")
    }
  }

  Timer {
    id: shortcutProcessStartGuard
    interval: 250
    repeat: false
    onTriggered: {
      if (root.shortcutBusy && root.shortcutPendingKind && !shortcutProc.running)
        root.finishShortcutProcess(127, "", "Shortcut helper could not be started.")
    }
  }

  Timer {
    id: confirmationTimer
    interval: Math.max(500, root.transitionTimeoutMs)
    repeat: false
    onTriggered: root.expirePending()
  }

  Timer {
    id: reconcileDebounce
    interval: 40
    repeat: false
    onTriggered: root.runScheduledReconcile()
  }

  Connections {
    target: root.testMode ? null : Hyprland
    enabled: !root.testMode
    function onRawEvent(event) {
      // HyprlandEvent is reused by Quickshell, so copy both fields now.
      var name = String(event && event.name || "")
      var data = String(event && event.data || "")
      root.scheduleReconcile(name, data)
    }
  }

  IpcHandler {
    target: "osouthgate.minimize"

    function status(): string { return root.statusJson() }
    function minimize(): string { return JSON.stringify(root.minimize()) }
    function restore(address: string): string { return JSON.stringify(root.restore(address)) }
    function restoreOrigin(address: string): string { return JSON.stringify(root.restoreOrigin(address)) }
    function restoreHere(address: string): string { return JSON.stringify(root.restoreHere(address)) }
    function restoreLast(): string { return JSON.stringify(root.restoreLast()) }
    function restoreAll(): string { return JSON.stringify(root.restoreAll()) }
    function acknowledge(address: string): string { return JSON.stringify(root.acknowledge(address)) }
    function reconcile(): string {
      return JSON.stringify(root.reconcileAndRetry())
    }
    function prepareRemoval(): string { return JSON.stringify(root.prepareRemoval()) }
    function cancelRemoval(): string { return JSON.stringify(root.cancelRemoval()) }
  }

  Component.onCompleted: {
    if (testMode) {
      stateReady = true
      loadingState = false
      root.reconcileNow()
    } else if (!statePath) {
      root.initializeEmptyState("The compositor runtime directory is unavailable; window transitions are disabled.")
    }
  }
}
