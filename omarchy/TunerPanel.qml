import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui

Ui.Panel {
  id: root
  moduleName: "io.github.fasi96.liquid-glass"
  manageIpc: false
  property Item anchorItem: null
  property var hostWidget: null
  property var state: ({})
  property var saved: ({})
  property var looks: ({looks: {}, active: null})
  property var controls: ({sections: [], integers: [], apple: {}})
  property var ranges: ({})
  property var defaults: ({})
  property bool lightSupported: false
  property bool edgeSupported: false
  property bool ready: false
  property bool closingBridge: false
  property bool powerBusy: false
  property bool comparing: false
  property string expandedSection: ""
  property string selectedLook: ""
  property string message: ""
  readonly property var lookNames: Object.keys(looks.looks || {}).sort()
  readonly property string tuner: Quickshell.env("HOME") + "/.local/share/omarchy-liquid-glass/tuner/tuner.py"

  function open(payloadJson) {
    if (root.opened) return
    root.expandedSection = ""
    root.controller.show()
    root.ready = false
    root.message = "Loading settings…"
    if (!bridge.running) bridge.running = true
  }
  function close() {
    deleteConfirm.close()
    overwriteConfirm.close()
    previewTimer.stop()
    root.comparing = false
    if (root.ready && bridge.running) {
      send("apply")
      send("close")
      root.closingBridge = true
    }
    root.ready = false
    root.controller.hide()
  }
  Component.onDestruction: { previewTimer.stop(); bridge.running = false }
  function send(action, extra) {
    if (!bridge.running) return
    bridge.write(JSON.stringify(Object.assign({action: action, state: root.state, compare: root.comparing}, extra || {})) + "\n")
  }
  function edit(key, value) {
    var next = Object.assign({}, root.state)
    next[key] = value
    root.state = next
    previewTimer.restart()
  }
  function setPower() {
    previewTimer.stop()
    root.comparing = false
    root.powerBusy = true
    send("power", {enabled: !root.state.glass_on})
  }
  function same(a, b) {
    return b && Object.keys(b).every(function(key) { return a[key] === b[key] })
  }
  function save() {
    previewTimer.stop()
    send("save", {look: root.same(root.state, root.looks.looks[root.selectedLook]) ? root.selectedLook : null})
    root.message = "Saving…"
  }
  function resetSection(section) {
    var next = Object.assign({}, root.state)
    var keys = (section.rows || []).map(function(row) { return row[0] })
      .concat((section.toggles || []).map(function(row) { return row[0] }))
      .concat((section.choices || []).map(function(row) { return row[0] }))
    if (section.extra) keys.push(section.extra[0])
    if (section.action) keys.push(section.action)
    keys.forEach(function(key) { next[key] = root.saved[key] })
    root.state = next
    previewTimer.restart()
  }
  function consume(line) {
    var reply
    try { reply = JSON.parse(line) } catch (error) { root.message = "Invalid settings response"; return }
    if (reply.action === "ready") {
      if (!root.opened) { send("close"); root.closingBridge = true; return }
      root.state = reply.state; root.saved = Object.assign({}, reply.state)
      root.looks = reply.looks; root.controls = reply.controls; root.ranges = reply.ranges; root.defaults = reply.defaults
      root.lightSupported = reply.light; root.edgeSupported = reply.edge
      root.selectedLook = reply.looks.active || ""
      root.ready = true; root.powerBusy = false; root.message = "Changes preview live. Right-click sliders to reset. Save keeps your adjustments."
    } else if (reply.action === "power") {
      root.state = Object.assign({}, root.state, {glass_on: reply.enabled})
      root.saved = Object.assign({}, root.saved, {glass_on: reply.enabled})
      root.powerBusy = false
      root.message = reply.errors || (reply.enabled ? "Liquid Glass on — saved" : "Liquid Glass off — saved")
    } else if (reply.action === "save") {
      root.saved = Object.assign({}, reply.state)
      root.looks = reply.looks
      root.message = reply.errors || "Settings saved"
    } else if (reply.action === "revert") {
      root.state = reply.state; root.saved = Object.assign({}, reply.state)
      root.message = "Restored saved settings"
    } else if (reply.action === "looks/save" || reply.action === "looks/delete") {
      root.looks = reply.looks
      if (!(root.selectedLook in root.looks.looks)) root.selectedLook = ""
      root.message = "Saved looks updated"
    } else if (reply.action === "error") {
      root.powerBusy = false
      root.message = reply.error
    }
  }

  Timer {
    id: previewTimer
    interval: 50
    onTriggered: if (root.opened && root.ready) root.send("apply")
  }
  Process {
    id: bridge
    command: ["python3", root.tuner, "--panel-bridge"]
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.consume(line) } }
    stderr: SplitParser { onRead: function(line) { root.message = String(line).slice(0, 300) } }
    onExited: function(code, status) {
      var expected = root.closingBridge
      root.closingBridge = false
      if (root.opened && expected) bridge.running = true
      else if (root.opened) { root.ready = false; root.message = "Settings helper stopped. Close and reopen to retry." }
    }
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.hostWidget || root
    open: root.opened
    focusTarget: content
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.cappedContentHeight(Style.space(640))

    Item {
      id: content
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
      Column {
        id: header
        width: parent.width
        spacing: Style.spacing.sm
        Text { text: "Liquid Glass"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.subtitle; font.bold: true }
        Ui.Toggle {
          width: parent.width
          label: "Liquid Glass"
          description: root.state.glass_on ? "On · turn off here (saved immediately)" : "Off · turn on here (saved immediately)"
          checked: root.state.glass_on === true
          enabled: root.ready && !root.powerBusy
          onClicked: root.setPower()
        }
      }
      Controls.ScrollView {
        id: scroll
        anchors.top: header.bottom
        anchors.topMargin: Style.spacing.md
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.spacing.md
        width: parent.width
        clip: true
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        Column {
          width: scroll.availableWidth
          spacing: Style.spacing.md
          enabled: root.ready
          Column {
            width: parent.width
            spacing: Style.spacing.sm
            Ui.Button {
              width: parent.width
              text: (root.expandedSection === "looks" ? "▾ " : "▸ ") + "Saved looks"
              foreground: Color.accent
              leftAlign: true
              focusable: true
              onClicked: root.expandedSection = root.expandedSection === "looks" ? "" : "looks"
            }
            Column {
              width: parent.width
              spacing: Style.spacing.sm
              visible: root.expandedSection === "looks"
              height: visible ? implicitHeight : 0
              Controls.ComboBox {
                width: parent.width
                model: ["Pick a look…"].concat(root.lookNames)
                currentIndex: root.lookNames.indexOf(root.selectedLook) + 1
                onActivated: function(index) {
                  if (index === 0) { root.selectedLook = ""; return }
                  root.selectedLook = root.lookNames[index - 1]
                  root.state = Object.assign({}, root.state, root.looks.looks[root.selectedLook])
                  previewTimer.restart()
                  root.message = "Look loaded. Press Save to keep it."
                }
              }
              Row {
                width: parent.width
                spacing: Style.spacing.sm
                Ui.Button { text: "Update"; focusable: true; enabled: root.selectedLook !== ""; onClicked: root.send("looks/save", {name: root.selectedLook}) }
                Ui.Button { text: "Delete"; focusable: true; enabled: root.selectedLook !== ""; onClicked: deleteConfirm.open() }
              }
              Controls.TextField { id: lookName; width: parent.width; placeholderText: "Name for a new look"; maximumLength: 40 }
              Ui.Button { text: "Save as new"; focusable: true; enabled: lookName.text.trim() !== ""; onClicked: { if (lookName.text.trim() in root.looks.looks) overwriteConfirm.open(); else root.send("looks/save", {name: lookName.text.trim()}) } }
            }
            Ui.PanelSeparator { width: parent.width }
          }
          Repeater {
            model: root.controls.sections || []
            Column {
              id: section
              required property var modelData
              required property int index
              width: parent.width
              spacing: Style.spacing.sm
              visible: (!modelData.light || root.lightSupported) && (!modelData.edge || root.edgeSupported)
              height: visible ? implicitHeight : 0
              readonly property string sectionKey: "section:" + index
              readonly property bool expanded: root.expandedSection === sectionKey
              Row {
                width: parent.width
                spacing: Style.spacing.sm
                Ui.Button {
                  width: parent.width - actionSwitch.width - parent.spacing
                  text: (section.expanded ? "▾ " : "▸ ") + (section.modelData.title || section.modelData.group)
                  foreground: Color.accent
                  leftAlign: true
                  focusable: true
                  onClicked: root.expandedSection = section.expanded ? "" : section.sectionKey
                }
                Ui.ToggleSwitch {
                  id: actionSwitch
                  visible: !!section.modelData.action
                  width: visible ? implicitWidth : 0
                  checked: root.state[section.modelData.action] === true
                  onToggled: root.edit(section.modelData.action, !checked)
                }
              }
              Column {
                width: parent.width
                spacing: Style.spacing.sm
                visible: section.expanded
                height: visible ? implicitHeight : 0
                Repeater {
                  model: section.modelData.rows || []
                  Column {
                    id: settingRow
                    required property var modelData
                    readonly property string key: modelData[0]
                    readonly property var range: root.ranges[key] || [0, 1]
                    readonly property bool integer: root.controls.integers.indexOf(key) >= 0
                    width: parent.width
                    Text { width: parent.width; text: settingRow.modelData[1] + "   " + (settingRow.integer ? Math.round(root.state[settingRow.key] || 0) : Number(root.state[settingRow.key] || 0).toFixed(2)); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
                    Text { width: parent.width; text: settingRow.modelData[2] || ""; visible: text !== ""; wrapMode: Text.WordWrap; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                    Ui.PanelSlider {
                      width: parent.width
                      bar: root.bar
                      minimum: settingRow.range[0]; maximum: settingRow.range[1]
                      integer: settingRow.integer
                      step: integer ? 1 : (maximum - minimum) / 200
                      value: root.state[settingRow.key] || 0
                      onMoved: function(value) { root.edit(settingRow.key, value) }
                      onReleased: function(value) { root.edit(settingRow.key, value) }
                      onRightClicked: root.edit(settingRow.key, root.defaults[settingRow.key])
                    }
                  }
                }
                Repeater {
                  model: section.modelData.toggles || []
                  Ui.Toggle {
                    required property var modelData
                    width: parent.width
                    label: modelData[1]
                    checked: root.state[modelData[0]] === true
                    onClicked: root.edit(modelData[0], !checked)
                  }
                }
                Repeater {
                  model: section.modelData.choices || []
                  Column {
                    required property var modelData
                    width: parent.width
                    Text { text: parent.modelData[1]; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
                    Controls.ComboBox {
                      width: parent.width
                      model: parent.modelData[2]
                      currentIndex: model.indexOf(root.state[parent.modelData[0]])
                      onActivated: function(index) { root.edit(parent.modelData[0], model[index]) }
                    }
                  }
                }
                Column {
                  width: parent.width
                  visible: !!section.modelData.extra
                  height: visible ? implicitHeight : 0
                  Text { text: section.modelData.extra ? section.modelData.extra[1] : ""; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
                  Controls.TextField {
                    width: parent.width
                    text: section.modelData.extra ? "#" + root.state[section.modelData.extra[0]] : ""
                    placeholderText: "#RRGGBB"
                    maximumLength: 7
                    onEditingFinished: { if (/^#?[0-9a-fA-F]{6}$/.test(text)) root.edit(section.modelData.extra[0], text.replace(/^#/, "")); else root.message = "Use a six-digit hex colour" }
                  }
                }
                Ui.Button { text: "Revert section"; focusable: true; onClicked: root.resetSection(section.modelData) }
              }
              Ui.PanelSeparator { width: parent.width }
            }
          }
          Ui.Button { text: "Load Apple-ish starting point"; focusable: true; onClicked: { root.state = Object.assign({}, root.state, root.controls.apple); previewTimer.restart() } }
          Row {
            spacing: Style.spacing.sm
            Ui.Button { text: "Test terminal"; focusable: true; onClicked: root.send("test-window") }
            Ui.Button { text: "Next wallpaper"; focusable: true; onClicked: root.send("wallpaper") }
          }
        }
      }
      Column {
        id: footer
        width: parent.width
        anchors.bottom: parent.bottom
        spacing: Style.spacing.sm
        enabled: root.ready
        Ui.Toggle {
          width: parent.width
          label: "Compare with glass off"
          checked: root.comparing
          onClicked: { root.comparing = !root.comparing; previewTimer.restart() }
        }
        Row {
          spacing: Style.spacing.sm
          Ui.Button { text: "Revert to saved"; focusable: true; onClicked: root.send("revert") }
          Ui.Button { text: "Save"; focusable: true; selected: true; onClicked: root.save() }
          Ui.Button { text: "Close"; focusable: true; onClicked: root.close() }
        }
        Text { width: parent.width; text: root.message; wrapMode: Text.WordWrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
      }
      Controls.Dialog {
        id: deleteConfirm
        title: "Delete saved look?"
        modal: true
        standardButtons: Controls.Dialog.Yes | Controls.Dialog.No
        onAccepted: root.send("looks/delete", {name: root.selectedLook})
      }
      Controls.Dialog {
        id: overwriteConfirm
        title: "Overwrite saved look?"
        modal: true
        standardButtons: Controls.Dialog.Yes | Controls.Dialog.No
        onAccepted: root.send("looks/save", {name: lookName.text.trim()})
      }
    }
  }
}
