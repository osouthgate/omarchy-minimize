import QtQuick
import Quickshell

// Real installed-Ui compatibility gate. The drawer stays closed, so this
// instantiates KeyboardPanel's actual Wayland backend without mapping a test
// surface or issuing any compositor mutation.
ShellRoot {
  id: harness

  property bool failed: false

  function expect(condition, message) {
    if (condition || failed) return
    failed = true
    console.warn("OMARCHY_MINIMIZE_NATIVE_ERROR " + message)
  }

  QtObject {
    id: fixtureStore
    property var entries: []
    property bool stateReady: true
    property bool loadingState: false
    property bool busy: false
    property string lastError: ""
    property string lastOperation: "Ready"
    property var pendingAction: null
    property bool shortcutStateKnown: true
    property bool shortcutConfigured: false
    property bool shortcutBusy: false
    property string minimizeShortcut: ""
    property string sidebarShortcut: ""
    property string shortcutLastOperation: "Optional shortcuts are not configured."
    property string shortcutLastError: ""
    signal shortcutOperationFinished(string code, bool ok)
    readonly property int count: 0
    readonly property int urgentCount: 0
    readonly property int updatedCount: 0
    function reconcileNow() { return { ok: true } }
    function refreshShortcutStatus() { return { ok: true } }
    function saveShortcuts(minimizeBinding, sidebarBinding) { return { ok: true } }
    function removeShortcuts() { return { ok: true } }
  }

  QtObject {
    id: fakeBar
    property var shell: null
    property color foreground: "#e6e9ef"
    property color barForeground: foreground
    property color urgent: "#ff6b8b"
    property string fontFamily: "sans-serif"
    property string position: "top"
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property int barSize: 44
    function showTooltip(item, text) { }
    function hideTooltip(item) { }
    function registerClickTarget(item) { }
    function unregisterClickTarget(item) { }
  }

  Panel {
    id: panel
    bar: fakeBar
    testStore: fixtureStore
    testWorkspaceOverride: "5"
    testScreenWidth: 1280
    testScreenHeight: 720
    settings: ({ panelWidth: 440 })
  }

  WindowRow {
    id: row
    visible: false
    width: 440
    rowIndex: 0
    nowMs: 1735693200000
    entry: ({
      address: "0x1001",
      title: "Native UI load",
      className: "foot",
      sourceWorkspace: "special:minimum",
      origin: "5",
      minimizedAt: 1735693140000,
      attention: "none",
      recovered: false
    })
  }

  Timer {
    interval: 60
    running: true
    repeat: false
    onTriggered: {
      harness.expect(!panel.opened, "real KeyboardPanel mapped unexpectedly")
      harness.expect(panel.panelWidthPx === 440, "real KeyboardPanel width contract drifted")
      harness.expect(panel.rightEdgeAnchorX === 1000000, "real fixed-edge anchor drifted")
      harness.expect(row.renderedTitleFormat === Text.PlainText, "real WindowRow did not load")
      harness.expect(panel.helpViewObject !== null
        && String(panel.helpViewObject.Accessible.name) === "Omarchy Minimize help",
        "real HelpView did not load with its accessibility contract")
      harness.expect(panel.shortcutViewObject.stateKind === "absent",
        "real ShortcutSettingsView did not load")
      if (!harness.failed) console.info("OMARCHY_MINIMIZE_NATIVE_PASS closed-real-KeyboardPanel")
    }
  }
}
