import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button + popup over the `led` CLI next to this file. `led` owns all state
// (~/.config/led.json) and prints it after every command; this file only renders it.
Panel {
  id: root
  moduleName: "com.pgeneva.omarchy_led_controller"
  ipcTarget: "com.pgeneva.omarchy_led_controller"

  readonly property string ledCmd: String(Qt.resolvedUrl("led")).replace(/^file:\/\//, "")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var st: ({ color: "8000FF", mode: "static", brightness: 100, power: true, held: false,
                      disabled: [], keep_on: [], auto_off: false, off: "22:00", on: "09:00", devices: [] })
  property string error: ""
  property var queue: []
  property int liveBrightness: st.brightness
  property real liveGamma: st.gamma || 2.8

  property bool advanced: false
  readonly property string timeRe: "^([01]\\d|2[0-3]):[0-5]\\d$"
  // "theme" follows the Omarchy theme (led reads keyboard.rgb / accent); the rest are fixed.
  readonly property var swatches: ["theme", "FFFFFF", "FF0000", "FF6000", "FFC000",
                                   "00FF00", "00FFFF", "0000FF", "8000FF", "FF00A0"]

  function hex(c) {
    function h(v) { return ("0" + Math.round(v * 255).toString(16)).slice(-2) }
    return (h(c.r) + h(c.g) + h(c.b)).toUpperCase()
  }

  // Commands run one at a time, in order, so fast clicks are never dropped.
  function run(args) { queue = queue.concat([args]); next() }
  function next() {
    if (proc.running || queue.length === 0) return
    proc.command = [ledCmd].concat(queue[0])
    queue = queue.slice(1)
    proc.running = true
  }

  function setLook(color, mode, brightness) { run(["set", color, "-m", mode, "-b", String(brightness)]) }
  function setSchedule(patch) { run(["schedule", JSON.stringify(patch)]) }
  function has(list, name) { return list.indexOf(name) !== -1 }
  // Picking a colour while in Daylight means "I want this colour": drop to Static.
  function colorMode() { return st.mode === "daylight" ? "static" : st.mode }

  Component.onCompleted: run(["state"])  // so right-click works before the panel is ever opened
  onOpenedChanged: if (opened) run(["state"])

  Process {
    id: proc
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onExited: function(code) {
      try { root.st = JSON.parse(String(out.text)); root.error = "" }
      catch (e) { root.error = (String(err.text) || "led failed; is openrgb.service running?").trim().split("\n").pop() }
      root.next()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌵"
    dimmed: !root.st.power || root.st.held
    tooltipText: root.opened ? "" : "LEDs"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.run([root.st.power && !root.st.held ? "off" : "on"])
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)  // grows with Advanced, up to screen height

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "LEDs"
          meta: root.error !== "" ? root.error
              : !root.st.power ? "Off"
              : root.st.held ? "Night off until " + root.st.on
              : root.st.devices.length + " devices · " + root.st.mode
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "󰌵"
              color: root.st.power && !root.st.held ? "#" + (root.st.shown || root.st.color) : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSectionHeader { text: "Colour"; foreground: root.foreground; fontFamily: root.fontFamily }

        Flow {
          width: parent.width
          spacing: Style.space(8)
          Repeater {
            model: root.swatches
            Rectangle {
              required property string modelData
              width: Style.space(26); height: width; radius: width / 2
              color: modelData === "theme" ? Color.accent : "#" + modelData
              border.width: root.st.color === modelData ? 3 : 1
              border.color: root.st.color === modelData ? root.foreground : root.dim
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setLook(parent.modelData, root.colorMode(), root.st.brightness)
              }
              Text {
                visible: parent.modelData === "theme"
                anchors.centerIn: parent
                text: "󰏘"  // palette: "follow theme"
                color: Color.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        PanelSectionHeader { text: "Effect"; foreground: root.foreground; fontFamily: root.fontFamily }

        ButtonGroup {
          options: [{ value: "static", label: "Static" }, { value: "breathing", label: "Breathe" },
                    { value: "rainbow", label: "Rainbow" }, { value: "daylight", label: "Daylight",
                      tooltip: "Blue by day, orange at sunset, red at night (times in ~/.config/led.json)" }]
          value: root.st.power ? root.st.mode : ""
          focusable: false
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.setLook(root.st.color, v, root.st.brightness) }
        }

        PanelSectionHeader { text: "Brightness " + root.liveBrightness + "%"; foreground: root.foreground; fontFamily: root.fontFamily }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: 5; maximum: 100; step: 5; integer: true
          value: root.st.brightness
          onMoved: function(v) { root.liveBrightness = Math.round(v) }
          onReleased: function(v) { root.setLook(root.st.color, root.st.mode, Math.round(v)) }
        }

        Repeater {
          model: root.st.devices
          RowLayout {
            required property var modelData
            readonly property bool isOn: !root.has(root.st.disabled, modelData.name)
            width: column.width
            Text {
              Layout.fillWidth: true
              text: modelData.name
              elide: Text.ElideRight
              color: isOn ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            ToggleSwitch {
              checked: isOn
              onToggled: root.run(["device", modelData.name, isOn ? "off" : "on"])
            }
          }
        }

        Button {
          text: (root.advanced ? "▾" : "▸") + "  Advanced"
          foreground: root.dim
          fontFamily: root.fontFamily
          onClicked: root.advanced = !root.advanced
        }

        Column {
          visible: root.advanced
          width: parent.width
          spacing: Style.space(10)

          RowLayout {
            width: parent.width
            Button {
              Layout.fillWidth: true
              text: root.st.power && !root.st.held ? "Turn all off" : "Turn all on"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.run([root.st.power && !root.st.held ? "off" : "on"])
            }
            Button {
              Layout.fillWidth: true
              text: "Restart OpenRGB"
              tooltipText: "Re-detect devices and re-apply"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: { root.error = "Restarting OpenRGB…"; root.run(["restart"]) }
            }
          }

          Text { text: "Colour depth " + Number(root.liveGamma).toFixed(1) + "  (higher = deeper, less washed out)"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: 1.0; maximum: 4.0; step: 0.1
            value: root.st.gamma || 2.8
            onMoved: function(v) { root.liveGamma = v }
            onReleased: function(v) { root.run(["set", "-g", Number(v).toFixed(1)]) }
          }

          Text { text: "Custom colour (hex)"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          TextField {
            width: parent.width
            placeholderText: "Hex, e.g. 8000FF"
            text: root.st.color === "theme" ? "" : root.st.color
            foreground: root.foreground
            onAccepted: {
              var m = String(text).match(/^#?([0-9a-fA-F]{6})$/)
              if (m) root.setLook(m[1].toUpperCase(), root.colorMode(), root.st.brightness)
            }
          }

          RowLayout {
            width: parent.width
            Text {
              Layout.fillWidth: true
              text: "Off while screens are off"
              color: root.st.idle_off !== false ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            ToggleSwitch {
              checked: root.st.idle_off !== false
              onToggled: root.setSchedule({ idle_off: !checked })
            }
          }

          RowLayout {
            width: parent.width
            Text {
              Layout.fillWidth: true
              text: "Auto off"
              color: root.st.auto_off ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            ToggleSwitch {
              checked: root.st.auto_off
              onToggled: root.setSchedule({ auto_off: !checked })
            }
          }
          RowLayout {
            width: parent.width
            spacing: Style.space(8)
            TextField {
              Layout.preferredWidth: Style.space(72)
              text: root.st.off
              foreground: root.foreground
              onEditingFinished: if (new RegExp(root.timeRe).test(text) && text !== root.st.off) root.setSchedule({ off: text })
            }
            Text { text: "to"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            TextField {
              Layout.preferredWidth: Style.space(72)
              text: root.st.on
              foreground: root.foreground
              onEditingFinished: if (new RegExp(root.timeRe).test(text) && text !== root.st.on) root.setSchedule({ on: text })
            }
            Item { Layout.fillWidth: true }
          }

          Text { text: "Auto off applies to"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          Repeater {
            model: root.st.devices
            RowLayout {
              required property var modelData
              readonly property bool isNight: !root.has(root.st.keep_on, modelData.name)
              width: column.width
              Text {
                Layout.fillWidth: true
                text: modelData.name
                elide: Text.ElideRight
                color: isNight ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              ToggleSwitch {
                checked: isNight
                onToggled: root.run(["night", modelData.name, isNight ? "off" : "on"])
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Daylight fade times: led schedule '{\"daylight\": [[\"HH:MM\", \"RRGGBB\"], ...]}'"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
