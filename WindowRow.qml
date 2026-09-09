import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// One compositor-backed minimized window. The row never polls Hyprland: all
// display state is supplied by the singleton service through Panel.qml.
CursorSurface {
  id: root

  required property var entry
  required property int rowIndex
  property bool selected: false
  property bool pending: false
  property bool originAvailable: true
  property double nowMs: Date.now()
  property color rowForeground: Color.foreground
  property string rowFontFamily: Style.font.family

  signal selectionRequested(int index)
  signal restoreRequested(bool restoreHereRequested)
  signal acknowledgeRequested()

  readonly property string address: String(entry && entry.address || "")
  readonly property string title: String(entry && entry.title || "Untitled window")
  readonly property string className: String(entry && entry.className || "Application")
  readonly property string attention: String(entry && entry.attention || "none")
  readonly property bool recovered: entry && entry.recovered === true
  readonly property bool hasRememberedOrigin: String(entry && entry.origin || "") !== ""
  readonly property string visibleStateLabel: pending ? "Pending"
    : attention === "urgent" ? "Needs attention"
    : attention === "updated" ? "Updated"
    : recovered ? "Recovered"
    : hasRememberedOrigin && !originAvailable ? "Origin unavailable" : "Minimized"
  readonly property color stateColor: attention === "urgent" ? Color.urgent
    : (pending || attention === "updated") ? Color.accent
    : Qt.rgba(rowForeground.r, rowForeground.g, rowForeground.b, 0.55)
  readonly property string iconName: /^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/.test(className)
    ? className : ""
  readonly property string iconSource: iconName ? Quickshell.iconPath(iconName, true) : ""
  readonly property bool hasIcon: iconSource !== "" && appIcon.status === Image.Ready
  readonly property string fallbackInitial: className.length > 0
    ? className.charAt(0).toUpperCase() : "?"
  readonly property string sourceLabel: sourceText(entry)
  readonly property string elapsedLabel: elapsedTextFor(nowMs, Number(entry && entry.minimizedAt || 0))
  readonly property string tooltipTitle: title.length > 72 ? title.slice(0, 71) + "…" : title
  readonly property int renderedTitleFormat: titleText.textFormat

  function sourceText(value) {
    var source = String(value && value.sourceWorkspace || "")
    var alias = source === "special:minimum" ? "Minimum"
      : source === "special:minimized" ? "Dock minimized"
      : source === "special:scratchpad" ? "Scratchpad"
      : (source || "Hidden workspace")
    var origin = String(value && value.origin || "")
    if (origin && !root.originAvailable) return "Workspace " + origin + " unavailable · " + alias
    return origin ? "Workspace " + origin + " · " + alias : alias
  }

  function elapsedTextFor(now, then) {
    if (!then || !isFinite(then)) return "just now"
    var age = Math.max(0, Number(now) - then)
    if (age < 60000) return "just now"
    if (age < 3600000) return Math.floor(age / 60000) + "m"
    if (age < 86400000) return Math.floor(age / 3600000) + "h"
    return Math.floor(age / 86400000) + "d"
  }

  hasCursor: selected
  current: false
  bordered: true
  foreground: rowForeground
  implicitHeight: Math.max(Style.space(76), details.implicitHeight + Style.spacing.xxl)
  opacity: pending ? 0.72 : 1.0
  Accessible.role: Accessible.Button
  Accessible.name: root.title
  Accessible.description: root.className + " · " + root.visibleStateLabel + " · " + root.sourceLabel
  Accessible.selected: root.selected

  Item {
    id: avatar
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.lg
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(34)
    height: width

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Qt.rgba(root.rowForeground.r, root.rowForeground.g, root.rowForeground.b, 0.1)
    }

    Text {
      anchors.centerIn: parent
      visible: !root.hasIcon
      textFormat: Text.PlainText
      text: root.fallbackInitial
      color: root.rowForeground
      opacity: 0.72
      font.family: root.rowFontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Image {
      id: appIcon
      anchors.fill: parent
      visible: root.hasIcon
      source: root.iconSource
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      Accessible.ignored: true
    }
  }

  Column {
    id: details
    anchors.left: avatar.right
    anchors.leftMargin: Style.spacing.lg
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.lg
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xxs

    Item {
      width: parent.width
      height: Math.max(titleText.implicitHeight, stateText.implicitHeight)

      Text {
        id: titleText
        anchors.left: parent.left
        anchors.right: stateText.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.title
        color: root.rowForeground
        font.family: root.rowFontFamily
        font.pixelSize: Style.font.body
        font.bold: root.attention === "urgent" || root.attention === "updated"
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      Text {
        id: stateText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.visibleStateLabel
        color: root.stateColor
        font.family: root.rowFontFamily
        font.pixelSize: Style.font.caption
        font.bold: root.attention === "urgent"
      }
    }

    Item {
      width: parent.width
      height: Math.max(classText.implicitHeight, elapsedText.implicitHeight)

      Text {
        id: classText
        anchors.left: parent.left
        anchors.right: elapsedText.left
        anchors.rightMargin: Style.spacing.lg
        textFormat: Text.PlainText
        text: root.className
        color: root.rowForeground
        opacity: 0.68
        font.family: root.rowFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        id: elapsedText
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.elapsedLabel
        color: root.rowForeground
        opacity: 0.68
        font.family: root.rowFontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.sourceLabel
      color: root.rowForeground
      opacity: 0.68
      font.family: root.rowFontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: root.pending ? Qt.ArrowCursor : Qt.PointingHandCursor
    enabled: !root.pending
    onContainsMouseChanged: if (containsMouse) root.selectionRequested(root.rowIndex)
    onClicked: function(mouse) {
      root.selectionRequested(root.rowIndex)
      if (mouse.button === Qt.RightButton) root.acknowledgeRequested()
      else root.restoreRequested((mouse.modifiers & Qt.ShiftModifier) !== 0)
    }
  }

  PanelToolTip {
    visible: rowHover.hovered && titleText.truncated
    text: root.tooltipTitle
      + "\nClick: original workspace · Shift-click: restore here · Right-click: clear marker"
    fontFamily: root.rowFontFamily
  }

  HoverHandler { id: rowHover }
}
