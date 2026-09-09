import QtQuick
import qs.Commons

// Headless stand-in for qs.Ui.KeyboardPanel. Production Panel.qml still owns
// all drawer content, navigation and sizing; this fixture replaces only the
// Wayland PanelWindow transport that cannot exist on Qt's offscreen backend.
Item {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property bool open: false
  property Item focusTarget: null
  property var screen: null
  property real availableCardHeight: 580
  property real verticalContentInset: padding * 2

  default property alias contentItem: contentHolder.children

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    if (cap !== undefined && Number(cap) > 0) desired = Math.min(desired, Number(cap))
    return Math.round(desired)
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(verticalContentInset,
      (Number(implicitHeight) || 0) + verticalContentInset)
    if (cap !== undefined && Number(cap) > 0) desired = Math.min(desired, Number(cap))
    return Math.round(desired)
  }

  visible: open
  width: contentWidth
  height: contentHeight

  Item {
    id: contentHolder
    anchors.fill: parent
  }
}
