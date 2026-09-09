import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  property var store: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool dirty: false
  property bool syncing: false
  property bool removeConfirmation: false
  property string localFeedback: ""
  property bool localError: false
  property string pendingKind: ""
  property bool focusRequested: false
  property string recordingAction: ""
  property string recordingHint: ""

  readonly property bool editing: focusRequested || recordingAction !== ""
    || minimizeField.activeFocus || sidebarField.activeFocus
  readonly property bool sharedBusy: store && store.shortcutBusy === true
  readonly property bool checking: sharedBusy && String(store.shortcutPendingKind || "") === "check"
  readonly property bool sharedKnown: store && store.shortcutStateKnown === true
  readonly property bool sharedConfigured: store && store.shortcutConfigured === true
  readonly property string minimizeDraft: minimizeField.text
  readonly property string sidebarDraft: sidebarField.text
  readonly property var minimizeCheck: store && store.shortcutMinimizeCheck
    ? store.shortcutMinimizeCheck : ({})
  readonly property var sidebarCheck: store && store.shortcutSidebarCheck
    ? store.shortcutSidebarCheck : ({})
  readonly property bool checkMatchesDrafts: store && store.shortcutCheckKnown === true
    && String(minimizeCheck.input || "") === minimizeDraft
    && String(sidebarCheck.input || "") === sidebarDraft
  readonly property bool canSave: dirty && !sharedBusy && recordingAction === ""
    && checkMatchesDrafts && store && store.shortcutPairAvailable === true
  readonly property real contentImplicitHeight: settingsColumn.implicitHeight
  readonly property bool scrollable: settingsColumn.implicitHeight > height
  readonly property string stateKind: sharedBusy ? "busy"
    : String(store && store.shortcutLastError || "") !== "" ? "error"
    : !sharedKnown ? "loading"
    : localFeedback !== "" && !localError ? "success"
    : sharedConfigured ? "configured" : "absent"
  readonly property string stateText: {
    if (checking) return "Checking live Hyprland bindings…"
    if (sharedBusy) return "Applying shortcut settings…"
    var error = String(store && store.shortcutLastError || "")
    if (error) return "Couldn’t update shortcuts · " + error
    if (!sharedKnown) return "Loading shortcut settings…"
    if (localFeedback) return localFeedback
    return sharedConfigured ? "Shortcuts are configured." : "No plugin-owned shortcuts are configured."
  }

  signal backRequested()
  signal helpRequested()

  implicitHeight: Math.min(contentImplicitHeight, Style.space(560))
  Accessible.role: Accessible.Pane
  Accessible.name: "Shortcut settings"
  Accessible.description: "Record, check, and configure the minimize-window and open-sidebar bindings"

  function trim(value) {
    return String(value || "").trim()
  }

  function syncFromStore(force) {
    if (!store || (dirty && force !== true)) return false
    syncing = true
    minimizeField.text = store.shortcutConfigured === true
      ? String(store.minimizeShortcut || "") : ""
    sidebarField.text = store.shortcutConfigured === true
      ? String(store.sidebarShortcut || "") : ""
    syncing = false
    if (force === true || !dirty) dirty = false
    scheduleCheck()
    return true
  }

  function openPage() {
    removeConfirmation = false
    recordingAction = ""
    recordingHint = ""
    localFeedback = ""
    localError = false
    if (store && typeof store.refreshShortcutStatus === "function")
      store.refreshShortcutStatus()
    else {
      localFeedback = "Shortcut service is unavailable."
      localError = true
    }
    if (!dirty) syncFromStore(false)
  }

  function draftChanged() {
    if (syncing) return
    dirty = true
    removeConfirmation = false
    localFeedback = ""
    localError = false
    scheduleCheck()
  }

  function resetSuggestions() {
    if (sharedBusy || recordingAction !== "") return false
    syncing = true
    minimizeField.text = "SUPER + M"
    sidebarField.text = "SUPER + ALT + M"
    syncing = false
    dirty = true
    removeConfirmation = false
    localFeedback = "Suggestions filled; checking whether they are available."
    localError = false
    scheduleCheck(true)
    return true
  }

  function setDrafts(minimizeValue, sidebarValue) {
    if (sharedBusy || recordingAction !== "") return false
    syncing = true
    minimizeField.text = String(minimizeValue || "")
    sidebarField.text = String(sidebarValue || "")
    syncing = false
    dirty = true
    removeConfirmation = false
    localFeedback = ""
    localError = false
    scheduleCheck(true)
    return true
  }

  function scheduleCheck(immediate) {
    checkDebounce.stop()
    if (!store || typeof store.checkShortcuts !== "function") return false
    checkDebounce.interval = immediate === true ? 1 : 300
    checkDebounce.restart()
    return true
  }

  function requestCheck() {
    if (!store || typeof store.checkShortcuts !== "function") return false
    if (sharedBusy) {
      checkDebounce.interval = 180
      checkDebounce.restart()
      return false
    }
    var response = store.checkShortcuts(minimizeDraft, sidebarDraft)
    if (!response || response.ok !== true) {
      localFeedback = String(response && response.message || "Shortcut availability could not be checked.")
      localError = true
      return false
    }
    return true
  }

  function fieldStatus(action) {
    var draft = action === "minimize" ? minimizeDraft : sidebarDraft
    var checked = action === "minimize" ? minimizeCheck : sidebarCheck
    if (recordingAction === action) return "Recording… press a keyboard shortcut or mouse button."
    if (!trim(draft)) return "Not set · choose Record or enter a shortcut."
    if (checking) return "Checking whether this shortcut is available…"
    if (!checkMatchesDrafts) return "Waiting for a live conflict check…"
    if (checked.valid !== true) return "Invalid · " + String(checked.message || "Unsupported shortcut.")
    if (checked.available !== true) {
      var conflicts = checked.conflicts || []
      if (conflicts.length > 0) return "Already used by: " + conflicts.join(", ")
      return "Unavailable · " + String(checked.message || "Choose a different shortcut.")
    }
    var canonical = String(checked.binding || draft)
    return canonical === draft ? "Available" : "Available · will save as " + canonical
  }

  function fieldProblem(action) {
    var draft = action === "minimize" ? minimizeDraft : sidebarDraft
    var checked = action === "minimize" ? minimizeCheck : sidebarCheck
    if (!trim(draft) || !checkMatchesDrafts) return false
    return checked.valid !== true || checked.available !== true
  }

  function refreshStatus() {
    if (sharedBusy || !store || typeof store.refreshShortcutStatus !== "function") return false
    localFeedback = ""
    localError = false
    var response = store.refreshShortcutStatus()
    if (!response || response.ok !== true) {
      localFeedback = String(response && response.message || "Shortcut status could not be refreshed.")
      localError = true
      return false
    }
    return true
  }

  function saveDrafts() {
    if (!canSave || !store || typeof store.saveShortcuts !== "function") return false
    pendingKind = "apply"
    removeConfirmation = false
    localFeedback = ""
    localError = false
    var response = store.saveShortcuts(minimizeDraft, sidebarDraft)
    if (!response || response.ok !== true) {
      pendingKind = ""
      localFeedback = String(response && response.message || "Shortcut settings could not be saved.")
      localError = true
      return false
    }
    return true
  }

  function requestRemove() {
    if (sharedBusy || recordingAction !== "") return false
    if (!removeConfirmation) {
      removeConfirmation = true
      localFeedback = "Choose Remove owned shortcuts again to confirm."
      localError = false
      return false
    }
    if (!store || typeof store.removeShortcuts !== "function") return false
    pendingKind = "remove"
    var response = store.removeShortcuts()
    if (!response || response.ok !== true) {
      pendingKind = ""
      localFeedback = String(response && response.message || "Plugin-owned shortcuts could not be removed.")
      localError = true
      return false
    }
    return true
  }

  function cancelRemove() {
    removeConfirmation = false
    localFeedback = "Removal cancelled."
    localError = false
  }

  function startRecording(action) {
    if (sharedBusy || (action !== "minimize" && action !== "sidebar")) return false
    checkDebounce.stop()
    recordingAction = action
    recordingHint = "Press the shortcut now. Modifier keys can be held with a key or mouse button."
    removeConfirmation = false
    localFeedback = ""
    localError = false
    Qt.callLater(function() { captureTarget.forceActiveFocus() })
    return true
  }

  function cancelRecording() {
    if (recordingAction === "") return false
    recordingAction = ""
    recordingHint = "Recording cancelled."
    return true
  }

  function modifierPrefix(modifiers) {
    var parts = []
    if ((modifiers & Qt.MetaModifier) !== 0) parts.push("SUPER")
    if ((modifiers & Qt.ControlModifier) !== 0) parts.push("CTRL")
    if ((modifiers & Qt.AltModifier) !== 0) parts.push("ALT")
    if ((modifiers & Qt.ShiftModifier) !== 0) parts.push("SHIFT")
    return parts
  }

  function keyToken(key, text) {
    if (key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt
        || key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R)
      return ""
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
    if (key >= Qt.Key_F1 && key <= Qt.Key_F35) return "F" + String(key - Qt.Key_F1 + 1)
    switch (key) {
      case Qt.Key_Space: return "SPACE"
      case Qt.Key_Tab: return "TAB"
      case Qt.Key_Backtab: return "TAB"
      case Qt.Key_Return: return "RETURN"
      case Qt.Key_Enter: return "ENTER"
      case Qt.Key_Backspace: return "BACKSPACE"
      case Qt.Key_Insert: return "INSERT"
      case Qt.Key_Delete: return "DELETE"
      case Qt.Key_Home: return "HOME"
      case Qt.Key_End: return "END"
      case Qt.Key_PageUp: return "PAGEUP"
      case Qt.Key_PageDown: return "PAGEDOWN"
      case Qt.Key_Left: return "LEFT"
      case Qt.Key_Right: return "RIGHT"
      case Qt.Key_Up: return "UP"
      case Qt.Key_Down: return "DOWN"
      case Qt.Key_Minus: return "MINUS"
      case Qt.Key_Equal: return "EQUAL"
      case Qt.Key_Plus: return "PLUS"
      case Qt.Key_BracketLeft: return "BRACKETLEFT"
      case Qt.Key_BracketRight: return "BRACKETRIGHT"
      case Qt.Key_Backslash: return "BACKSLASH"
      case Qt.Key_Semicolon: return "SEMICOLON"
      case Qt.Key_Apostrophe: return "APOSTROPHE"
      case Qt.Key_Comma: return "COMMA"
      case Qt.Key_Period: return "PERIOD"
      case Qt.Key_Slash: return "SLASH"
      case Qt.Key_QuoteLeft: return "GRAVE"
    }
    var printable = String(text || "")
    return /^[A-Za-z0-9]$/.test(printable) ? printable.toUpperCase() : ""
  }

  function keyboardChord(key, modifiers, text) {
    var token = keyToken(key, text)
    if (!token) return ""
    var parts = modifierPrefix(modifiers)
    parts.push(token)
    return parts.join(" + ")
  }

  function mouseCode(button) {
    var value = Number(button)
    if (value <= 0 || (value & (value - 1)) !== 0) return 0
    var index = 0
    while (value > 1) {
      value = Math.floor(value / 2)
      index++
    }
    return index <= 26 ? 272 + index : 0
  }

  function mouseChord(button, modifiers) {
    var code = mouseCode(button)
    if (!code) return ""
    var parts = modifierPrefix(modifiers)
    parts.push("mouse:" + code)
    return parts.join(" + ")
  }

  function completeRecording(chord) {
    if (!chord || recordingAction === "") return false
    syncing = true
    if (recordingAction === "minimize") minimizeField.text = chord
    else sidebarField.text = chord
    syncing = false
    var recorded = recordingAction
    recordingAction = ""
    recordingHint = "Recorded " + chord + "; checking it now."
    dirty = true
    removeConfirmation = false
    localFeedback = ""
    localError = false
    scheduleCheck(true)
    return recorded !== ""
  }

  function captureKeyboard(key, modifiers, text) {
    if (recordingAction === "") return false
    if (key === Qt.Key_Escape) return cancelRecording()
    var chord = keyboardChord(key, modifiers, text)
    if (!chord) {
      recordingHint = "Keep holding any modifiers, then press a supported key or mouse button."
      return false
    }
    return completeRecording(chord)
  }

  function captureMouse(button, modifiers) {
    if (recordingAction === "") return false
    var chord = mouseChord(button, modifiers)
    if (!chord) {
      recordingHint = "That mouse button could not be identified; enter its mouse:NUMBER value manually."
      return false
    }
    var code = mouseCode(button)
    if (code <= 274 && modifierPrefix(modifiers).length === 0) {
      recordingHint = "Left, right, and middle click need a modifier so normal clicking keeps working."
      return false
    }
    return completeRecording(chord)
  }

  function clearDraft(action) {
    if (sharedBusy || recordingAction !== "") return false
    syncing = true
    if (action === "minimize") minimizeField.text = ""
    else sidebarField.text = ""
    syncing = false
    dirty = true
    removeConfirmation = false
    localFeedback = ""
    localError = false
    scheduleCheck(true)
    return true
  }

  function focusFirstField() {
    focusRequested = true
    minimizeField.forceActiveFocus()
    focusRequestTimer.restart()
  }

  function resetPageState() {
    removeConfirmation = false
    pendingKind = ""
    focusRequested = false
    recordingAction = ""
    recordingHint = ""
    checkDebounce.stop()
  }

  onStoreChanged: if (!dirty) syncFromStore(false)

  Connections {
    target: root.store
    ignoreUnknownSignals: true
    function onShortcutOperationFinished(code, ok) {
      if (code === "check") {
        if (!ok) {
          root.localFeedback = String(root.store && root.store.shortcutCheckError
            || "Shortcut availability could not be checked.")
          root.localError = true
        }
        return
      }
      var operation = root.pendingKind
      if (operation !== "") {
        root.localFeedback = ok
          ? (operation === "remove" ? "Plugin-owned shortcuts removed." : "Shortcuts saved.")
          : String(root.store && root.store.shortcutLastError || code)
        root.localError = !ok
        if (ok) {
          root.dirty = false
          root.removeConfirmation = false
          root.syncFromStore(true)
        } else {
          root.scheduleCheck(true)
        }
        root.pendingKind = ""
      } else if (!root.dirty && ok) {
        root.syncFromStore(false)
      } else if (code === "status") {
        root.scheduleCheck(true)
      }
    }
  }

  Timer {
    id: focusRequestTimer
    interval: 100
    repeat: false
    onTriggered: root.focusRequested = false
  }

  Timer {
    id: checkDebounce
    interval: 300
    repeat: false
    onTriggered: root.requestCheck()
  }

  ScrollView {
    id: scrollArea
    anchors.fill: parent
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: root.scrollable ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

    Column {
      id: settingsColumn
      width: scrollArea.availableWidth
      spacing: Style.spacing.lg

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.stateText
        color: root.localError || root.stateKind === "error" ? Color.urgent : root.foreground
        opacity: root.localError || root.stateKind === "error" ? 1.0 : 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        Accessible.name: "Shortcut status: " + root.stateText
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          width: Math.max(0, parent.width - minimizeRecord.width - minimizeClear.width
            - parent.spacing * 2)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Minimize focused window"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }

        Button {
          id: minimizeRecord
          text: root.recordingAction === "minimize" ? "Listening…" : "Record"
          focusable: true
          bordered: true
          active: root.recordingAction === "minimize"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          enabled: !root.sharedBusy && root.recordingAction === ""
          Accessible.name: "Record minimize window shortcut"
          Accessible.description: "Listen for one keyboard combination or mouse button"
          onClicked: root.startRecording("minimize")
        }

        Button {
          id: minimizeClear
          text: "Clear"
          focusable: true
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          enabled: !root.sharedBusy && root.recordingAction === "" && root.minimizeDraft !== ""
          Accessible.name: "Clear minimize window shortcut draft"
          onClicked: root.clearDraft("minimize")
        }
      }

      TextField {
        id: minimizeField
        width: parent.width
        placeholderText: "Record a shortcut or enter SUPER + M"
        foreground: root.foreground
        enabled: !root.sharedBusy && root.recordingAction === ""
        Accessible.role: Accessible.EditableText
        Accessible.name: "Minimize window shortcut"
        Accessible.description: root.fieldStatus("minimize")
        onTextEdited: root.draftChanged()
        Keys.onEscapePressed: root.backRequested()
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_F1) { root.helpRequested(); event.accepted = true }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.fieldStatus("minimize")
        color: root.fieldProblem("minimize") ? Color.urgent : root.foreground
        opacity: root.fieldProblem("minimize") ? 1.0 : 0.68
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          width: Math.max(0, parent.width - sidebarRecord.width - sidebarClear.width
            - parent.spacing * 2)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Open minimize sidebar"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }

        Button {
          id: sidebarRecord
          text: root.recordingAction === "sidebar" ? "Listening…" : "Record"
          focusable: true
          bordered: true
          active: root.recordingAction === "sidebar"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          enabled: !root.sharedBusy && root.recordingAction === ""
          Accessible.name: "Record open sidebar shortcut"
          Accessible.description: "Listen for one keyboard combination or mouse button"
          onClicked: root.startRecording("sidebar")
        }

        Button {
          id: sidebarClear
          text: "Clear"
          focusable: true
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          enabled: !root.sharedBusy && root.recordingAction === "" && root.sidebarDraft !== ""
          Accessible.name: "Clear open sidebar shortcut draft"
          onClicked: root.clearDraft("sidebar")
        }
      }

      TextField {
        id: sidebarField
        width: parent.width
        placeholderText: "Record a shortcut or enter SUPER + ALT + M"
        foreground: root.foreground
        enabled: !root.sharedBusy && root.recordingAction === ""
        Accessible.role: Accessible.EditableText
        Accessible.name: "Open sidebar shortcut"
        Accessible.description: root.fieldStatus("sidebar")
        onTextEdited: root.draftChanged()
        Keys.onEscapePressed: root.backRequested()
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_F1) { root.helpRequested(); event.accepted = true }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.fieldStatus("sidebar")
        color: root.fieldProblem("sidebar") ? Color.urgent : root.foreground
        opacity: root.fieldProblem("sidebar") ? 1.0 : 0.68
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Record captures ordinary keys, Super/Ctrl/Alt/Shift combinations, and up to 27 mouse buttons. You can still type an advanced Hyprland value such as mouse:276. Nothing changes until Save, and Save checks the live bindings again."
        color: root.foreground
        opacity: 0.68
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Button {
          width: (parent.width - parent.spacing) / 2
          text: "Reset suggestions"
          focusable: true
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          enabled: !root.sharedBusy && root.recordingAction === ""
          Accessible.name: "Reset shortcut suggestions"
          Accessible.description: "Fill suggested values and check them without changing configuration"
          onClicked: root.resetSuggestions()
        }

        Button {
          width: (parent.width - parent.spacing) / 2
          text: root.checking ? "Checking…" : "Check again"
          focusable: true
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          enabled: !root.sharedBusy && root.recordingAction === ""
          Accessible.name: "Check live shortcut availability"
          Accessible.description: "Read active Hyprland bindings without changing configuration"
          onClicked: root.scheduleCheck(true)
        }
      }

      Button {
        width: parent.width
        text: root.sharedBusy && !root.checking ? "Working…"
          : root.canSave ? "Save shortcuts" : "Resolve shortcut issues to save"
        focusable: true
        bordered: true
        active: root.canSave
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.canSave
        Accessible.role: Accessible.Button
        Accessible.name: "Save both shortcuts"
        Accessible.description: root.canSave
          ? "Recheck and save both available shortcuts"
          : "Disabled until both shortcuts pass the live conflict check"
        onClicked: root.saveDrafts()
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Button {
          width: root.removeConfirmation
            ? (parent.width - parent.spacing) * 0.68 : parent.width
          text: root.removeConfirmation ? "Confirm remove owned shortcuts" : "Remove owned shortcuts…"
          focusable: true
          bordered: true
          foreground: root.removeConfirmation ? Color.urgent : root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          enabled: !root.sharedBusy && root.recordingAction === "" && root.sharedConfigured
          Accessible.role: Accessible.Button
          Accessible.name: root.removeConfirmation
            ? "Confirm remove plugin-owned shortcuts" : "Remove plugin-owned shortcuts"
          Accessible.description: root.removeConfirmation
            ? "Second confirmation; remove only the block managed by Omarchy Minimize"
            : "Ask for confirmation before removing only the plugin-owned shortcut block"
          onClicked: root.requestRemove()
        }

        Button {
          visible: root.removeConfirmation
          width: (parent.width - parent.spacing) * 0.32
          text: "Cancel"
          focusable: true
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          Accessible.role: Accessible.Button
          Accessible.name: "Cancel shortcut removal"
          Accessible.description: "Keep the plugin-owned shortcut block"
          onClicked: root.cancelRemove()
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.dirty ? "Unsaved changes stay local to this panel until Save is chosen." : ""
        visible: text !== ""
        color: root.foreground
        opacity: 0.62
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        bottomPadding: Style.spacing.lg
      }
    }
  }

  Item {
    id: captureTarget
    anchors.fill: parent
    z: 100
    visible: root.recordingAction !== ""
    focus: visible
    Accessible.role: Accessible.Pane
    Accessible.name: root.recordingAction === "minimize"
      ? "Recording minimize window shortcut" : "Recording open sidebar shortcut"
    Accessible.description: root.recordingHint

    Keys.onPressed: function(event) {
      root.captureKeyboard(event.key, event.modifiers, event.text)
      event.accepted = true
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Color.popups.background
      border.width: Style.spacing.hairline
      border.color: Color.accent
      opacity: 0.98
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onPressed: function(mouse) {
        root.captureMouse(mouse.button, mouse.modifiers)
        mouse.accepted = true
      }
    }

    Column {
      anchors.centerIn: parent
      width: Math.max(1, parent.width - Style.spacing.huge * 2)
      spacing: Style.spacing.lg

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.recordingAction === "minimize"
          ? "Record: Minimize focused window" : "Record: Open minimize sidebar"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.recordingHint
        color: root.foreground
        opacity: 0.76
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Escape cancels. Unmodified left, right, and middle clicks are ignored for safety."
        color: root.foreground
        opacity: 0.62
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Button {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Cancel recording"
        focusable: true
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        Accessible.name: "Cancel shortcut recording"
        onClicked: root.cancelRecording()
      }
    }
  }
}
