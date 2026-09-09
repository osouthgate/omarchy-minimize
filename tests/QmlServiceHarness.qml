import QtQuick
import Quickshell

ShellRoot {
  id: harness

  property int step: 0
  property bool failed: false
  property int burstRefreshBaseline: 0
  property int burstReconcileBaseline: 0
  property int idleRefreshBaseline: 0
  property int idleReconcileBaseline: 0
  property var shortcutSignals: []

  function client(address, workspace, pid, title, urgent) {
    return {
      address: address,
      workspace: {
        id: workspace.indexOf("special:") === 0 ? -99 : Number(workspace),
        name: workspace
      },
      monitor: 0,
      pid: pid,
      stableId: Number(pid).toString(16),
      class: "foot",
      initialClass: "foot",
      title: title,
      initialTitle: "Fixture",
      urgent: urgent === true,
      pinned: false,
      grouped: []
    }
  }

  function expect(condition, message) {
    if (condition || failed) return
    failed = true
    console.warn("OMARCHY_MINIMIZE_SERVICE_ERROR " + message)
  }

  function operations() {
    var result = []
    for (var i = 0; i < service.testCommandLog.length; i++) {
      var values = service.testCommandLog[i].operations || [service.testCommandLog[i].kind]
      for (var j = 0; j < values.length; j++) result.push(values[j])
    }
    return result.join(">")
  }

  function persisted() {
    return JSON.parse(service.testPersistedText)
  }

  function ownedRecord(liveClient, origin) {
    return {
      address: liveClient.address,
      instanceSignature: "test-instance",
      pid: liveClient.pid,
      compositorStableId: String(liveClient.stableId).toLowerCase(),
      stableId: String(liveClient.stableId).toLowerCase(),
      initialIdentity: "foot\u001fFixture",
      initialClass: "foot",
      initialTitle: "Fixture",
      className: "foot",
      title: liveClient.title,
      baselineTitle: liveClient.title,
      sourceWorkspace: liveClient.workspace.name,
      origin: String(origin || "2"),
      monitor: liveClient.monitor,
      minimizedAt: liveClient.pid,
      attention: "none",
      owned: true,
      recovered: false
    }
  }

  function stateText(records, pending) {
    return JSON.stringify({
      schemaVersion: 2,
      instanceSignature: "test-instance",
      records: records || [],
      pending: pending || null
    })
  }

  function loadOwned(liveClients, origins) {
    var records = []
    var originValues = origins || []
    service.testStateWriteFailure = false
    service.testCommandLog = []
    service.restoreQueue = []
    service.restoreQueueTarget = null
    service.testClients = liveClients
    service.testActiveClient = null
    for (var i = 0; i < liveClients.length; i++)
      records.push(ownedRecord(liveClients[i], originValues[i] || "2"))
    service.loadStateText(stateText(records, null))
  }

  function advance() {
    if (failed) return
    var response
    var normal
    var hidden

    if (step === 0) {
      normal = client("0x1001", "2", 4101, "Build running", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.testWorkspaces = [{ id: 2, name: "2" }, { id: 7, name: "7" }]
      service.testFocusedWorkspace = { id: 7, name: "7" }
      service.reconcileNow()
      response = service.minimize()
      expect(response.ok && response.code === "queued", "minimize was not queued")
      expect(service.entries.length === 0, "row published before live membership")
      expect(operations() === "set-override>move", "guarded minimize order is wrong")
      expect(persisted().pending && persisted().pending.type === "minimize",
        "minimize command started without a persisted journal")
      expect(persisted().records.length === 0, "unconfirmed minimize leaked into saved rows")
      expect(service.testCommandLog[0].argv[1] === "repl"
        && service.testCommandLog[0].lua.indexOf("follow=false") !== -1,
        "minimize is not a guarded silent repl transaction")
      expect(service.testCommandLog[0].lua.indexOf("Build running") === -1,
        "window-controlled title entered Lua source")
    } else if (step === 1) {
      service.testCompleteCommand(0, "OK:MINIMIZED")
      expect(service.pendingAction && service.pendingAction.stage === "confirm-minimize",
        "minimize did not wait for live confirmation")
      hidden = client("0x1001", "special:minimum", 4101, "Build running", false)
      service.testClients = [hidden]
      service.testActiveClient = hidden
      service.reconcileNow()
      expect(service.entries.length === 1 && service.pendingAction === null,
        "confirmed minimum window was not published")
      expect(service.entries[0].origin === "2" && service.entries[0].owned === true,
        "owned origin metadata was not retained")
      expect(persisted().pending === null && persisted().records.length === 1,
        "terminal minimize state did not clear its journal")
      console.info("OMARCHY_MINIMIZE_MINIMIZE_ORDER " + operations())
    } else if (step === 2) {
      response = service.restore("0x1001", "7")
      expect(response.ok && response.target === "2" && response.usedOrigin === true,
        "normal restore did not prefer the remembered workspace 2")
      expect(operations() === "set-override>move>move", "restore did not begin with move")
      service.testCompleteCommand(0, "OK:RESTORE_MOVED")
      normal = client("0x1001", "2", 4101, "Build finished", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.reconcileNow()
      expect(operations() === "set-override>move>move>focus>unset-override",
        "focus/unset ran before move confirmation or in the wrong order")
    } else if (step === 3) {
      service.testCompleteCommand(0, "OK:RESTORED")
      expect(service.pendingAction === null && service.entries.length === 0,
        "restore did not finish cleanly")
      expect(operations() === "set-override>move>move>focus>unset-override",
        "complete transaction order is wrong: " + operations())
      console.info("OMARCHY_MINIMIZE_RESTORE_ORDER " + operations())
    } else if (step === 4) {
      var minimum = client("0x2001", "special:minimum", 4201, "One", false)
      var dock = client("0x2002", "special:minimized", 4202, "Two", false)
      var scratch = client("0x2003", "special:scratchpad", 4203, "Three", false)
      var unrelated = client("0x2004", "special:dropterm", 4204, "Four", false)
      service.testClients = [minimum, dock, scratch, unrelated]
      service.testActiveClient = null
      service.reconcileNow()
      expect(service.entries.length === 3, "compatible live aliases were not adopted exactly")
      var allExternal = true
      for (var i = 0; i < service.entries.length; i++)
        if (service.entries[i].owned === true) allExternal = false
      expect(allExternal, "external aliases were incorrectly claimed as owned")
      console.info("OMARCHY_MINIMIZE_ADOPTED " + service.entries.length)
    } else if (step === 5) {
      response = service.loadStateText("{not-json")
      expect(!response.ok && response.code === "invalid-state", "corrupt state was not ignored")
      response = service.loadStateText(JSON.stringify({
        schemaVersion: 1,
        instanceSignature: "other-instance",
        records: [{ address: "0x2001" }]
      }))
      expect(!response.ok && response.code === "state-mismatch", "instance mismatch was not ignored")
      service.testClients = []
      service.reconcileNow()
      expect(service.entries.length === 0, "closed live clients left stale rows")
      console.info("OMARCHY_MINIMIZE_STALE_CLEAN count=0")
    } else if (step === 6) {
      normal = client("0x5001", "3", 4501, "Timeout", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.testFocusedWorkspace = { id: 3, name: "3" }
      service.testWorkspaces = [{ id: 3, name: "3" }]
      service.testCommandLog = []
      response = service.minimize()
      expect(response.ok, "timeout fixture did not queue")
      response = service.minimize()
      expect(!response.ok && response.code === "busy", "concurrent request was not refused")
      service.testCompleteCommand(0, "OK:MINIMIZED")
      service.testExpirePending()
      expect(operations() === "set-override>move>resolve-timeout"
        && service.testCommandLog[1].lua.indexOf("value=\"unset\"") !== -1,
        "timeout did not queue a compositor-authoritative resolver")
      service.testCompleteCommand(0, "OK:ROLLED_BACK")
      expect(service.pendingAction === null && service.entries.length === 0,
        "rollback left pending state or a stale row")
      console.info("OMARCHY_MINIMIZE_ROLLBACK " + operations())
    } else if (step === 7) {
      var oldLive = client("0x6001", "special:minimum", 4601, "Old", false)
      service.testClients = [oldLive]
      service.testActiveClient = oldLive
      service.loadStateText(JSON.stringify({
        schemaVersion: 2,
        instanceSignature: "test-instance",
        records: [{
          address: "0x6001",
          instanceSignature: "test-instance",
          pid: 4601,
          compositorStableId: "11f9",
          stableId: "11f9",
          initialIdentity: "foot\u001fFixture",
          initialClass: "foot",
          initialTitle: "Fixture",
          className: "foot",
          title: "Old",
          baselineTitle: "Old",
          sourceWorkspace: "special:minimum",
          origin: "2",
          monitor: 0,
          minimizedAt: 1,
          attention: "none",
          owned: true,
          recovered: false
        }],
        pending: null
      }))
      expect(service.entries.length === 1 && service.entries[0].owned === true,
        "old fixture record was not established before address reuse")
      var reused = client("0x6001", "special:minimum", 9999, "New process", false)
      service.testClients = [reused]
      service.testActiveClient = reused
      service.reconcileNow()
      expect(service.entries.length === 1 && service.entries[0].pid === 9999,
        "reused address did not adopt the live identity")
      expect(service.entries[0].owned === false && service.entries[0].recovered === true,
        "reused address retained stale ownership")
      console.info("OMARCHY_MINIMIZE_ADDRESS_REUSE safe")
    } else if (step === 8) {
      normal = client("0x7001", "4", 4701, "Recover", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.testWorkspaces = [{ id: 4, name: "4" }]
      service.testFocusedWorkspace = { id: 4, name: "4" }
      service.reconcileNow()
      service.testCommandLog = []
      response = service.minimize()
      expect(response.ok, "recovery fixture did not queue")
      service.testCompleteCommand(0, "OK:MINIMIZED")
      var interruptedState = service.testPersistedText
      hidden = client("0x7001", "special:minimum", 4701, "Recover", false)
      service.testClients = [hidden]
      service.testActiveClient = hidden
      service.testCommandLog = []
      service.loadStateText(interruptedState)
      expect(service.pendingAction && service.pendingAction.stage === "recovery-protect"
        && operations() === "set-override",
        "hot-reload journal did not guard uncertain activation protection")
      expect(service.entries.length === 0,
        "hot-reload published ownership before activation protection")
      service.testCompleteCommand(0, "OK:PROTECTED")
      expect(service.pendingAction === null && service.entries.length === 1
        && service.entries[0].owned === true,
        "hot-reload protection did not publish the recovered minimize")
      console.info("OMARCHY_MINIMIZE_RELOAD_RECOVERY protection=set-override owned=1")
    } else if (step === 9) {
      normal = client("0x7001", "4", 4701, "Recover", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.testCommandLog = []
      service.reconcileNow()
      expect(service.pendingAction && service.pendingAction.stage === "recovery-cleanup"
        && operations() === "unset-override",
        "manual move-out did not queue exact-identity override cleanup")
      service.testCompleteCommand(0, "OK:CLEANED")
      expect(service.pendingAction === null && service.entries.length === 0,
        "manual move-out cleanup left a stale row")
      console.info("OMARCHY_MINIMIZE_MANUAL_MOVE_CLEANUP safe")
    } else if (step === 10) {
      normal = client("0x8001", "5", 4801, "Refusal", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.testWorkspaces = [{ id: 5, name: "5" }]
      service.testFocusedWorkspace = { id: 5, name: "5" }
      service.reconcileNow()
      service.testCommandLog = []
      response = service.minimize()
      expect(response.ok, "semantic-refusal fixture did not queue")
      service.testCompleteCommand(0, "REFUSE:STALE")
      expect(service.pendingAction === null && service.entries.length === 0,
        "exit-zero semantic refusal was mistaken for success")
      expect(operations() === "set-override>move", "semantic refusal triggered an unsafe cleanup")
      console.info("OMARCHY_MINIMIZE_SEMANTIC_REFUSAL safe")
    } else if (step === 11) {
      normal = client("0x9001", "6", 4901, "Save guard", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.testWorkspaces = [{ id: 6, name: "6" }]
      service.testFocusedWorkspace = { id: 6, name: "6" }
      service.reconcileNow()
      service.testCommandLog = []
      service.testStateWriteFailure = true
      response = service.minimize()
      expect(!response.ok && response.code === "state-write-failed",
        "journal write failure did not refuse the transition")
      expect(service.testCommandLog.length === 0 && service.pendingAction === null,
        "a compositor command escaped the failed write-ahead guard")
      service.testStateWriteFailure = false
      service.stateReady = false
      service.loadingState = true
      response = service.minimize()
      expect(!response.ok && response.code === "state-loading",
        "mutation was not gated while state loaded")
      service.loadStateText("")
      console.info("OMARCHY_MINIMIZE_WRITE_AHEAD_GUARD safe")
    } else if (step === 12) {
      normal = client("0xa001", "6", 5001, "Transport", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.testCommandLog = []
      response = service.minimize()
      expect(response.ok, "transport-failure fixture did not queue")
      service.testCompleteCommand(9, "hyprctl transport failed")
      expect(operations() === "set-override>move>rollback-move>unset-override",
        "transport failure did not queue guarded cleanup")
      service.testCompleteCommand(0, "OK:ROLLED_BACK")
      expect(service.pendingAction === null && service.entries.length === 0,
        "transport rollback left pending state")
      console.info("OMARCHY_MINIMIZE_COMMAND_ROLLBACK safe")
    } else if (step === 13) {
      service.testClients = []
      service.testActiveClient = null
      service.loadStateText(stateText([], null))
      service.testCommandLog = []
      burstRefreshBaseline = service.testRefreshCount
      burstReconcileBaseline = service.testReconcileCount
      for (var eventIndex = 0; eventIndex < 1000; eventIndex++)
        service.scheduleReconcile("synthetic-" + eventIndex, "payload-" + eventIndex)
      step++
      debounceCheck.restart()
      return
    } else if (step === 14) {
      var firstHidden = client("0xb001", "special:minimum", 5101, "First owned", false)
      var secondHidden = client("0xb002", "special:minimized", 5102, "Second owned", false)
      service.testWorkspaces = [{ id: 7, name: "7" }]
      service.testFocusedWorkspace = { id: 7, name: "7" }
      loadOwned([firstHidden, secondHidden], ["2", "4"])
      expect(service.entries.length === 2, "two owned cleanup fixtures were not established")
      service.testCommandLog = []
      service.testClients = [
        client("0xb001", "7", 5101, "First owned", false),
        client("0xb002", "7", 5102, "Second owned", false)
      ]
      service.reconcileNow()
      expect(service.pendingAction && service.pendingAction.stage === "recovery-cleanup"
        && service.pendingAction.address === "0xb001",
        "first externally restored owned window did not enter cleanup")
      expect(service.unresolvedOwnedCount === 2 && persisted().records.length === 2,
        "simultaneous external restores lost durable ownership")
    } else if (step === 15) {
      service.testCompleteCommand(0, "OK:CLEANED")
      expect(service.pendingAction && service.pendingAction.stage === "recovery-cleanup"
        && service.pendingAction.address === "0xb002",
        "second externally restored owned window was not drained")
      expect(service.unresolvedOwnedCount === 1 && persisted().records.length === 1,
        "first cleanup did not retain exactly the unresolved second record")
    } else if (step === 16) {
      service.testCompleteCommand(0, "OK:CLEANED")
      expect(service.pendingAction === null && service.entries.length === 0
        && service.unresolvedOwnedCount === 0 && persisted().records.length === 0,
        "two-window cleanup left stale actionable or owned state")
      expect(operations() === "unset-override>unset-override",
        "two-window cleanup did not issue one exact cleanup per identity")
      console.info("OMARCHY_MINIMIZE_MULTI_EXTERNAL_CLEANUP count=2")
    } else if (step === 17) {
      var raceHidden = client("0xc003", "special:minimum", 5203, "Cleanup race", false)
      loadOwned([raceHidden], ["2"])
      service.testCommandLog = []
      service.testClients = [client("0xc003", "7", 5203, "Cleanup race", false)]
      service.reconcileNow()
      expect(service.pendingAction && service.pendingAction.stage === "recovery-cleanup",
        "cleanup-race fixture did not queue")
      var cleanupLua = service.testCommandLog[0].lua
      expect(cleanupLua.indexOf("REFUSE:TARGET") >= 0
        && cleanupLua.indexOf("REFUSE:TARGET") < cleanupLua.indexOf("value=\"unset\""),
        "cleanup command did not guard workspace before unsetting")
      service.testClients = [raceHidden]
      service.testCompleteCommand(0, "REFUSE:TARGET")
      expect(service.pendingAction === null && service.entries.length === 1
        && service.entries[0].owned === true && persisted().records.length === 1,
        "cleanup race removed protection or lost the hidden owned record")
      console.info("OMARCHY_MINIMIZE_CLEANUP_RACE hidden-owned-retained=1")
    } else if (step === 18) {
      var retryHidden = client("0xd004", "special:minimum", 5304, "Cleanup retry", false)
      loadOwned([retryHidden], ["2"])
      service.testCommandLog = []
      service.testClients = [client("0xd004", "7", 5304, "Cleanup retry", false)]
      service.reconcileNow()
      service.testCompleteCommand(9, "synthetic cleanup failure")
      expect(service.pendingAction && service.pendingAction.stage === "recovery-cleanup"
        && service.currentStep === null && persisted().pending
        && persisted().pending.stage === "recovery-cleanup",
        "cleanup failure did not retain a retryable journal")
      response = service.reconcileAndRetry()
      expect(response.ok && response.code === "recovery-retried"
        && service.testCommandLog.length === 2,
        "reconcile did not retry the exact guarded cleanup")
      service.testCompleteCommand(0, "OK:CLEANED")
      expect(service.pendingAction === null && service.unresolvedOwnedCount === 0
        && persisted().records.length === 0,
        "successful cleanup retry left durable ownership")
      console.info("OMARCHY_MINIMIZE_CLEANUP_RETRY attempts=2")
    } else if (step === 19) {
      var writeHidden = client("0xe005", "special:minimum", 5405, "Cleanup write guard", false)
      loadOwned([writeHidden], ["2"])
      service.testCommandLog = []
      service.testStateWriteFailure = true
      service.testClients = [client("0xe005", "7", 5405, "Cleanup write guard", false)]
      service.reconcileNow()
      expect(service.pendingAction === null && service.testCommandLog.length === 0
        && service.unresolvedOwnedCount === 1 && service.supplementalRecords.length === 1,
        "failed cleanup journal either sent a command or discarded ownership")
      service.testStateWriteFailure = false
      service.reconcileNow()
      expect(service.pendingAction && service.pendingAction.stage === "recovery-cleanup"
        && service.testCommandLog.length === 1,
        "cleanup did not resume after journal writes recovered")
      service.testCompleteCommand(0, "OK:CLEANED")
      expect(service.pendingAction === null && service.unresolvedOwnedCount === 0,
        "write-guarded cleanup left unresolved ownership")
      console.info("OMARCHY_MINIMIZE_CLEANUP_WRITE_GUARD safe")
    } else if (step === 20) {
      var originHidden = client("0xf006", "special:minimum", 5506, "Lost monitor", false)
      service.testWorkspaces = [{ id: 3, name: "3" }]
      service.testFocusedWorkspace = { id: 3, name: "3" }
      loadOwned([originHidden], ["8"])
      response = service.restoreOrigin("0xf006", { id: 3, name: "3" })
      expect(response.ok && response.target === "3" && response.usedOrigin === false
        && response.message.indexOf("unavailable") >= 0,
        "missing monitor origin did not fall back visibly to the live workspace")
      service.testCompleteCommand(0, "OK:RESTORE_MOVED")
      service.testClients = [client("0xf006", "3", 5506, "Lost monitor", false)]
      service.testCompleteCommand(0, "OK:RESTORED")
      expect(operations() === "move>focus>unset-override"
        && service.pendingAction === null && service.entries.length === 0,
        "monitor-origin fallback did not finish move, focus, and cleanup")
      console.info("OMARCHY_MINIMIZE_MONITOR_FALLBACK target=3")
    } else if (step === 21) {
      normal = client("0x11007", "2", 5607, "Pending minimize", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.testWorkspaces = [{ id: 2, name: "2" }]
      service.testFocusedWorkspace = { id: 2, name: "2" }
      service.loadStateText(stateText([], null))
      service.testCommandLog = []
      response = service.minimize()
      expect(response.ok, "pending-minimize interleaving did not queue")
      hidden = client("0x11007", "special:minimum", 5607, "Pending minimize", false)
      service.testClients = [hidden]
      service.testActiveClient = hidden
      service.reconcileNow()
      expect(service.entries.length === 0 && service.supplementalRecords.length === 0,
        "pending minimize promoted unproven ownership")
      service.testCompleteCommand(0, "REFUSE:SOURCE")
      expect(service.pendingAction === null && service.entries.length === 1
        && service.entries[0].owned === false && persisted().records.length === 0,
        "refused pending minimize did not adopt the external move safely")
      console.info("OMARCHY_MINIMIZE_PENDING_MINIMIZE external-owned=0")
    } else if (step === 22) {
      var restoreHidden = client("0x12008", "special:minimum", 5708, "Pending restore", false)
      service.testWorkspaces = [{ id: 7, name: "7" }]
      service.testFocusedWorkspace = { id: 7, name: "7" }
      loadOwned([restoreHidden], ["2"])
      response = service.restore("0x12008", { id: 7, name: "7" })
      expect(response.ok, "pending-restore interleaving did not queue")
      service.testClients = [client("0x12008", "7", 5708, "Pending restore", false)]
      service.reconcileNow()
      expect(service.entries.length === 0 && service.supplementalRecords.length === 1,
        "pending restore discarded cleanup ownership")
      service.testCompleteCommand(0, "REFUSE:MEMBERSHIP")
      expect(service.pendingAction && service.pendingAction.stage === "recovery-cleanup"
        && operations() === "move>unset-override",
        "refused pending restore did not transition to guarded cleanup")
      service.testCompleteCommand(0, "OK:CLEANED")
      expect(service.pendingAction === null && service.entries.length === 0
        && service.unresolvedOwnedCount === 0 && persisted().records.length === 0,
        "pending restore cleanup left stale state")
      console.info("OMARCHY_MINIMIZE_PENDING_RESTORE cleanup=1")
    } else if (step === 23) {
      var closeHidden = client("0x13009", "special:minimum", 5809, "Hidden close", false)
      loadOwned([closeHidden], ["2"])
      service.testCommandLog = []
      service.testClients = []
      service.reconcileNow()
      expect(service.pendingAction === null && service.entries.length === 0
        && service.supplementalRecords.length === 0 && persisted().records.length === 0,
        "closed hidden owned window left actionable or durable state")
      expect(service.testCommandLog.length === 0,
        "hidden close targeted a window that no longer exists")
      console.info("OMARCHY_MINIMIZE_HIDDEN_CLOSE stale=0")
    } else if (step === 24) {
      var protectHidden = client("0x1400a", "special:minimum", 59010,
        "Recovery protection race", false)
      var protectRecord = ownedRecord(protectHidden, "2")
      protectRecord.sourceWorkspace = "2"
      service.testClients = [protectHidden]
      service.testActiveClient = protectHidden
      service.testWorkspaces = [{ id: 7, name: "7" }]
      service.testFocusedWorkspace = { id: 7, name: "7" }
      service.testCommandLog = []
      response = service.loadStateText(stateText([], {
        type: "minimize",
        stage: "confirm-minimize",
        address: protectRecord.address,
        target: "special:minimum",
        record: protectRecord,
        stepIndex: 1,
        overrideApplied: true
      }))
      var protectedState = persisted()
      expect(response.ok && service.pendingAction
        && service.pendingAction.stage === "recovery-protect"
        && service.currentStep && service.currentStep.kind === "guarded-ensure-hidden",
        "interrupted hidden minimize did not enter recovery protection")
      expect(operations() === "set-override" && service.entries.length === 0
        && service.supplementalRecords.length === 1
        && service.unresolvedOwnedCount === 1,
        "recovery protection was not pending with hidden durable ownership")
      expect(protectedState.records.length === 1 && protectedState.pending
        && protectedState.pending.stage === "recovery-protect"
        && protectedState.records[0].address === protectRecord.address
        && protectedState.pending.record.address === protectRecord.address,
        "recovery protection did not persist its exact owned identity")

      normal = client("0x1400a", "7", 59010, "Recovery protection race", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.reconcileNow()
      expect(service.pendingAction && service.pendingAction.stage === "recovery-protect"
        && service.supplementalRecords.length === 1
        && persisted().records.length === 1,
        "external move during recovery protection discarded durable ownership")

      service.testCompleteCommand(0, "REFUSE:MEMBERSHIP")
      var refusedState = persisted()
      expect(service.pendingAction && service.pendingAction.stage === "recovery-cleanup"
        && service.currentStep && service.currentStep.kind === "guarded-cleanup"
        && service.supplementalRecords.length === 1
        && service.unresolvedOwnedCount === 1,
        "membership refusal did not retain ownership and queue cleanup")
      expect(operations() === "set-override>unset-override"
        && refusedState.records.length === 1 && refusedState.pending
        && refusedState.pending.stage === "recovery-cleanup",
        "membership refusal did not durably journal exact cleanup")
      var protectCleanup = service.testCommandLog[1]
      var identityPrelude = "local a,p,s=\"0x1400a\",59010,"
      var workspaceGuard = protectCleanup.lua.indexOf("w.workspace and w.workspace.id==7")
      var overrideUnset = protectCleanup.lua.indexOf("value=\"unset\"")
      expect(protectCleanup.kind === "guarded-cleanup"
        && protectCleanup.lua.indexOf(identityPrelude) >= 0
        && workspaceGuard >= 0 && workspaceGuard < overrideUnset,
        "membership refusal cleanup was not exact-identity and workspace guarded")

      service.testCompleteCommand(0, "OK:CLEANED")
      expect(service.pendingAction === null && service.currentStep === null
        && service.entries.length === 0 && service.supplementalRecords.length === 0
        && service.unresolvedOwnedCount === 0 && persisted().records.length === 0
        && persisted().pending === null,
        "completed membership-race cleanup left a record or override obligation")
      console.info("OMARCHY_MINIMIZE_CLEANUP_RACE recovery-protect-membership cleanup=1")
    } else if (step === 25) {
      service.testClients = []
      service.testActiveClient = null
      service.removalDrain = false
      service.stateReady = false
      service.loadingState = true
      response = service.prepareRemoval()
      expect(!response.ok && response.code === "state-loading"
        && service.removalDrain === false,
        "removal drain started before state was ready")
      service.loadStateText(stateText([], null))

      normal = client("0x1500b", "7", 60011, "Removal busy gate", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.testWorkspaces = [{ id: 7, name: "7" }]
      service.testFocusedWorkspace = { id: 7, name: "7" }
      service.testCommandLog = []
      response = service.minimize()
      expect(response.ok && response.code === "queued",
        "removal busy-gate fixture did not start a transition")
      response = service.prepareRemoval()
      expect(!response.ok && response.code === "busy"
        && service.removalDrain === false,
        "removal drain started while a transition was busy")
      service.testCompleteCommand(0, "REFUSE:SOURCE")
      expect(service.pendingAction === null,
        "removal busy-gate fixture did not return to idle")

      var drainHidden = client("0x1600c", "special:minimum", 61012,
        "Removal drain restore", false)
      loadOwned([drainHidden], ["2"])
      expect(service.entries.length === 1 && service.busy === false,
        "removal drain fixture was not ready and idle")

      var undrainedStateText = service.testPersistedText
      service.testStateWriteFailure = true
      response = service.prepareRemoval()
      expect(!response.ok && response.code === "state-write-failed"
        && service.removalDrain === false
        && service.testPersistedText === undrainedStateText
        && persisted().removalDrain === false,
        "failed removal preparation did not remain durably undrained")
      expect(service.testCommandLog.length === 0,
        "failed removal preparation sent a compositor command")
      service.testStateWriteFailure = false
      response = service.prepareRemoval()
      var preparedStateText = service.testPersistedText
      var preparedState = persisted()
      var drainedStatus = JSON.parse(service.statusJson())
      expect(response.ok && response.code === "removal-draining"
        && response.removalDrain === true && service.removalDrain === true,
        "ready idle removal drain did not start")
      expect(preparedState.removalDrain === true,
        "successful removal preparation did not persist the drain flag")
      expect(drainedStatus.removalDrain === true && drainedStatus.busy === false,
        "status did not expose the active removal drain")

      var acquiredStateText = service.testPersistedText
      var acquiredCommandCount = service.testCommandLog.length
      service.testStateWriteFailure = true
      response = service.prepareRemoval()
      expect(!response.ok && response.code === "removal-already-draining"
        && String(response.message || "").length > 0,
        "duplicate removal-drain acquisition did not refuse with an error")
      expect(service.removalDrain === true
        && service.testPersistedText === acquiredStateText
        && persisted().removalDrain === true
        && service.testCommandLog.length === acquiredCommandCount,
        "duplicate removal-drain acquisition mutated durable or compositor state")
      service.testStateWriteFailure = false

      service.removalDrain = false
      response = service.loadStateText(preparedStateText)
      expect(response.ok && response.code === "state-loaded"
        && service.removalDrain === true
        && JSON.parse(service.statusJson()).removalDrain === true,
        "matching-session reload did not restore the persisted removal drain")

      var drainedCommandCount = service.testCommandLog.length
      response = service.minimize()
      expect(!response.ok && response.code === "removal-draining"
        && service.testCommandLog.length === drainedCommandCount,
        "minimize sent a command while removal drain was active")

      var drainedStateText = service.testPersistedText
      service.testStateWriteFailure = true
      response = service.cancelRemoval()
      expect(!response.ok && response.code === "state-write-failed"
        && service.removalDrain === true
        && service.testPersistedText === drainedStateText
        && persisted().removalDrain === true,
        "failed removal cancellation did not remain durably drained")
      response = service.minimize()
      expect(!response.ok && response.code === "removal-draining"
        && service.testCommandLog.length === drainedCommandCount,
        "failed removal cancellation reopened minimize or sent a command")
      service.testStateWriteFailure = false

      response = service.restore("0x1600c", "7")
      expect(response.ok && response.code === "queued"
        && service.testCommandLog.length === drainedCommandCount + 1
        && operations() === "move",
        "exact hidden restore was blocked by removal drain")
      service.testCompleteCommand(0, "OK:RESTORE_MOVED")
      normal = client("0x1600c", "7", 61012, "Removal drain restore", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.reconcileNow()
      expect(operations() === "move>focus>unset-override"
        && service.removalDrain === true,
        "drained restore did not reach guarded post-restore cleanup")
      service.testCompleteCommand(0, "OK:RESTORED")
      expect(service.pendingAction === null && service.entries.length === 0
        && service.removalDrain === true,
        "exact restore did not finish while retaining removal drain")

      response = service.cancelRemoval()
      expect(response.ok && response.code === "removal-cancelled"
        && service.removalDrain === false
        && JSON.parse(service.statusJson()).removalDrain === false
        && persisted().removalDrain === false,
        "cancel removal did not clear drain status")
      normal = client("0x1700d", "7", 62013, "Removal drain cancelled", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      var commandCountBeforeResume = service.testCommandLog.length
      response = service.minimize()
      expect(response.ok && response.code === "queued"
        && service.testCommandLog.length === commandCountBeforeResume + 1,
        "minimize did not become available after cancelling removal")
      service.testCompleteCommand(0, "REFUSE:SOURCE")
      expect(service.pendingAction === null && service.removalDrain === false,
        "post-cancel minimize fixture did not settle cleanly")

      response = service.prepareRemoval()
      expect(response.ok && persisted().removalDrain === true,
        "signature-mismatch fixture did not persist an active drain")
      var foreignDrainState = persisted()
      foreignDrainState.instanceSignature = "other-instance"
      response = service.loadStateText(JSON.stringify(foreignDrainState))
      expect(!response.ok && response.code === "state-mismatch"
        && service.removalDrain === false
        && JSON.parse(service.statusJson()).removalDrain === false
        && persisted().removalDrain === false
        && service.lastOperation === "Saved minimize state ignored."
        && service.lastError.indexOf("another compositor session") >= 0,
        "signature mismatch did not clear the persisted removal drain")
      response = service.reconcileAndRetry()
      expect(response.ok && response.code === "reconciled"
        && service.lastOperation === "Live window state reconciled."
        && service.lastError === "",
        "successful reconcile did not clear the handled state warning")
      console.info("OMARCHY_MINIMIZE_REMOVAL_DRAIN gates=2 writes=2 duplicate=1 reload=1 restore=1 cancel=1 mismatch=1 status-reset=1")
    } else if (step === 26) {
      var originRouteHidden = client("0x1800e", "special:minimum", 63014,
        "Origin route", false)
      service.testWorkspaces = [
        { id: 2, name: "2" }, { id: 3, name: "3" }, { id: 8, name: "8" }
      ]
      service.testFocusedWorkspace = { id: 8, name: "8" }
      loadOwned([originRouteHidden], ["2"])
      response = service.restore("0x1800e", { id: 3, name: "3" })
      expect(response.ok && response.target === "2" && response.usedOrigin === true,
        "normal restore did not prefer its live origin over panel and global workspaces")
      service.testCompleteCommand(0, "OK:RESTORE_MOVED")
      service.testClients = [client("0x1800e", "2", 63014, "Origin route", false)]
      service.testCompleteCommand(0, "OK:RESTORED")
      expect(operations() === "move>focus>unset-override" && service.entries.length === 0,
        "origin-first restore did not complete exact move, focus, and cleanup")

      var hereRouteHidden = client("0x1900f", "special:minimum", 64015,
        "Here route", false)
      loadOwned([hereRouteHidden], ["2"])
      response = service.restoreHere("0x1900f", { id: 3, name: "3" })
      expect(response.ok && response.target === "3" && response.usedOrigin === false,
        "explicit restore-here did not ignore the live origin")
      service.testCompleteCommand(0, "OK:RESTORE_MOVED")
      service.testClients = [client("0x1900f", "3", 64015, "Here route", false)]
      service.testCompleteCommand(0, "OK:RESTORED")
      expect(operations() === "move>focus>unset-override" && service.entries.length === 0,
        "explicit restore-here did not finish exact move, focus, and cleanup")

      var panelFallbackHidden = client("0x1a010", "special:minimum", 65016,
        "Panel fallback", false)
      service.testWorkspaces = [{ id: 3, name: "3" }, { id: 8, name: "8" }]
      service.testFocusedWorkspace = { id: 8, name: "8" }
      loadOwned([panelFallbackHidden], ["9"])
      response = service.restore("0x1a010", { id: 3, name: "3" })
      expect(response.ok && response.target === "3" && response.usedOrigin === false
        && response.message.indexOf("unavailable") >= 0,
        "missing origin did not prefer the captured panel fallback over global focus")
      service.testCompleteCommand(0, "OK:RESTORE_MOVED")
      service.testClients = [client("0x1a010", "3", 65016, "Panel fallback", false)]
      service.testCompleteCommand(0, "OK:RESTORED")

      var globalFallbackHidden = client("0x1b011", "special:minimum", 66017,
        "Global fallback", false)
      service.testWorkspaces = [{ id: 8, name: "8" }]
      service.testFocusedWorkspace = { id: 8, name: "8" }
      loadOwned([globalFallbackHidden], ["9"])
      response = service.restore("0x1b011", { id: 3, name: "3" })
      expect(response.ok && response.target === "8" && response.usedOrigin === false
        && response.message.indexOf("unavailable") >= 0,
        "missing panel workspace did not fall back visibly to global focus")
      service.testCompleteCommand(0, "OK:RESTORE_MOVED")
      service.testClients = [client("0x1b011", "8", 66017, "Global fallback", false)]
      service.testCompleteCommand(0, "OK:RESTORED")

      var adoptedHidden = client("0x1c012", "special:minimized", 67018,
        "Adopted route", false)
      service.testWorkspaces = [{ id: 3, name: "3" }, { id: 8, name: "8" }]
      service.testFocusedWorkspace = { id: 8, name: "8" }
      service.testClients = [adoptedHidden]
      service.loadStateText(stateText([], null))
      service.testCommandLog = []
      expect(service.entries.length === 1 && service.entries[0].owned === false
        && service.entries[0].origin === "",
        "external route fixture did not reconcile without an invented origin")
      response = service.restore("0x1c012", { id: 3, name: "3" })
      expect(response.ok && response.target === "3" && response.usedOrigin === false,
        "external entry without a trusted origin did not restore to the panel fallback")
      service.testCompleteCommand(0, "OK:RESTORE_MOVED")
      service.testClients = [client("0x1c012", "3", 67018, "Adopted route", false)]
      service.testCompleteCommand(0, "OK:RESTORED")

      var refusedHidden = client("0x1d013", "special:minimum", 68019,
        "No target", false)
      service.testWorkspaces = []
      service.testFocusedWorkspace = { id: -99, name: "special:minimum" }
      loadOwned([refusedHidden], ["9"])
      response = service.restore("0x1d013", { id: -99, name: "special:minimum" })
      expect(!response.ok && response.code === "no-visible-workspace"
        && service.testCommandLog.length === 0,
        "restore without origin, panel, or global target did not refuse before mutation")
      console.info("OMARCHY_MINIMIZE_ORIGIN_ROUTING origin=2 here=3 panel=3 global=8 external=3 refusal=pass")
    } else if (step === 27) {
      service.testShortcutCommandLog = []
      shortcutSignals = []
      service.testShortcutStartFailure = true
      response = service.refreshShortcutStatus()
      expect(!response.ok && response.code === "shortcut-start-failed"
        && service.shortcutBusy === false && service.shortcutStateKnown === false,
        "shortcut process start failure did not settle as unknown and idle")

      service.testShortcutCommandLog = []
      response = service.refreshShortcutStatus()
      expect(response.ok && service.shortcutBusy
        && service.testShortcutCommandLog.length === 1
        && service.testShortcutCommandLog[0].join("|")
          === "/fixture/plugin/bin/configure-shortcuts|status|--json",
        "read-only shortcut refresh did not use the exact helper argv")
      response = service.refreshShortcutStatus()
      expect(!response.ok && response.code === "shortcut-busy"
        && service.testShortcutCommandLog.length === 1,
        "duplicate shortcut refresh launched a second process")
      service.testCompleteShortcut(0, JSON.stringify({
        ok: true,
        configured: true,
        minimizeBinding: "SUPER + MINUS",
        sidebarBinding: "SUPER + N"
      }), "")
      expect(service.shortcutStateKnown && service.shortcutConfigured
        && service.minimizeShortcut === "SUPER + MINUS"
        && service.sidebarShortcut === "SUPER + N" && !service.shortcutBusy,
        "configured shortcut JSON did not populate shared state")

      response = service.checkShortcuts("super + shift + k", "mouse:276")
      var checkArgv = service.testShortcutCommandLog.slice(-1)[0]
      expect(response.ok && service.shortcutBusy && !service.shortcutMutationActive
        && checkArgv.join("|")
          === "/fixture/plugin/bin/configure-shortcuts|check|--minimize-binding|super + shift + k|--sidebar-binding|mouse:276|--json",
        "read-only shortcut check did not preserve the exact pair argv")
      service.testCompleteShortcut(0, JSON.stringify({
        ok: true,
        minimize: { input: "super + shift + k", binding: "SUPER + SHIFT + K",
          valid: true, available: true, conflicts: [], message: "" },
        sidebar: { input: "mouse:276", binding: "mouse:276",
          valid: true, available: false, conflicts: ["Personal mouse action"], message: "" },
        duplicate: false,
        pairAvailable: false
      }), "")
      expect(service.shortcutCheckKnown && !service.shortcutPairAvailable
        && service.shortcutMinimizeCheck.available === true
        && service.shortcutMinimizeCheck.binding === "SUPER + SHIFT + K"
        && service.shortcutSidebarCheck.available === false
        && service.shortcutSidebarCheck.conflicts[0] === "Personal mouse action"
        && !service.shortcutBusy,
        "shortcut check did not expose canonical and named per-field availability")

      response = service.checkShortcuts("SUPER + K", "SUPER + K")
      service.testCompleteShortcut(0, "{not-json", "")
      expect(!service.shortcutCheckKnown && !service.shortcutPairAvailable
        && service.shortcutCheckError.indexOf("invalid JSON") >= 0,
        "malformed shortcut check was accepted")

      var commandCountBeforeInvalid = service.testShortcutCommandLog.length
      response = service.saveShortcuts("", "SUPER + ALT + M")
      expect(!response.ok && response.code === "empty-shortcut"
        && service.testShortcutCommandLog.length === commandCountBeforeInvalid,
        "empty shortcut draft reached the helper process")
      response = service.saveShortcuts("M".repeat(129), "SUPER + ALT + M")
      expect(!response.ok && response.code === "shortcut-too-long"
        && service.testShortcutCommandLog.length === commandCountBeforeInvalid,
        "overlong shortcut draft reached the helper process")

      var hostileShortcut = "SUPER + Q; touch never"
      response = service.saveShortcuts("mouse:275", hostileShortcut)
      var hostileArgv = service.testShortcutCommandLog.slice(-1)[0]
      expect(response.ok && hostileArgv.length === 6
        && hostileArgv[0] === "/fixture/plugin/bin/configure-shortcuts"
        && hostileArgv[1] === "apply" && hostileArgv[3] === "mouse:275"
        && hostileArgv[5] === hostileShortcut,
        "hostile shortcut text did not remain one literal argv element")
      response = service.saveShortcuts("SUPER + X", "SUPER + Y")
      expect(!response.ok && response.code === "shortcut-busy",
        "shortcut double-submit was not refused")
      service.testCompleteShortcut(1, "", "Conflict: SUPER + Q is already bound")
      expect(service.shortcutBusy && service.shortcutMutationActive
        && service.testShortcutCommandLog.slice(-1)[0].join("|")
          === "/fixture/plugin/bin/configure-shortcuts|status|--json",
        "failed shortcut apply did not queue a read-only status refresh")
      service.testCompleteShortcut(0, JSON.stringify({
        ok: true,
        configured: true,
        minimizeBinding: "SUPER + MINUS",
        sidebarBinding: "SUPER + N"
      }), "")
      expect(!service.shortcutBusy && !service.shortcutMutationActive
        && service.shortcutLastError.indexOf("Conflict") >= 0
        && service.minimizeShortcut === "SUPER + MINUS",
        "failed apply did not preserve refreshed state and separate error feedback")

      response = service.saveShortcuts("mouse:275", "SUPER + CTRL + N")
      expect(response.ok && service.shortcutMutationActive,
        "valid keyboard/mouse pair did not queue through the singleton")
      response = service.minimize()
      expect(!response.ok && response.code === "shortcut-busy",
        "window mutation was not blocked while shortcut apply was active")
      service.testCompleteShortcut(0,
        "Configured minimize=mouse:275 and sidebar=SUPER + CTRL + N.", "")
      service.testCompleteShortcut(0, JSON.stringify({
        ok: true,
        configured: true,
        minimizeBinding: "mouse:275",
        sidebarBinding: "SUPER + CTRL + N"
      }), "")
      expect(service.shortcutConfigured && service.minimizeShortcut === "mouse:275"
        && service.sidebarShortcut === "SUPER + CTRL + N"
        && service.shortcutLastError === ""
        && service.shortcutLastOperation.indexOf("Configured") >= 0,
        "successful apply did not refresh state and preserve success feedback")

      normal = client("0x1e014", "2", 69020, "Window overlap", false)
      service.testClients = [normal]
      service.testActiveClient = normal
      service.testWorkspaces = [{ id: 2, name: "2" }]
      service.testFocusedWorkspace = { id: 2, name: "2" }
      service.loadStateText(stateText([], null))
      service.testCommandLog = []
      response = service.minimize()
      expect(response.ok && service.busy, "window-overlap fixture did not become busy")
      response = service.saveShortcuts("SUPER + X", "SUPER + Y")
      expect(!response.ok && response.code === "window-busy"
        && !service.shortcutBusy,
        "shortcut mutation was not blocked during a window transition")
      service.testCompleteCommand(0, "REFUSE:SOURCE")

      response = service.removeShortcuts()
      expect(response.ok && service.testShortcutCommandLog.slice(-1)[0].join("|")
        === "/fixture/plugin/bin/configure-shortcuts|remove",
        "explicit remove did not use the exact helper argv")
      service.testCompleteShortcut(0, "Removed only the owned shortcut block.", "")
      service.testCompleteShortcut(0, JSON.stringify({
        ok: true,
        configured: false,
        minimizeBinding: "",
        sidebarBinding: ""
      }), "")
      expect(service.shortcutStateKnown && !service.shortcutConfigured
        && service.minimizeShortcut === "" && service.sidebarShortcut === "",
        "remove completion did not refresh shared state to absent")

      response = service.refreshShortcutStatus()
      service.testCompleteShortcut(0, "{not-json", "")
      expect(!service.shortcutStateKnown && service.shortcutLastError.indexOf("invalid JSON") >= 0,
        "malformed shortcut status was accepted")
      response = service.refreshShortcutStatus()
      service.testCompleteShortcut(127, "", "x".repeat(5000))
      expect(!service.shortcutStateKnown && service.shortcutLastError.length === 2048,
        "shortcut process error was not bounded")
      expect(shortcutSignals.length >= 6
        && shortcutSignals.filter(function(value) {
          return value.code === "apply" && value.ok === true
        }).length === 1
        && shortcutSignals.filter(function(value) {
          return value.code === "apply" && value.ok === false
        }).length === 1,
        "shortcut results did not use their separate completion signal")
      console.info("OMARCHY_MINIMIZE_SHORTCUT_SERVICE status=known check=read-only+named apply=serialized argv=literal remove=explicit errors=bounded signals=" + shortcutSignals.length)
    } else if (step === 28) {
      service.testClients = []
      service.testActiveClient = null
      service.reconcileNow()
      expect(JSON.parse(service.statusJson()).count === 0, "status JSON is not deterministic")
      console.info("OMARCHY_MINIMIZE_IPC_STATUS " + service.statusJson())
      console.info("OMARCHY_MINIMIZE_SERVICE_PASS")
      return
    }

    step++
    tick.restart()
  }

  Service {
    id: service
    testMode: true
    testInstanceSignature: "test-instance"
    transitionTimeoutMs: 500
  }

  Connections {
    target: service
    function onShortcutOperationFinished(code, ok) {
      var next = harness.shortcutSignals.slice()
      next.push({ code: String(code), ok: ok === true })
      harness.shortcutSignals = next
    }
  }

  Timer {
    id: tick
    interval: 10
    repeat: false
    onTriggered: harness.advance()
  }

  Timer {
    id: debounceCheck
    interval: 80
    repeat: false
    onTriggered: {
      harness.expect(service.testRefreshCount - harness.burstRefreshBaseline === 1,
        "1,000 events did not coalesce to one native refresh")
      harness.expect(service.testReconcileCount - harness.burstReconcileBaseline === 1,
        "1,000 events did not coalesce to one reconciliation")
      harness.expect(service.lastRawEvent.name === "synthetic-999"
        && service.lastRawEvent.data === "payload-999",
        "event burst did not retain the final copied event")
      harness.idleRefreshBaseline = service.testRefreshCount
      harness.idleReconcileBaseline = service.testReconcileCount
      idleCheck.restart()
    }
  }

  Timer {
    id: idleCheck
    interval: 80
    repeat: false
    onTriggered: {
      harness.expect(service.testRefreshCount === harness.idleRefreshBaseline
        && service.testReconcileCount === harness.idleReconcileBaseline,
        "idle service performed a periodic refresh or reconciliation")
      harness.expect(service.testCommandLog.length === 0,
        "idle service launched a compositor command")
      console.info("OMARCHY_MINIMIZE_EVENT_BURST events=1000 refresh=1 reconcile=1 idle=0")
      tick.restart()
    }
  }

  Component.onCompleted: tick.start()
}
