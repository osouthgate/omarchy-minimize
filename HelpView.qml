import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property real contentImplicitHeight: helpColumn.implicitHeight
  readonly property bool scrollable: helpColumn.implicitHeight > height
  readonly property string coverageText: mentalModel.text + " " + barActions.text + " "
    + restoreActions.text + " " + attention.text + " " + limits.text + " " + recovery.text

  signal configureShortcutsRequested()
  signal backRequested()

  function scrollBy(delta) {
    var target = scrollArea.contentItem
    if (!target) return
    target.contentY = Math.max(0, Math.min(target.contentHeight - target.height,
      target.contentY + Number(delta || 0)))
  }

  implicitHeight: Math.min(contentImplicitHeight, Style.space(500))
  Accessible.role: Accessible.Pane
  Accessible.name: "Omarchy Minimize help"
  Accessible.description: "Instructions for minimizing, restoring, attention markers, limitations and recovery"

  ScrollView {
    id: scrollArea
    anchors.fill: parent
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: root.scrollable ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

    Column {
      id: helpColumn
      width: scrollArea.availableWidth
      spacing: Style.spacing.lg

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Hide a window without stopping it"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        wrapMode: Text.WordWrap
      }

      Text {
        id: mentalModel
        width: parent.width
        textFormat: Text.PlainText
        text: "Minimize moves the window to a private special workspace. The application keeps running; its window is simply hidden until you restore it."
        color: root.foreground
        opacity: 0.78
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Button {
        id: configureButton
        width: parent.width
        text: "Configure shortcuts"
        iconText: "󰌌"
        bordered: true
        focusable: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        Accessible.role: Accessible.Button
        Accessible.name: "Configure minimize shortcuts"
        Accessible.description: "Open the shortcut settings page"
        onClicked: root.configureShortcutsRequested()
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Bar controls"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        id: barActions
        width: parent.width
        textFormat: Text.PlainText
        text: "Left-click opens this sidebar. Right-click minimizes the focused window. Middle-click restores the most recently minimized window."
        color: root.foreground
        opacity: 0.78
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Restore controls"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        id: restoreActions
        width: parent.width
        textFormat: Text.PlainText
        text: "Click a row, press Enter or Space to restore to its original workspace and monitor. If that origin no longer exists, it safely falls back to this screen's active workspace. Shift+click or Shift+Enter deliberately restores here. The sidebar closes after one window restores successfully, but stays open if restoration fails. Ctrl+Enter restores every listed window here and keeps the sidebar open. A clears an attention marker; R reconciles; M minimizes; Esc closes. F1 or ? opens Help."
        color: root.foreground
        opacity: 0.78
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "What the markers mean"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        id: attention
        width: parent.width
        textFormat: Text.PlainText
        text: "Updated only means the window title changed while hidden. Needs attention means the application signalled urgency. Neither marker means a job completed or succeeded."
        color: root.foreground
        opacity: 0.78
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Shortcuts"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Choose Record beside either action, then press the keyboard combination or mouse button you want; Escape cancels. Each draft is checked immediately against live Hyprland bindings and shows Available, Invalid, or Already used by with the existing action's name. Save stays disabled until both drafts are free and rechecks them before changing anything. Manual chords such as SUPER + M and mouse:276 are also accepted."
        color: root.foreground
        opacity: 0.78
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Limitations"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        id: limits
        width: parent.width
        textFormat: Text.PlainText
        text: "The list accepts exactly special:minimum, special:minimized, and special:scratchpad; unrelated special workspaces are ignored. Pinned and grouped windows are intentionally unsupported because moving them cannot be made reliably reversible. Move them to a normal standalone state before minimizing."
        color: root.foreground
        opacity: 0.78
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Recovery"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        id: recovery
        width: parent.width
        textFormat: Text.PlainText
        text: "Choose Reconcile to compare the list with live windows and retry guarded recovery. If a window remains hidden after the plugin stops, move it from special:minimum with Hyprland's workspace tools, then reopen the sidebar and Reconcile."
        color: root.foreground
        opacity: 0.78
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        bottomPadding: Style.spacing.lg
      }
    }
  }
}
