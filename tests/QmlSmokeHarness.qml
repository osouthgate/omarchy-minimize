import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import qs.Commons

// Deterministic UI contract harness. The production service is replaced by a
// passive in-memory store: any compositor work from a row delegate would show
// up as a non-zero queryCount and fail the 100-row fixture.
ShellRoot {
  id: harness

  property bool failed: false
  property int screenshotStep: 0
  property string artifactDir: String(Quickshell.env("OMARCHY_MINIMIZE_ARTIFACT_DIR") || "")
  property var rowFixture: makeEntry(1, "none", false, "Build running")
  property var captureEntries: []
  property string captureLabel: "Empty"
  property string captureMessage: "No minimized windows"
  property int captureSelectedIndex: -1
  property string capturePage: "windows"

  function expect(condition, message) {
    if (condition || failed) return
    failed = true
    console.warn("OMARCHY_MINIMIZE_UI_ERROR " + message)
  }

  function contains(text, fragment) {
    return String(text || "").toLowerCase().indexOf(String(fragment || "").toLowerCase()) !== -1
  }

  function makeEntry(index, attention, recovered, title) {
    var suffix = Number(index).toString(16)
    var address = "0x" + "1000000000000000".substr(0, 16 - suffix.length) + suffix
    return {
      address: address,
      title: String(title === undefined ? "Window " + index : title),
      className: index % 2 === 0 ? "foot" : "org.mozilla.firefox",
      sourceWorkspace: index % 3 === 0 ? "special:scratchpad" : "special:minimum",
      origin: String(index % 9 + 1),
      monitor: index % 2,
      minimizedAt: 1735689600000 - index * 60000,
      attention: String(attention || "none"),
      owned: true,
      recovered: recovered === true
    }
  }

  function entries(count) {
    var rows = []
    for (var i = 0; i < count; i++)
      rows.push(makeEntry(i + 1, "none", false, "Fixture window " + (i + 1)))
    return rows
  }

  function setStoreRows(rows) {
    fixtureStore.entries = rows.slice(0)
  }

  function callsNamed(name) {
    var out = []
    for (var i = 0; i < fixtureStore.calls.length; i++)
      if (fixtureStore.calls[i].name === name) out.push(fixtureStore.calls[i])
    return out
  }

  function productionListView(item) {
    if (!item) return null
    if (typeof item.positionViewAtIndex === "function"
        && typeof item.itemAtIndex === "function"
        && typeof item.contentY === "number") return item
    var descendants = item.children || []
    for (var i = 0; i < descendants.length; i++) {
      var found = productionListView(descendants[i])
      if (found) return found
    }
    return null
  }

  function listContainsRow(list, index) {
    if (!list || typeof list.itemAtIndex !== "function") return false
    var row = list.itemAtIndex(index)
    if (!row) return false
    var viewportTop = Number(row.y) - Number(list.contentY)
    return viewportTop >= -1 && viewportTop + Number(row.height) <= Number(list.height) + 1
  }

  function resetStore() {
    fixtureStore.calls = []
    fixtureStore.queryCount = 0
    fixtureStore.loaded = true
    fixtureStore.stateReady = true
    fixtureStore.loadingState = false
    fixtureStore.busy = false
    fixtureStore.supported = true
    fixtureStore.compositorSupported = true
    fixtureStore.unsupportedReason = ""
    fixtureStore.lastError = ""
    fixtureStore.lastOperation = "Ready"
    fixtureStore.pendingAction = null
    fixtureStore.unavailableOrigins = []
    fixtureStore.shortcutStateKnown = true
    fixtureStore.shortcutConfigured = true
    fixtureStore.shortcutBusy = false
    fixtureStore.shortcutPendingKind = ""
    fixtureStore.minimizeShortcut = "SUPER + M"
    fixtureStore.sidebarShortcut = "SUPER + ALT + M"
    fixtureStore.shortcutLastOperation = "Shortcut settings loaded."
    fixtureStore.shortcutLastError = ""
    fixtureStore.shortcutCheckKnown = false
    fixtureStore.shortcutPairAvailable = false
    fixtureStore.shortcutMinimizeCheck = ({})
    fixtureStore.shortcutSidebarCheck = ({})
    fixtureStore.shortcutCheckError = ""
  }

  function capturePath(name) {
    return artifactDir + "/" + name + ".png"
  }

  function requestCapture(name) {
    captureRoot.grabToImage(function(result) {
      if (!result || !result.saveToFile(capturePath(name))) {
        harness.expect(false, "could not save " + name + " screenshot")
      } else {
        console.info("OMARCHY_MINIMIZE_UI_SCREENSHOT " + capturePath(name))
      }
      screenshotStep++
      captureTimer.restart()
    }, Qt.size(captureRoot.width, captureRoot.height))
  }

  function runAssertions() {
    resetStore()

    // Shared store and badge geometry/priority.
    setStoreRows([])
    var reserved = panelA.badgeReservedWidth
    expect(reserved > 0, "badge did not reserve a fixed-width slot")
    setStoreRows(entries(9))
    expect(panelA.badgeReservedWidth === reserved, "badge width changed at one digit")
    setStoreRows(entries(100))
    expect(panelA.badgeReservedWidth === reserved, "badge width changed at 100 rows")
    expect(panelA.badgeText === "99+", "three-digit badge was not capped inside its slot")
    expect(panelA.effectiveStore === panelB.effectiveStore
      && panelA.visibleEntries.length === panelB.visibleEntries.length,
      "monitor panels did not share one store")

    setStoreRows([makeEntry(1, "updated", false, "Updated")])
    var updatedState = panelA.indicatorState
    setStoreRows([
      makeEntry(1, "updated", false, "Updated"),
      makeEntry(2, "urgent", false, "Urgent")
    ])
    var urgentState = panelA.indicatorState
    expect(String(updatedState) === "updated", "updated indicator state was not exposed")
    expect(String(urgentState) === "urgent", "urgent did not outrank updated")
    console.info("OMARCHY_MINIMIZE_UI_BADGE reserved=" + reserved
      + " text=" + panelA.badgeText + " state=" + String(urgentState))

    // Bar button semantics exercise the production routing function.
    fixtureStore.calls = []
    var initiallyOpen = panelA.opened
    panelA.handleBarPress(Qt.LeftButton)
    expect(panelA.opened !== initiallyOpen, "left-click did not toggle the drawer")
    panelA.handleBarPress(Qt.LeftButton)
    expect(panelA.opened === initiallyOpen, "second left-click did not restore drawer state")
    panelA.handleBarPress(Qt.RightButton)
    panelA.handleBarPress(Qt.MiddleButton)
    expect(callsNamed("minimize").length === 1, "right-click did not request minimize")
    expect(callsNamed("restore").length === 1
      && callsNamed("restore")[0].address === fixtureStore.entries[0].address,
      "middle-click did not request the newest minimizedAt entry")
    console.info("OMARCHY_MINIMIZE_UI_MOUSE left=toggle right=minimize middle=restore-last")

    // Production WindowRow state priority, metadata, accessibility and
    // literal-title safety. These are the five row-level members of the nine
    // visible-state fixture set (pending is also checked at panel level).
    var hostile = "編集中 🧪, <b>literal & untrusted</b> — " + "界".repeat(180)
    rowFixture = makeEntry(7, "urgent", true, hostile)
    rowProbe.pending = true
    expect(rowProbe.visibleStateLabel === "Pending", "pending did not outrank row attention")
    rowProbe.pending = false
    expect(rowProbe.visibleStateLabel === "Needs attention", "urgent row label is wrong")
    expect(String(rowProbe.Accessible.name) === hostile,
      "row accessible name does not preserve its literal title")
    expect(contains(rowProbe.Accessible.description, "needs attention")
      && contains(rowProbe.Accessible.description, "workspace 8"),
      "row accessible description omits state or origin")
    rowFixture = makeEntry(7, "updated", true, hostile)
    expect(rowProbe.visibleStateLabel === "Updated", "updated did not outrank recovered")
    rowFixture = makeEntry(7, "none", true, hostile)
    expect(rowProbe.visibleStateLabel === "Recovered", "recovered row label is wrong")
    rowFixture = makeEntry(7, "none", false, hostile)
    expect(rowProbe.visibleStateLabel === "Minimized", "ordinary row label is wrong")
    rowProbe.originAvailable = false
    expect(rowProbe.visibleStateLabel === "Origin unavailable",
      "origin-missing row label is wrong")
    expect(contains(rowProbe.sourceLabel, "unavailable"),
      "origin-missing source metadata is not visible")
    rowProbe.originAvailable = true
    expect(rowProbe.renderedTitleFormat === Text.PlainText, "title is not rendered as plain text")
    expect(rowProbe.title === hostile, "hostile Unicode title was rewritten")
    expect(rowProbe.tooltipTitle.length <= 72 && hostile.indexOf(rowProbe.tooltipTitle.slice(0, 20)) === 0,
      "truncated-title tooltip was not bounded while preserving literal text")
    expect(contains(rowProbe.sourceLabel, "workspace 8") && contains(rowProbe.sourceLabel, "minimum"),
      "origin/source metadata is incomplete")
    expect(rowProbe.elapsedLabel.length > 0, "elapsed-time label is empty")
    expect(rowProbe.hasIcon || rowProbe.fallbackInitial.length === 1,
      "row exposed neither an application icon nor a fallback")
    console.info("OMARCHY_MINIMIZE_UI_ROW states=Pending,Needs-attention,Updated,Recovered,Origin-unavailable,Minimized"
      + " titleFormat=" + rowProbe.renderedTitleFormat)
    console.info("OMARCHY_MINIMIZE_UI_ACCESSIBILITY row-name=literal row-description=state+origin")

    // Origin-first and explicit restore-here use distinct service methods.
    setStoreRows([makeEntry(1, "none", false, "Restore target")])
    fixtureStore.calls = []
    panelA.restoreIndex(0, false)
    panelA.restoreIndex(0, true)
    panelB.restoreIndex(0, false)
    panelA.restoreAllHere()
    var origin = callsNamed("restore")
    var here = callsNamed("restoreHere")
    var restoreAll = callsNamed("restoreAll")
    expect(origin.length === 2 && String(origin[0].target) === "3"
      && String(origin[1].target) === "8",
      "origin-first restores did not retain distinct per-panel fallbacks")
    expect(here.length === 1 && here[0].address === fixtureStore.entries[0].address
      && String(here[0].target) === "3",
      "explicit restore-here did not route the exact address to this panel")
    expect(restoreAll.length === 1 && restoreAll[0].target === "3",
      "deliberate restore-all did not target the clicked panel workspace")
    expect(fakeShell.serviceLookups >= 2 && panelA.effectiveStore === fixtureStore,
      "bar panels did not resolve the singleton through shell.serviceFor")
    console.info("OMARCHY_MINIMIZE_UI_MONITORS shared=" + panelA.visibleEntries.length
      + " originFallbackA=" + origin[0].target + " originFallbackB=" + origin[1].target
      + " hereTarget=" + here[0].target)

    // A single restore closes only after authoritative success. Keeping the
    // drawer open while queued makes progress/errors visible; manual close
    // cancels the intent so an old completion cannot close a reopened drawer.
    panelA.close()
    panelB.close()
    panelA.open()
    fixtureStore.calls = []
    expect(panelA.restoreIndex(0, false) && panelA.opened
      && panelA.pendingAutoCloseAddress === fixtureStore.entries[0].address,
      "queued single restore did not retain its auto-close intent")
    fixtureStore.lastOperation = "Window restored."
    fixtureStore.operationFinished("restored", true)
    expect(!panelA.opened && panelA.pendingAutoCloseAddress === "",
      "successful single restore did not close the drawer")

    panelA.open()
    fixtureStore.calls = []
    expect(panelA.restoreIndex(0, true), "failure fixture restore was not queued")
    fixtureStore.lastError = "Restore fixture failed safely."
    fixtureStore.operationFinished("restore-failed", false)
    expect(panelA.opened && panelA.pendingAutoCloseAddress === ""
      && panelA.feedbackError && contains(panelA.feedbackText, "failed safely"),
      "failed single restore closed the drawer or hid its error")

    fixtureStore.lastError = ""
    expect(panelA.restoreIndex(0, false), "manual-close fixture restore was not queued")
    panelA.close()
    panelA.open()
    fixtureStore.operationFinished("restored", true)
    expect(panelA.opened && panelA.pendingAutoCloseAddress === "",
      "stale restore completion closed a manually reopened drawer")
    panelA.restoreAllHere()
    fixtureStore.operationFinished("restored", true)
    expect(panelA.opened, "restore-all inherited single-window auto-close")
    console.info("OMARCHY_MINIMIZE_UI_RESTORE_CLOSE queued=open success=closed failure=open manual-cancel=preserved all=open")

    // Cursor navigation and complete keyboard-only action routing.
    setStoreRows(entries(4))
    panelA.close()
    fixtureStore.calls = []
    panelA.open()
    expect(panelA.opened, "keyboard-summoned open did not show the drawer")
    expect(callsNamed("reconcile").length === 1,
      "opening the drawer did not refresh the passive projection")
    panelA.selectFirst()
    panelA.handleSemanticKey(Qt.Key_Down, Qt.NoModifier)
    expect(panelA.selectedIndex === 1, "Down did not move selection")
    panelA.handleSemanticKey(Qt.Key_Up, Qt.NoModifier)
    expect(panelA.selectedIndex === 0, "Up did not move selection")
    panelA.handleSemanticKey(Qt.Key_End, Qt.NoModifier)
    expect(panelA.selectedIndex === 3, "End did not select the last row")
    panelA.handleSemanticKey(Qt.Key_Home, Qt.NoModifier)
    expect(panelA.selectedIndex === 0, "Home did not select the first row")
    fixtureStore.calls = []
    panelA.handleSemanticKey(Qt.Key_M, Qt.NoModifier)
    var enterAction = panelA.handleSemanticKey(Qt.Key_Return, Qt.NoModifier)
    var shiftEnterAction = panelA.handleSemanticKey(Qt.Key_Return, Qt.ShiftModifier)
    var spaceAction = panelA.handleSemanticKey(Qt.Key_Space, Qt.NoModifier)
    panelA.handleSemanticKey(Qt.Key_Return, Qt.ControlModifier)
    panelA.handleSemanticKey(Qt.Key_A, Qt.NoModifier)
    panelA.handleSemanticKey(Qt.Key_R, Qt.NoModifier)
    expect(callsNamed("minimize").length === 1, "M did not request minimize")
    expect(callsNamed("restore").length === 2 && callsNamed("restoreHere").length === 1,
      "Enter/Space/Shift+Enter did not preserve origin-first and restore-here semantics")
    expect(enterAction === "restore-origin" && spaceAction === "restore-origin"
      && shiftEnterAction === "restore-here",
      "semantic return tokens do not describe origin-first and restore-here actions")
    expect(callsNamed("restoreAll").length === 1
      && callsNamed("restoreAll")[0].target === "3",
      "Ctrl+Enter did not restore all to this monitor")
    expect(callsNamed("acknowledge").length === 1
      && callsNamed("acknowledge")[0].address === fixtureStore.entries[0].address,
      "A did not acknowledge the selected exact address")
    expect(callsNamed("reconcile").length === 1, "R did not request reconciliation")
    fakeBar.switchDirections = []
    panelA.handleSemanticKey(Qt.Key_Tab, Qt.NoModifier)
    panelA.handleSemanticKey(Qt.Key_Tab, Qt.ShiftModifier)
    expect(fakeBar.switchDirections.length === 2 && fakeBar.switchDirections[0] === 1
      && fakeBar.switchDirections[1] === -1, "Tab/Shift+Tab panel switching is wrong")
    panelA.handleSemanticKey(Qt.Key_Escape, Qt.NoModifier)
    expect(!panelA.opened, "Escape did not close the drawer")
    console.info("OMARCHY_MINIMIZE_UI_KEYBOARD open,M,Enter,Shift+Enter,Ctrl+Enter,A,R,Escape"
      + ",Up,Down,Home,End,Tab")

    // Internal pages, shared shortcut authority and edit-focus routing.
    fixtureStore.calls = []
    panelA.open()
    fixtureStore.calls = []
    panelA.openHelp()
    expect(panelA.currentPage === "help", "Help action did not open the internal page")
    var helpCopy = panelA.helpViewObject.coverageText
    expect(helpCopy.length > 700 && contains(helpCopy, "keeps running")
      && contains(helpCopy, "neither marker") && contains(helpCopy, "reconcile")
      && contains(helpCopy, "pinned and grouped"),
      "Help copy does not cover the complete mental model: " + helpCopy)
    expect(callsNamed("shortcut-status").length === 0,
      "opening Help unexpectedly touched shortcut config")
    panelA.openShortcuts()
    expect(panelA.currentPage === "shortcuts", "Configure CTA did not open Shortcuts")
    expect(callsNamed("shortcut-status").length === 1
      && callsNamed("shortcut-apply").length === 0,
      "opening Shortcuts was not a single read-only refresh")
    var settingsA = panelA.shortcutViewObject
    var settingsB = panelB.shortcutViewObject
    expect(settingsA.stateKind === "configured", "configured state is not visible")
    fixtureStore.shortcutStateKnown = false
    expect(settingsA.stateKind === "loading", "unknown/loading shortcut state is not visible")
    fixtureStore.shortcutLastError = "Conflict detected; rollback preserved prior bytes."
    expect(settingsA.stateKind === "error" && contains(settingsA.stateText, "rollback"),
      "conflict/rollback failure state is not visible")
    fixtureStore.shortcutLastError = ""
    fixtureStore.shortcutStateKnown = true
    fixtureStore.shortcutConfigured = false
    settingsA.syncFromStore(true)
    expect(settingsA.stateKind === "absent" && settingsA.minimizeDraft === ""
      && settingsA.sidebarDraft === "", "absent shortcut state did not keep fields empty")
    fixtureStore.shortcutConfigured = true
    settingsA.syncFromStore(true)
    fixtureStore.shortcutBusy = true
    expect(settingsA.stateKind === "busy", "busy shortcut state is not visible")
    fixtureStore.shortcutBusy = false
    settingsA.resetSuggestions()
    expect(settingsA.dirty && settingsA.minimizeDraft === "SUPER + M"
      && settingsA.sidebarDraft === "SUPER + ALT + M"
      && callsNamed("shortcut-apply").length === 0,
      "Reset suggestions mutated config or failed to fill drafts")
    expect(settingsA.keyboardChord(Qt.Key_M, Qt.MetaModifier | Qt.ShiftModifier, "m")
      === "SUPER + SHIFT + M", "keyboard recorder did not normalize Super+Shift+M")
    expect(settingsA.mouseChord(Qt.ExtraButton2, Qt.NoModifier) === "mouse:276",
      "mouse recorder did not map the fifth non-wheel button to mouse:276")
    expect(settingsA.startRecording("minimize")
      && !settingsA.captureMouse(Qt.LeftButton, Qt.NoModifier)
      && settingsA.recordingAction === "minimize"
      && contains(settingsA.recordingHint, "need a modifier"),
      "recorder accepted an unsafe unmodified primary mouse button")
    expect(settingsA.captureKeyboard(Qt.Key_K, Qt.MetaModifier | Qt.ControlModifier, "k")
      && settingsA.minimizeDraft === "SUPER + CTRL + K"
      && settingsA.recordingAction === "", "keyboard capture did not populate one action draft")

    settingsA.setDrafts("SUPER + M", "mouse:276")
    fixtureStore.shortcutCheckKnown = true
    fixtureStore.shortcutPairAvailable = false
    fixtureStore.shortcutMinimizeCheck = ({ input: "SUPER + M", binding: "SUPER + M",
      valid: true, available: false, conflicts: ["Personal mail"], message: "" })
    fixtureStore.shortcutSidebarCheck = ({ input: "mouse:276", binding: "mouse:276",
      valid: true, available: true, conflicts: [], message: "" })
    expect(contains(settingsA.fieldStatus("minimize"), "Personal mail") && !settingsA.canSave,
      "named live conflict did not stay beside its field or block Save")

    settingsA.setDrafts("SUPER + SHIFT + M", "mouse:276")
    fixtureStore.shortcutCheckKnown = true
    fixtureStore.shortcutPairAvailable = true
    fixtureStore.shortcutMinimizeCheck = ({ input: "SUPER + SHIFT + M", binding: "SUPER + SHIFT + M",
      valid: true, available: true, conflicts: [], message: "" })
    fixtureStore.shortcutSidebarCheck = ({ input: "mouse:276", binding: "mouse:276",
      valid: true, available: true, conflicts: [], message: "" })
    expect(settingsA.canSave && settingsA.fieldStatus("minimize") === "Available",
      "fresh matching free-pair check did not enable Save")
    expect(settingsA.saveDrafts(), "Save did not accept valid exact drafts")
    expect(callsNamed("shortcut-apply").length === 1
      && callsNamed("shortcut-apply")[0].address === "SUPER + SHIFT + M"
      && callsNamed("shortcut-apply")[0].target === "mouse:276",
      "Save did not submit both exact drafts once")
    panelB.openShortcuts()
    expect(callsNamed("shortcut-status").length === 1,
      "a busy shared service accepted a second panel refresh")
    expect(!settingsB.saveDrafts() && callsNamed("shortcut-apply").length === 1,
      "a second panel double-submitted while shared state was busy")
    fixtureStore.shortcutBusy = false
    fixtureStore.minimizeShortcut = "SUPER + SHIFT + M"
    fixtureStore.sidebarShortcut = "mouse:276"
    fixtureStore.shortcutOperationFinished("apply", true)
    settingsB.setDrafts("SUPER + CTRL + M", "mouse:277")
    fixtureStore.minimizeShortcut = "SUPER + Q"
    fixtureStore.sidebarShortcut = "SUPER + ALT + Q"
    fixtureStore.shortcutOperationFinished("status", true)
    expect(settingsB.minimizeDraft === "SUPER + CTRL + M"
      && settingsB.sidebarDraft === "mouse:277" && settingsB.dirty,
      "shared refresh clobbered another panel's dirty drafts")
    var statusBeforeRefresh = callsNamed("shortcut-status").length
    settingsA.refreshStatus()
    expect(callsNamed("shortcut-status").length === statusBeforeRefresh + 1
      && callsNamed("shortcut-apply").length === 1,
      "Refresh was not read-only")
    fixtureStore.shortcutBusy = false
    fixtureStore.shortcutConfigured = true
    expect(!settingsA.requestRemove() && callsNamed("shortcut-remove").length === 0,
      "first Remove click bypassed confirmation")
    expect(settingsA.requestRemove() && callsNamed("shortcut-remove").length === 1,
      "confirmed Remove did not submit exactly once")
    fixtureStore.shortcutBusy = false
    fixtureStore.shortcutConfigured = false
    fixtureStore.shortcutOperationFinished("remove", true)
    expect(settingsA.stateKind === "success" || settingsA.stateKind === "absent",
      "successful/absent shortcut state is not visible")

    panelA.openShortcuts()
    settingsA.focusFirstField()
    expect(panelA.keyInputBlocked, "focused TextField did not bypass panel keys")
    settingsA.backRequested()
    expect(panelA.currentPage === "windows", "Escape route did not return to windows")
    expect(panelA.handleSemanticKey(Qt.Key_F1, Qt.NoModifier) === "help"
      && panelA.currentPage === "help", "F1 did not open Help")
    expect(panelA.handleSemanticKey(Qt.Key_Escape, Qt.NoModifier) === "back"
      && panelA.opened && panelA.currentPage === "windows",
      "first Escape did not return from subpage")
    expect(panelA.handleSemanticKey(Qt.Key_Escape, Qt.NoModifier) === "close" && !panelA.opened,
      "second Escape did not close the drawer")
    panelA.open()
    expect(panelA.currentPage === "windows", "reopening did not reset to windows")
    panelA.testScreenWidth = 320
    panelA.testScreenHeight = 360
    panelA.openHelp()
    expect(panelA.panelWidthPx <= 320 && panelA.panelHeightPx <= 360,
      "minimum panel escaped its bounds: " + panelA.panelWidthPx + "x" + panelA.panelHeightPx)
    panelA.testScreenWidth = 520
    panelA.testScreenHeight = 600
    panelA.backToWindows()
    console.info("OMARCHY_MINIMIZE_UI_PAGES help=covered shortcuts=states back=before-close reopen=windows")
    console.info("OMARCHY_MINIMIZE_UI_SHORTCUTS open=read-only record=keyboard+mouse conflict=named save=gated+once refresh=read-only remove=confirmed shared=preserved")
    console.info("OMARCHY_MINIMIZE_UI_FOCUS fields=bypass F1=help Escape=back-then-close width=320 scroll=true")

    // User-facing state messages. Assertions deliberately check meaning, not
    // typography, so themes may change punctuation without weakening coverage.
    setStoreRows([])
    resetStore()
    panelA.feedbackText = "Stale completed action"
    panelA.feedbackError = false
    panelA.close()
    panelA.open()
    expect(panelA.feedbackText === "", "opening the panel did not clear stale feedback")
    expect(contains(panelA.stateMessage, "minimized"), "empty state message is missing")
    fixtureStore.stateReady = false
    fixtureStore.loadingState = true
    expect(contains(panelA.stateMessage, "load") || contains(panelA.stateMessage, "connect")
      || contains(panelA.stateMessage, "reading"),
      "binding/loading state message is missing: " + panelA.stateMessage)
    fixtureStore.stateReady = true
    fixtureStore.loadingState = false
    fixtureStore.supported = false
    fixtureStore.compositorSupported = false
    fixtureStore.unsupportedReason = "Unsupported compositor fixture"
    expect(contains(panelA.stateMessage, "unsupported"), "unsupported state message is missing")
    expect(contains(panelA.stateMessage, "normal workspace") || contains(panelA.stateMessage, "close"),
      "unsupported state omits a safe next action")
    fixtureStore.supported = true
    fixtureStore.compositorSupported = true
    fixtureStore.unsupportedReason = ""
    fixtureStore.lastError = ""
    fixtureStore.busy = true
    fixtureStore.pendingAction = ({ type: "restore", address: "0x1" })
    fixtureStore.lastOperation = "Restoring selected window"
    expect(contains(panelA.stateMessage, "restor") || contains(panelA.stateMessage, "pending"),
      "pending state message is missing")
    fixtureStore.busy = false
    fixtureStore.pendingAction = null
    fixtureStore.lastError = "Compositor fixture error"
    expect(contains(panelA.stateMessage, "compositor fixture error"),
      "compositor error is not visible")
    expect(contains(panelA.stateMessage, "reconcile"), "error state omits a safe retry action")
    console.info("OMARCHY_MINIMIZE_UI_MESSAGES empty,loading,error,unsupported,pending")
    console.info("OMARCHY_MINIMIZE_UI_STATES empty,loading,error,unsupported,pending,updated,urgent,recovered,origin-missing")

    // Let the production ListView incubate the 100-row fixture before checking
    // its real geometry. This also prevents an unlaid-out 28px shell from
    // satisfying a mere upper-bound assertion.
    resetStore()
    var many = entries(100)
    many[0] = makeEntry(1, "urgent", false, hostile)
    setStoreRows(many)
    panelA.open()
    panelA.handleSemanticKey(Qt.Key_End, Qt.NoModifier)
    layoutTimer.restart()
  }

  function runLayoutAssertions() {
    // Screen bounds and list cost. Reading/rendering 100 records must remain a
    // pure projection of the service store, with no per-row compositor calls.
    expect(panelA.visibleEntries.length === 100, "100-row store did not rebuild")
    expect(panelA.panelWidthPx > 0 && panelA.panelWidthPx <= captureWindow.width,
      "panel width escaped the synthetic screen")
    expect(panelA.rightEdgeAnchorX === 1000000,
      "drawer lost the fixed right-edge anchor")
    expect(panelA.panelHeightPx >= 240 && panelA.panelHeightPx <= captureWindow.height,
      "panel height collapsed or escaped the synthetic screen: " + panelA.panelHeightPx)
    expect(panelA.drawerContentImplicitHeight >= panelA.listViewportHeight,
      "drawer natural height did not include its list viewport")
    expect(panelA.listViewportHeight >= 120,
      "100-row list viewport collapsed: " + panelA.listViewportHeight)
    expect(panelA.listContentHeight > panelA.listViewportHeight,
      "100-row fixture is not scrollable")
    expect(panelA.selectedIndex === 99, "End did not select row 100 in the long list")
    var productList = productionListView(panelA)
    expect(productList !== null, "production ListView could not be inspected")
    expect(listContainsRow(productList, 99),
      "selected row 100 is not contained in the production viewport")
    expect(fixtureStore.queryCount === 0, "row rebuild launched compositor queries")
    console.info("OMARCHY_MINIMIZE_UI_BOUNDS width=" + panelA.panelWidthPx
      + " height=" + panelA.panelHeightPx + " screen=" + captureWindow.width + "x" + captureWindow.height)
    console.info("OMARCHY_MINIMIZE_UI_LAYOUT implicit=" + panelA.drawerContentImplicitHeight
      + " listContent=" + panelA.listContentHeight + " listViewport=" + panelA.listViewportHeight)
    console.info("OMARCHY_MINIMIZE_UI_PERF rows=100 hyprctl=" + fixtureStore.queryCount)
    console.info("OMARCHY_MINIMIZE_UI_LONG_LIST rows=100 selected=" + panelA.selectedIndex
      + " contained=" + listContainsRow(productList, 99))

    // Begin the visual captures only after all behavioral assertions pass.
    panelA.close()
    panelA.feedbackText = ""
    panelA.feedbackError = false
    setStoreRows([])
    captureEntries = []
    captureSelectedIndex = -1
    captureLabel = "Empty"
    captureMessage = panelA.stateMessage
    captureTimer.restart()
  }

  function advanceCapture() {
    if (failed) return
    if (screenshotStep === 0) {
      requestCapture("empty")
    } else if (screenshotStep === 1) {
      var rows = entries(5)
      rows[0] = makeEntry(1, "none", false, "Build running — terminal")
      rows[1] = makeEntry(2, "none", false, "Documentation — browser")
      setStoreRows(rows)
      captureEntries = rows
      captureSelectedIndex = 0
      captureLabel = "Minimized windows"
      captureMessage = "5 windows · original workspace or restore here"
      requestCapture("populated")
    } else if (screenshotStep === 2) {
      var rowsUpdated = entries(4)
      rowsUpdated[0] = makeEntry(1, "updated", false, "Title changed while minimized")
      setStoreRows(rowsUpdated)
      captureEntries = rowsUpdated
      captureSelectedIndex = 0
      captureLabel = "Updated"
      captureMessage = "1 minimized window changed since it was hidden"
      requestCapture("updated")
    } else if (screenshotStep === 3) {
      var rowsUrgent = entries(4)
      rowsUrgent[0] = makeEntry(1, "urgent", false,
        "編集中 🧪, <b>literal markup stays text</b> — very long title")
      setStoreRows(rowsUrgent)
      captureEntries = rowsUrgent
      captureSelectedIndex = 0
      captureLabel = "Needs attention"
      captureMessage = "A minimized window is asking for attention"
      requestCapture("urgent")
    } else if (screenshotStep === 4) {
      var rowsLong = entries(100)
      rowsLong[97] = makeEntry(98, "updated", false, "Background build output changed")
      rowsLong[99] = makeEntry(100, "none", false, "Selected final window")
      setStoreRows(rowsLong)
      captureEntries = rowsLong
      captureSelectedIndex = 99
      captureLabel = "Long list"
      captureMessage = "100 minimized windows · row 100 selected and contained"
      Qt.callLater(function() {
        captureList.positionViewAtIndex(99, ListView.Contain)
        Qt.callLater(function() { harness.requestCapture("long-list") })
      })
    } else if (screenshotStep === 5) {
      capturePage = "help"
      captureLabel = "Help"
      captureMessage = "How minimizing and restoring works"
      requestCapture("help")
    } else if (screenshotStep === 6) {
      capturePage = "shortcuts"
      captureLabel = "Shortcuts"
      captureMessage = "Record a keyboard combination or mouse button"
      captureShortcutSettings.syncFromStore(true)
      fixtureStore.shortcutBusy = false
      fixtureStore.shortcutPendingKind = ""
      fixtureStore.shortcutCheckKnown = true
      fixtureStore.shortcutPairAvailable = false
      fixtureStore.shortcutMinimizeCheck = ({ input: "SUPER + M", binding: "SUPER + M",
        valid: true, available: false, conflicts: ["Omamail"], message: "" })
      fixtureStore.shortcutSidebarCheck = ({ input: "SUPER + ALT + M", binding: "SUPER + ALT + M",
        valid: true, available: true, conflicts: [], message: "" })
      requestCapture("shortcuts")
    } else if (screenshotStep === 7) {
      fixtureStore.shortcutBusy = false
      fixtureStore.shortcutPendingKind = ""
      captureLabel = "Record shortcut"
      captureMessage = "Listening for one safe trigger"
      expect(captureShortcutSettings.startRecording("minimize"),
        "recording overlay could not be opened for visual verification")
      requestCapture("recording")
    } else {
      console.info("OMARCHY_MINIMIZE_UI_PASS")
    }
  }

  QtObject {
    id: fixtureStore

    property var entries: []
    property bool loaded: true
    property bool stateReady: true
    property bool loadingState: false
    property bool busy: false
    property bool supported: true
    property bool compositorSupported: true
    property string unsupportedReason: ""
    property string lastError: ""
    property string lastOperation: "Ready"
    property var pendingAction: null
    property var unavailableOrigins: []
    property int queryCount: 0
    property var calls: []
    property bool shortcutStateKnown: true
    property bool shortcutConfigured: true
    property bool shortcutBusy: false
    property string shortcutPendingKind: ""
    property string minimizeShortcut: "SUPER + M"
    property string sidebarShortcut: "SUPER + ALT + M"
    property string shortcutLastOperation: "Shortcut settings loaded."
    property string shortcutLastError: ""
    property bool shortcutCheckKnown: false
    property bool shortcutPairAvailable: false
    property var shortcutMinimizeCheck: ({})
    property var shortcutSidebarCheck: ({})
    property string shortcutCheckError: ""
    signal operationFinished(string code, bool ok)
    signal shortcutOperationFinished(string code, bool ok)
    readonly property int count: entries.length
    readonly property int urgentCount: {
      var total = 0
      for (var i = 0; i < entries.length; i++) if (entries[i].attention === "urgent") total++
      return total
    }
    readonly property int updatedCount: {
      var total = 0
      for (var i = 0; i < entries.length; i++) if (entries[i].attention === "updated") total++
      return total
    }

    function record(name, address, target) {
      var next = calls.slice(0)
      var destination = target && target.name !== undefined ? String(target.name) : String(target || "")
      next.push({ name: name, address: String(address || ""), target: destination })
      calls = next
      return { ok: true, code: "queued" }
    }
    function minimize() { return record("minimize", "", "") }
    function restore(address, target) { return record("restore", address, target) }
    function restoreOrigin(address, target) { return record("restoreOrigin", address, target || "origin") }
    function restoreHere(address, target) { return record("restoreHere", address, target) }
    function restoreLast(target) { return record("restoreLast", "", target) }
    function restoreAll(target) { return record("restoreAll", "", target) }
    function acknowledge(address) { return record("acknowledge", address, "") }
    function reconcileNow() { return record("reconcile", "", "") }
    function refreshShortcutStatus() {
      if (shortcutBusy) return { ok: false, code: "shortcut-busy" }
      return record("shortcut-status", "", "")
    }
    function checkShortcuts(minimizeBinding, sidebarBinding) {
      if (shortcutBusy) return { ok: false, code: "shortcut-busy" }
      shortcutBusy = true
      shortcutPendingKind = "check"
      return record("shortcut-check", minimizeBinding, sidebarBinding)
    }
    function saveShortcuts(minimizeBinding, sidebarBinding) {
      if (shortcutBusy) return { ok: false, code: "shortcut-busy" }
      shortcutBusy = true
      return record("shortcut-apply", minimizeBinding, sidebarBinding)
    }
    function removeShortcuts() {
      if (shortcutBusy) return { ok: false, code: "shortcut-busy" }
      shortcutBusy = true
      return record("shortcut-remove", "", "")
    }
    function originAvailable(origin) {
      return unavailableOrigins.indexOf(String(origin || "")) === -1
    }
  }

  QtObject {
    id: fakeShell
    property int serviceLookups: 0
    function serviceFor(name) {
      serviceLookups++
      return name === "osouthgate.minimize" ? fixtureStore : null
    }
  }

  QtObject {
    id: fakeBar
    property var shell: fakeShell
    property color foreground: Color.bar.text
    property color barForeground: foreground
    property color urgent: Color.urgent
    property color background: Color.bar.background
    property string fontFamily: Style.font.family
    property string position: "top"
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property int barSize: Style.bar.sizeHorizontal
    property var switchDirections: []
    function switchPanelFrom(panel, direction) {
      var next = switchDirections.slice(0)
      next.push(direction)
      switchDirections = next
      return true
    }
    function showTooltip(item, text) { }
    function hideTooltip(item) { }
    function registerClickTarget(item) { }
    function unregisterClickTarget(item) { }
    function run(command) { }
  }

  Panel {
    id: panelA
    bar: fakeBar
    testWorkspaceOverride: "3"
    testScreenWidth: 520
    testScreenHeight: 600
    settings: ({ panelWidth: 440 })
  }

  Panel {
    id: panelB
    bar: fakeBar
    testWorkspaceOverride: "8"
    testScreenWidth: 520
    testScreenHeight: 600
    settings: ({ panelWidth: 440 })
  }

  // A directly loaded production row supplies exact state/metadata assertions.
  WindowRow {
    id: rowProbe
    visible: false
    width: 440
    entry: harness.rowFixture
    rowIndex: 0
    nowMs: 1735693200000
  }

  Window {
    id: captureWindow
    visible: true
    width: 520
    height: 600
    color: Color.background
    title: "Omarchy Minimize UI fixture"

    Item {
      id: captureRoot
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        color: Color.background
      }

      Rectangle {
        id: captureCard
        anchors.fill: parent
        anchors.margins: Style.spacing.huge
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: Style.spacing.hairline
        border.color: Color.popups.border

        Column {
          id: captureColumn
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.lg

          Row {
            id: captureHeader
            width: parent.width
            spacing: Style.spacing.xl

            Text {
              width: parent.width - badge.width - parent.spacing
              textFormat: Text.PlainText
              text: harness.captureLabel
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideRight
            }

            Rectangle {
              id: badge
              width: Math.max(Style.space(48), captureBadgeText.implicitWidth + Style.spacing.xl)
              height: Style.spacing.controlHeight
              radius: Style.cornerRadius
              color: fixtureStore.urgentCount > 0 ? Color.urgent
                : fixtureStore.updatedCount > 0 ? Color.accent : Color.popups.border

              Text {
                id: captureBadgeText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: String(fixtureStore.count)
                color: Color.background
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
          }

          Text {
            id: captureMessageText
            width: parent.width
            textFormat: Text.PlainText
            text: harness.captureMessage
            color: Color.popups.text
            opacity: 0.68
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            visible: text.length > 0
          }

          Item {
            id: captureBody
            width: parent.width
            height: Math.max(0, captureColumn.height - captureHeader.height
              - (captureMessageText.visible ? captureMessageText.implicitHeight : 0)
              - captureColumn.spacing * (captureMessageText.visible ? 2 : 1))

            ListView {
              id: captureList
              anchors.fill: parent
              clip: true
              visible: harness.capturePage === "windows"
              model: harness.captureEntries
              spacing: Style.spacing.sm
              currentIndex: harness.captureSelectedIndex
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick
              interactive: contentHeight > height
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              delegate: WindowRow {
                required property var modelData
                required property int index
                width: captureList.width
                  - (captureList.contentHeight > captureList.height ? Style.space(10) : 0)
                entry: modelData
                rowIndex: index
                selected: index === harness.captureSelectedIndex
                originAvailable: fixtureStore.originAvailable(modelData.origin)
                nowMs: 1735693200000
                rowForeground: Color.popups.text
                rowFontFamily: Style.font.family
              }
            }

            Text {
              visible: harness.capturePage === "windows" && harness.captureEntries.length === 0
              anchors.centerIn: parent
              width: parent.width
              textFormat: Text.PlainText
              text: "Nothing is hidden right now"
              color: Color.popups.text
              opacity: 0.58
              horizontalAlignment: Text.AlignHCenter
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
            }

            HelpView {
              anchors.fill: parent
              visible: harness.capturePage === "help"
              foreground: Color.popups.text
              fontFamily: Style.font.family
            }

            ShortcutSettingsView {
              id: captureShortcutSettings
              anchors.fill: parent
              visible: harness.capturePage === "shortcuts"
              store: fixtureStore
              foreground: Color.popups.text
              fontFamily: Style.font.family
            }
          }
        }
      }
    }
  }

  Timer {
    id: startTimer
    interval: 30
    repeat: false
    onTriggered: harness.runAssertions()
  }

  Timer {
    id: layoutTimer
    interval: 120
    repeat: false
    onTriggered: harness.runLayoutAssertions()
  }

  Timer {
    id: captureTimer
    interval: 80
    repeat: false
    onTriggered: harness.advanceCapture()
  }

  Component.onCompleted: startTimer.start()
}
