import QtQuick
import QtQuick.Controls
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Per-monitor bar surface backed by one session-wide Service.qml instance.
// Every copy reads the same entries; only the restore-here workspace comes
// from the screen whose button opened the panel.
Panel {
  id: root

  moduleName: "osouthgate.minimize"
  ipcTarget: ""
  manageIpc: false

  property var service: null
  property var store: null

  // Deterministic UI harness injection. Production leaves these null/zero.
  property var testStore: null
  property var testWorkspaceOverride: null
  property int testScreenWidth: 0
  property int testScreenHeight: 0

  property int selectedIndex: 0
  property bool cursorActive: false
  property double nowMs: Date.now()
  property string feedbackText: ""
  property bool feedbackError: false
  property string currentPage: "windows"
  // Set only by a successfully queued single-window restore. The drawer stays
  // visible while the transaction is pending and closes once that exact kind
  // of operation completes successfully; failures remain visible in place.
  property string pendingAutoCloseAddress: ""

  readonly property var effectiveStore: testStore || service || store
  readonly property var visibleEntries: effectiveStore && effectiveStore.entries
    ? effectiveStore.entries : []
  readonly property int globalCount: effectiveStore && typeof effectiveStore.count === "number"
    ? effectiveStore.count : visibleEntries.length
  readonly property int globalUrgentCount: effectiveStore
    && typeof effectiveStore.urgentCount === "number" ? effectiveStore.urgentCount : countState("urgent")
  readonly property int globalUpdatedCount: effectiveStore
    && typeof effectiveStore.updatedCount === "number" ? effectiveStore.updatedCount : countState("updated")
  readonly property string indicatorState: globalUrgentCount > 0 ? "urgent"
    : globalUpdatedCount > 0 ? "updated" : globalCount > 0 ? "minimized" : "empty"
  readonly property bool serviceLoading: !effectiveStore
    || effectiveStore.stateReady === false || effectiveStore.loadingState === true
  readonly property bool serviceBusy: effectiveStore && effectiveStore.busy === true
  readonly property string serviceError: effectiveStore ? String(effectiveStore.lastError || "") : ""
  readonly property bool serviceSupported: !effectiveStore
    || (effectiveStore.supported !== false && effectiveStore.compositorSupported !== false)
  readonly property string unsupportedReason: effectiveStore
    ? String(effectiveStore.unsupportedReason || "This compositor cannot provide safe window identities.") : ""
  readonly property bool recoveryRetryAvailable: serviceBusy && effectiveStore
    && effectiveStore.pendingAction
    && (String(effectiveStore.pendingAction.stage || "") === "recovery-cleanup"
      || String(effectiveStore.pendingAction.stage || "") === "recovery-protect")
  readonly property string badgeText: globalCount > 99 ? "99+" : String(globalCount)
  readonly property real badgeReservedWidth: button.slotSize
  readonly property int configuredPanelWidth: Math.max(320,
    Math.min(720, Number(setting("panelWidth", 440)) || 440))
  readonly property real panelWidthPx: popup.contentWidth
  readonly property real panelHeightPx: popup.contentHeight
  readonly property real rightEdgeAnchorX: rightAnchor.x
  readonly property bool keyInputBlocked: currentPage === "shortcuts" && shortcutView.editing
  readonly property var helpViewObject: helpView
  readonly property var shortcutViewObject: shortcutView
  readonly property real nonListContentHeight: {
    var total = header.height
    var blocks = 1
    if (stateText.visible) { total += stateText.implicitHeight; blocks++ }
    if (windowList.visible) blocks++
    if (listSeparator.visible) { total += listSeparator.implicitHeight; blocks++ }
    if (footer.visible) { total += footer.implicitHeight; blocks++ }
    return total + Math.max(0, blocks - 1) * panelContent.spacing
  }
  readonly property real windowsContentImplicitHeight: nonListContentHeight
    + (windowList.visible ? windowList.height : 0)
  readonly property real drawerContentImplicitHeight: currentPage === "help"
    ? header.height + panelContent.spacing + helpView.implicitHeight
    : currentPage === "shortcuts"
      ? header.height + panelContent.spacing + shortcutView.implicitHeight
      : windowsContentImplicitHeight
  readonly property real listContentHeight: windowList.contentHeight
  readonly property real listViewportHeight: windowList.height
  readonly property string stateMessage: {
    if (!effectiveStore) return "Connecting to the minimize service…"
    if (serviceLoading) return "Loading minimized windows…"
    if (!serviceSupported) return "Unsupported · " + unsupportedReason
      + " Move the window to a normal workspace or close this panel."
    if (serviceError) return "Couldn’t update minimized windows · " + serviceError
      + (serviceError.toLowerCase().indexOf("reconcile") === -1 ? " Choose Reconcile to retry." : "")
    if (feedbackError && feedbackText) return feedbackText
    if (serviceBusy && globalCount === 0) {
      var operation = String(effectiveStore.lastOperation || "")
      return operation || "A window transition is pending…"
    }
    if (feedbackText) return feedbackText
    if (globalCount === 0) return "Nothing is minimized\nRight-click the bar icon or use your configured minimize shortcut."
    return ""
  }
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function countState(attention) {
    var total = 0
    for (var i = 0; i < visibleEntries.length; i++)
      if (String(visibleEntries[i].attention || "") === attention) total++
    return total
  }

  function bindStore() {
    if (testStore || service || store) return
    var host = bar && bar.shell ? bar.shell : null
    if (host && typeof host.serviceFor === "function")
      store = host.serviceFor("osouthgate.minimize")
  }

  function pushSettings() {
    if (!effectiveStore) return
    var timeout = Math.max(500, Math.min(5000,
      Number(setting("transitionTimeoutMs", 1800)) || 1800))
    if ("transitionTimeoutMs" in effectiveStore) effectiveStore.transitionTimeoutMs = timeout
  }

  function workspaceSnapshot(workspace) {
    if (!workspace) return null
    if (typeof workspace === "string" || typeof workspace === "number")
      return ({ id: Number(workspace) || 0, name: String(workspace) })
    return ({
      id: Number(workspace.id) || 0,
      name: String(workspace.name === undefined ? "" : workspace.name)
    })
  }

  function currentWorkspace() {
    if (testWorkspaceOverride) return workspaceSnapshot(testWorkspaceOverride)
    var screen = popup.screen
    var monitor = screen ? Hyprland.monitorFor(screen) : null
    if (monitor && monitor.activeWorkspace) return workspaceSnapshot(monitor.activeWorkspace)
    if (effectiveStore && typeof effectiveStore.focusedWorkspace === "function")
      return workspaceSnapshot(effectiveStore.focusedWorkspace())
    return null
  }

  function handleResult(response) {
    if (!response) {
      root.showFeedback(
        "The minimize service did not respond. Choose Reconcile; if it persists, reopen the panel.", true)
      return false
    }
    root.showFeedback(String(response.message || ""), response.ok !== true)
    return response.ok === true
  }

  function clearFeedback() {
    feedbackClearTimer.stop()
    feedbackText = ""
    feedbackError = false
  }

  function showFeedback(message, isError) {
    feedbackClearTimer.stop()
    feedbackText = String(message || "")
    feedbackError = isError === true
    if (feedbackText && !feedbackError) feedbackClearTimer.restart()
  }

  function requestMinimize() {
    if (!effectiveStore || typeof effectiveStore.minimize !== "function")
      return handleResult(null)
    return handleResult(effectiveStore.minimize())
  }

  function restoreIndex(index, restoreHereRequested) {
    if (!effectiveStore || index < 0 || index >= visibleEntries.length)
      return handleResult({ ok: false,
        message: "That minimized window is no longer available. Choose Reconcile to refresh the list." })
    var entry = visibleEntries[index]
    pendingAutoCloseAddress = String(entry.address || "")
    var response
    if (restoreHereRequested === true) {
      response = typeof effectiveStore.restoreHere === "function"
        ? effectiveStore.restoreHere(entry.address, currentWorkspace()) : null
    } else {
      var workspace = currentWorkspace()
      response = typeof effectiveStore.restore === "function"
        ? effectiveStore.restore(entry.address, workspace) : null
    }
    var accepted = handleResult(response)
    if (!accepted) pendingAutoCloseAddress = ""
    return accepted
  }

  function restoreLatest() {
    if (visibleEntries.length === 0)
      return handleResult({ ok: false, message: "There are no minimized windows." })
    var latest = 0
    for (var i = 1; i < visibleEntries.length; i++)
      if (Number(visibleEntries[i].minimizedAt || 0)
          > Number(visibleEntries[latest].minimizedAt || 0)) latest = i
    selectIndex(latest)
    return restoreIndex(latest, false)
  }

  function restoreAllHere() {
    if (!effectiveStore || typeof effectiveStore.restoreAll !== "function")
      return handleResult(null)
    return handleResult(effectiveStore.restoreAll(currentWorkspace()))
  }

  function acknowledgeIndex(index) {
    if (!effectiveStore || index < 0 || index >= visibleEntries.length)
      return handleResult({ ok: false,
        message: "That attention marker is no longer available. Choose Reconcile to refresh the list." })
    if (typeof effectiveStore.acknowledge !== "function") return handleResult(null)
    return handleResult(effectiveStore.acknowledge(visibleEntries[index].address))
  }

  function acknowledgeSelection() { return acknowledgeIndex(selectedIndex) }

  function requestReconcile() {
    if (!effectiveStore) return handleResult(null)
    var response = null
    if (typeof effectiveStore.reconcileAndRetry === "function") {
      response = effectiveStore.reconcileAndRetry()
    } else {
      if (typeof effectiveStore.reconcileNow === "function") effectiveStore.reconcileNow()
      var retried = typeof effectiveStore.retryRecovery === "function"
        && effectiveStore.retryRecovery()
      response = { ok: true, code: retried ? "recovery-retried" : "reconciled",
        message: retried ? "Retrying the guarded recovery step."
          : "Minimized windows reconciled with live state." }
    }
    return handleResult(response)
  }

  function originAvailableFor(entry) {
    var origin = String(entry && entry.origin || "")
    if (!origin) return true
    if (effectiveStore && typeof effectiveStore.originAvailable === "function")
      return effectiveStore.originAvailable(origin)
    return true
  }

  function handleBarPress(mouseButton) {
    if (mouseButton === Qt.RightButton) {
      var minimized = requestMinimize()
      if (!minimized) root.controller.show()
      return minimized
    }
    if (mouseButton === Qt.MiddleButton) {
      var restored = restoreLatest()
      if (!restored) root.controller.show()
      return restored
    }
    toggle()
    return true
  }

  function selectIndex(index) {
    if (visibleEntries.length === 0) {
      selectedIndex = 0
      cursorActive = false
      return
    }
    selectedIndex = Math.max(0, Math.min(Number(index) || 0, visibleEntries.length - 1))
    cursorActive = true
    Qt.callLater(function() {
      if (windowList && visibleEntries.length > 0)
        windowList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function moveSelection(delta) { selectIndex(selectedIndex + Number(delta || 0)) }
  function selectFirst() { selectIndex(0) }
  function selectLast() { selectIndex(visibleEntries.length - 1) }
  function activateSelection(restoreHereRequested) {
    return restoreIndex(selectedIndex, restoreHereRequested === true)
  }

  function focusForPage() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.currentPage === "shortcuts") shortcutView.focusFirstField()
      else keyCatcher.forceActiveFocus()
    })
  }

  function openHelp() {
    currentPage = "help"
    focusForPage()
    return true
  }

  function openShortcuts() {
    currentPage = "shortcuts"
    shortcutView.openPage()
    focusForPage()
    return true
  }

  function backToWindows() {
    currentPage = "windows"
    shortcutView.resetPageState()
    focusForPage()
    return true
  }

  // One semantic function makes the keyboard contract deterministic in the
  // smoke harness without synthesizing compositor keyboard focus.
  function handleSemanticKey(key, modifiers, text) {
    var mods = Number(modifiers || 0)
    if (key === Qt.Key_F1 || String(text || "") === "?") { openHelp(); return "help" }
    if (key === Qt.Key_Escape) {
      if (currentPage !== "windows") { backToWindows(); return "back" }
      close()
      return "close"
    }
    if (currentPage === "help") {
      if (key === Qt.Key_Up) { helpView.scrollBy(-Style.space(48)); return "scroll-up" }
      if (key === Qt.Key_Down) { helpView.scrollBy(Style.space(48)); return "scroll-down" }
      return "ignored"
    }
    if (currentPage !== "windows") return "ignored"
    if (key === Qt.Key_Up) { moveSelection(-1); return "up" }
    if (key === Qt.Key_Down) { moveSelection(1); return "down" }
    if (key === Qt.Key_Home) { selectFirst(); return "home" }
    if (key === Qt.Key_End) { selectLast(); return "end" }
    if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      if ((mods & Qt.ControlModifier) !== 0) {
        restoreAllHere()
        return "restore-all"
      }
      activateSelection((mods & Qt.ShiftModifier) !== 0)
      return (mods & Qt.ShiftModifier) !== 0 ? "restore-here" : "restore-origin"
    }
    if (key === Qt.Key_Space) { activateSelection(false); return "restore-origin" }
    if (key === Qt.Key_A) { acknowledgeSelection(); return "acknowledge" }
    if (key === Qt.Key_R) { requestReconcile(); return "reconcile" }
    if (key === Qt.Key_M) { requestMinimize(); return "minimize" }
    if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      switchPanel((mods & Qt.ShiftModifier) !== 0 || key === Qt.Key_Backtab ? -1 : 1)
      return "switch-panel"
    }
    return "ignored"
  }

  function open() {
    root.clearFeedback()
    bindStore()
    if (effectiveStore && typeof effectiveStore.reconcileNow === "function")
      effectiveStore.reconcileNow()
    root.controller.show()
  }

  function close() {
    pendingAutoCloseAddress = ""
    currentPage = "windows"
    shortcutView.resetPageState()
    root.controller.hide()
  }
  function toggle() { opened ? close() : open() }

  onBarChanged: { bindStore(); pushSettings() }
  onServiceChanged: pushSettings()
  onTestStoreChanged: pushSettings()
  onSettingsChanged: pushSettings()
  onVisibleEntriesChanged: {
    if (visibleEntries.length === 0) {
      selectedIndex = 0
      cursorActive = false
    } else if (selectedIndex >= visibleEntries.length) {
      selectedIndex = visibleEntries.length - 1
    }
  }
  onOpenedChanged: {
    if (opened) {
      nowMs = Date.now()
      if (visibleEntries.length > 0) selectIndex(0)
      focusForPage()
    } else {
      pendingAutoCloseAddress = ""
      currentPage = "windows"
      shortcutView.resetPageState()
    }
  }
  Component.onCompleted: { bindStore(); pushSettings() }

  Timer {
    interval: 200
    running: root.effectiveStore === null
    repeat: true
    onTriggered: root.bindStore()
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Connections {
    target: root.effectiveStore
    ignoreUnknownSignals: true
    function onOperationFinished(code, ok) {
      var closeAfterRestore = root.pendingAutoCloseAddress !== ""
        && ok === true && String(code) === "restored"
      root.pendingAutoCloseAddress = ""
      if (closeAfterRestore) {
        root.close()
        return
      }
      root.showFeedback(ok ? String(root.effectiveStore.lastOperation || "")
        : String(root.effectiveStore.lastError || code), !ok)
    }
  }

  Timer {
    id: feedbackClearTimer
    interval: 4000
    repeat: false
    onTriggered: root.clearFeedback()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uDB80\uDD13"
    active: root.globalUrgentCount > 0 || root.globalUpdatedCount > 0
    activeColor: root.globalUrgentCount > 0 ? Color.urgent : Color.accent
    tooltipText: {
      var summary = root.serviceLoading ? "Minimized windows · service loading"
        : root.globalCount === 1 ? "1 minimized window"
        : root.globalCount + " minimized windows"
      if (root.globalUrgentCount > 0) summary += " · " + root.globalUrgentCount + " need attention"
      else if (root.globalUpdatedCount > 0) summary += " · " + root.globalUpdatedCount + " updated"
      return summary + "\nLeft: open · Right: minimize · Middle: restore latest"
    }
    Accessible.role: Accessible.Button
    Accessible.name: "Minimized windows"
    Accessible.description: tooltipText
    onPressed: function(mouseButton) { root.handleBarPress(mouseButton) }
  }

  // The count overlays a fixed-size bar slot; 0, 1, and 100+ never reflow it.
  Rectangle {
    visible: root.globalCount > 0
    anchors.right: button.right
    anchors.rightMargin: Style.spacing.xs
    anchors.top: button.top
    anchors.topMargin: Style.spacing.xs
    width: Math.max(countText.implicitWidth + Style.spacing.sm, Style.space(12))
    height: Style.space(12)
    radius: height / 2
    color: root.globalUrgentCount > 0 ? Color.urgent
      : root.globalUpdatedCount > 0 ? Color.accent : root.foreground
    opacity: root.globalUrgentCount > 0 || root.globalUpdatedCount > 0 ? 1.0 : 0.72
    Accessible.ignored: true

    Text {
      id: countText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.badgeText
      color: Color.background
      font.family: root.fontFamily
      font.pixelSize: Math.max(8, Style.font.caption - Style.spacing.xs)
      font.bold: true
    }
  }

  // KeyboardPanel clamps this deliberately out-of-bounds point to the
  // screen's right edge, giving the drawer a fixed home after bar reordering.
  Item {
    id: rightAnchor
    anchors.top: button.top
    anchors.bottom: button.bottom
    x: 1000000
    width: 1
    visible: false
  }

  KeyboardPanel {
    id: popup
    anchorItem: rightAnchor
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(root.configuredPanelWidth),
      root.testScreenWidth > 0 ? Math.max(1, root.testScreenWidth - Style.space(20)) : 0)
    contentHeight: popup.fittedContentHeight(
      Math.max(Style.space(220), root.drawerContentImplicitHeight),
      root.testScreenHeight > 0 ? Math.max(160, root.testScreenHeight - Style.space(20)) : 0)

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: root.opened
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.keyInputBlocked) return
        var key = event.key
        if (event.text === "j") key = Qt.Key_Down
        else if (event.text === "k") key = Qt.Key_Up
        var handled = root.handleSemanticKey(key, event.modifiers, event.text)
        event.accepted = handled !== "ignored"
      }

      Column {
        id: panelContent
        width: parent.width
        spacing: Style.spacing.lg

        Item {
          id: header
          width: parent.width
          height: Math.max(sectionTitle.implicitHeight, headerActions.implicitHeight)

          PanelSectionHeader {
            id: sectionTitle
            anchors.left: parent.left
            anchors.right: headerActions.left
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: root.currentPage === "help" ? "HELP"
              : root.currentPage === "shortcuts" ? "SHORTCUTS" : "MINIMIZED WINDOWS"
            foreground: root.foreground
            fontFamily: root.fontFamily
            elide: Text.ElideRight
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            PanelActionButton {
              visible: root.currentPage !== "windows"
              focusable: true
              anchors.verticalCenter: parent.verticalCenter
              iconText: "←"
              tooltipText: "Back to minimized windows"
              Accessible.role: Accessible.Button
              Accessible.name: "Back to minimized windows"
              Accessible.description: tooltipText
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.backToWindows()
            }

            PanelActionButton {
              visible: root.currentPage === "windows"
              focusable: true
              anchors.verticalCenter: parent.verticalCenter
              iconText: "?"
              tooltipText: "Help"
              Accessible.role: Accessible.Button
              Accessible.name: "Open Omarchy Minimize help"
              Accessible.description: "Explain controls, restore behavior, status markers and recovery"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.openHelp()
            }

            PanelActionButton {
              visible: root.currentPage === "windows"
              focusable: true
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰌌"
              tooltipText: "Configure shortcuts"
              Accessible.role: Accessible.Button
              Accessible.name: "Configure minimize shortcuts"
              Accessible.description: "Open shortcut settings for keyboard and mouse bindings"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.openShortcuts()
            }

            PanelActionButton {
              visible: root.currentPage === "windows"
              focusable: true
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\uDB81\uDD17"
              tooltipText: "Reconcile with live windows"
              Accessible.role: Accessible.Button
              Accessible.name: "Reconcile minimized windows"
              Accessible.description: tooltipText
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.effectiveStore !== null
                && (!root.serviceBusy || root.recoveryRetryAvailable)
              onClicked: root.requestReconcile()
            }

            PanelActionButton {
              visible: root.currentPage === "windows"
              focusable: true
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰑐"
              tooltipText: "Restore every listed window to this screen's active workspace"
              Accessible.role: Accessible.Button
              Accessible.name: "Restore all minimized windows here"
              Accessible.description: tooltipText
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.globalCount > 0 && !root.serviceBusy
              onClicked: root.restoreAllHere()
            }
          }
        }

        Text {
          id: stateText
          visible: root.currentPage === "windows" && root.stateMessage !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.stateMessage
          color: root.feedbackError || root.serviceError !== "" ? Color.urgent : root.foreground
          opacity: root.feedbackError || root.serviceError !== "" ? 1.0 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          topPadding: Style.spacing.xl
          bottomPadding: Style.spacing.xl
        }

        ListView {
          id: windowList
          width: parent.width
          readonly property real heightCap: {
            if (root.testScreenHeight > 0)
              return Math.max(0, root.testScreenHeight - Style.space(20)
                - popup.verticalContentInset - root.nonListContentHeight)
            if (popup.availableCardHeight > 0)
              return Math.max(0, popup.availableCardHeight
                - popup.verticalContentInset - root.nonListContentHeight)
            return Style.space(460)
          }
          height: Math.min(contentHeight, heightCap)
          visible: root.currentPage === "windows" && root.visibleEntries.length > 0
          clip: true
          model: root.visibleEntries
          spacing: Style.spacing.sm
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: WindowRow {
            id: row
            required property var modelData
            required property int index
            width: windowList.width - (windowList.contentHeight > windowList.height ? Style.space(10) : 0)
            entry: modelData
            rowIndex: index
            selected: root.cursorActive && root.selectedIndex === index
            pending: root.effectiveStore && root.effectiveStore.pendingAction
              && String(root.effectiveStore.pendingAction.address || "") === String(modelData.address || "")
            nowMs: root.nowMs
            originAvailable: root.originAvailableFor(modelData)
            rowForeground: root.foreground
            rowFontFamily: root.fontFamily
            onSelectionRequested: function(requestedIndex) { root.selectIndex(requestedIndex) }
            onRestoreRequested: function(restoreHereRequested) {
              root.restoreIndex(index, restoreHereRequested)
            }
            onAcknowledgeRequested: root.acknowledgeIndex(index)
          }
        }

        PanelSeparator {
          id: listSeparator
          visible: root.currentPage === "windows" && root.visibleEntries.length > 0
          width: parent.width
          foreground: root.foreground
        }

        Text {
          id: footer
          width: parent.width
          visible: root.currentPage === "windows" && root.visibleEntries.length > 0
          textFormat: Text.PlainText
          text: "Enter: original workspace · Shift+Enter: restore here · A: clear marker · Ctrl+Enter: all here · Esc: close"
          color: root.foreground
          opacity: 0.68
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        HelpView {
          id: helpView
          width: parent.width
          height: Math.min(implicitHeight, Math.max(Style.space(180),
            root.testScreenHeight > 0
              ? root.testScreenHeight - Style.space(20) - popup.verticalContentInset
                - header.height - panelContent.spacing
              : popup.availableCardHeight - popup.verticalContentInset
                - header.height - panelContent.spacing))
          visible: root.currentPage === "help"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onConfigureShortcutsRequested: root.openShortcuts()
          onBackRequested: root.backToWindows()
        }

        ShortcutSettingsView {
          id: shortcutView
          width: parent.width
          height: Math.min(implicitHeight, Math.max(Style.space(180),
            root.testScreenHeight > 0
              ? root.testScreenHeight - Style.space(20) - popup.verticalContentInset
                - header.height - panelContent.spacing
              : popup.availableCardHeight - popup.verticalContentInset
                - header.height - panelContent.spacing))
          visible: root.currentPage === "shortcuts"
          store: root.effectiveStore
          foreground: root.foreground
          fontFamily: root.fontFamily
          onBackRequested: root.backToWindows()
          onHelpRequested: root.openHelp()
        }
      }
    }
  }
}
