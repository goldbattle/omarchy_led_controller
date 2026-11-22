// omarchy_led_controller: the bar button and its popup panel.
//
// How it fits together
// --------------------
// This file is only the user interface. All the real work is done by the `led`
// command-line tool that sits next to this file in the plugin folder:
//
//   * `led` owns every setting (saved in ~/.config/led.json) and talks to the
//     OpenRGB server to change the hardware.
//   * After every command, `led` prints the complete current state as JSON.
//   * This panel runs `led ...` when you click something, reads the JSON it
//     prints, and redraws itself from that. It never keeps settings of its own.
//
// Because of that, the panel, the terminal, the right-click shortcut and the
// background timers can never disagree: they all go through the same tool.
//
// Layout of the popup, top to bottom
// ----------------------------------
//   1. Header       big bulb icon plus a one-line status ("5 devices · static")
//   2. Colour       a row of fixed colours, then a row with the current theme's
//                   colours (the first one, with the Omarchy logo, is "theme")
//   3. Effect       Static / Breathe / Rainbow / Flux
//   4. Brightness   a slider
//   5. Devices      one on/off switch per detected device
//   6. Advanced     a collapsible section: colour depth, custom hex colour,
//                   "off while screens are off", the auto-off schedule,
//                   the Flux location, and the "turn all off" / "restart" buttons
//
// Clicking the bar button opens the popup. Right-clicking it turns all the
// lights off (or back on) without opening anything.

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "com.pgeneva.omarchy_led_controller"
  ipcTarget: "com.pgeneva.omarchy_led_controller"
  manageIpc: false  // we declare our own handler below, with one extra call

  // Lets scripts drive the panel, e.g.
  //   omarchy-shell com.pgeneva.omarchy_led_controller open
  //   omarchy-shell com.pgeneva.omarchy_led_controller setAdvanced true
  // The first five match every other Omarchy panel. setAdvanced expands or collapses the
  // Advanced section; the update-screenshot skill uses it to capture both views.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function setAdvanced(on: bool): void { root.advanced = on }
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  // Full path to the `led` tool that ships alongside this file.
  readonly property string ledCmd: String(Qt.resolvedUrl("led")).replace(/^file:\/\//, "")

  // The latest state reported by `led`. These defaults are only shown for the
  // split second before the first reply arrives. The fields mean:
  //   color       "RRGGBB" hex, or "theme" to follow the Omarchy theme accent
  //   mode        "static", "breathing", "rainbow" or "flux"
  //   brightness  5 to 100 (percent)
  //   power       false after "Turn all off"
  //   held        true while the auto-off schedule is keeping the lights dark
  //   disabled    names of devices whose own switch is off
  //   auto_off, off, on   the night schedule: on/off flag and its "HH:MM" times
  //   devices     the devices OpenRGB found, each with at least a `name`
  // `led` also sends a few extras that are read below when present:
  //   shown (the colour actually on the LEDs right now), flux (the current Flux
  //   step, e.g. "3400K"), theme (the Omarchy theme's name, e.g. "tokyo-night"),
  //   theme_color (the RRGGBB that "theme" stands for right now), palette (the
  //   theme's own colours by slot name, e.g. { magenta: "907AA9" }),
  //   color_name (a rough name for the colour, e.g. "purple"), gamma, idle_off
  //   and location.
  property var st: ({ color: "8000FF", mode: "static", brightness: 100, power: true, held: false,
                      disabled: [], auto_off: false, off: "22:00", on: "09:00", devices: [] })

  // True when the lights are allowed to be on at all: not switched off by
  // hand and not being held dark by the night schedule.
  readonly property bool lit: st.power && !st.held

  // Last error message from `led`, shown in the header instead of the status.
  property string error: ""

  // Commands waiting to run (see run() below).
  property var queue: []

  // Slider values while you are still dragging. The label follows your finger
  // straight away; the command is only sent when you let go.
  property int liveBrightness: st.brightness
  property real liveGamma: st.gamma || 2.8

  // Whether the Advanced section is expanded.
  property bool advanced: false

  // A valid 24-hour time such as "07:30" or "22:00".
  readonly property string timeRe: "^([01]\\d|2[0-3]):[0-5]\\d$"

  // The fixed colour presets (the theme's colours get a row of their own).
  readonly property var swatches: ["FFFFFF", "FF0000", "FF6000", "FFC000", "00FF00",
                                   "00FFFF", "0000FF", "8000FF", "FF00A0"]

  // One round colour button. `value` is what `led set` gets ("FF0000", "theme",
  // "theme:magenta"), `hex` is the colour to draw. The chosen one gets a thick
  // ring; none is chosen in Flux, because the sun picks the colour then. `logo`
  // puts the Omarchy logo (the bar's menu glyph) on it, for "follow the theme".
  component Swatch: Rectangle {
    property string value
    property string hex
    property bool logo: false
    readonly property bool picked: root.st.mode !== "flux" && root.st.color === value
    width: Style.space(26); height: width; radius: width / 2
    color: "#" + hex
    border.width: picked ? 3 : 1
    border.color: picked ? root.foreground : root.dim
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.setColor(parent.value)
    }
    Text {
      visible: parent.logo
      anchors.centerIn: parent
      text: "\ue900"
      color: Color.background
      font.family: "omarchy"
      font.pixelSize: Style.font.caption
    }
  }

  // Shared look for the panel's text, so every label matches the bar.
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)  // for labels and things that are off
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---------------------------------------------------------------------------
  // Talking to `led`
  // ---------------------------------------------------------------------------

  // Queue a `led` command. Commands run one at a time, in the order they were
  // clicked. Each takes a moment (it changes every device, then checks they all
  // took it), so clicking quickly through colours would leave the lights
  // trailing behind. Instead a new command replaces any still-waiting command it
  // makes pointless, and the lights jump straight to the last thing clicked.
  function run(args) {
    queue = queue.filter(function(waiting) { return !supersedes(args, waiting) }).concat([args])
    next()
  }

  // Whether running `newer` makes the waiting command `older` pointless: a
  // colour replaces a colour, an effect an effect, brightness brightness and
  // colour depth colour depth (same shape of `led set`); a device switch
  // replaces the same device's switch; all on/off replaces all on/off.
  // Schedule changes are never dropped: each one may change a different field.
  function supersedes(newer, older) {
    function shape(args) {  // ["set", "-m", "rainbow"] -> "set -m _"
      return args.map(function(a, i) { return i === 0 || a[0] === "-" ? a : "_" }).join(" ")
    }
    var onOff = ["on", "off"]
    if (onOff.indexOf(newer[0]) !== -1) return onOff.indexOf(older[0]) !== -1
    if (newer[0] === "set") return shape(newer) === shape(older)
    if (newer[0] === "device") return older[0] === "device" && newer[1] === older[1]
    return false
  }

  // Start the next queued command, unless one is already running.
  function next() {
    if (proc.running || queue.length === 0) return
    proc.command = [ledCmd].concat(queue[0])
    queue = queue.slice(1)
    proc.running = true
  }

  // Change one thing at a time; `led` keeps everything else as it is. (Sending
  // only what changed matters: values read from `st` may be a click behind.)
  // Picking a colour while in Flux switches to Static; `led` handles that.
  function setColor(color) { run(["set", color]) }
  function setMode(mode) { run(["set", "-m", mode]) }
  function setBrightness(percent) { run(["set", "-b", String(percent)]) }

  // What the lights are showing, for the header: "static · tokyo-night",
  // "breathing · purple", "flux · 3400K", or just "rainbow" (it has no colour).
  function lookText() {
    if (st.mode === "flux") return "flux" + (st.flux ? " · " + st.flux : "")
    if (st.mode === "rainbow") return "rainbow"
    if (st.color === "theme") return st.mode + " · " + (st.theme || "theme")
    if (st.color.indexOf("theme:") === 0)  // a palette slot, e.g. "rose-pine magenta"
      return st.mode + " · " + (st.theme || "theme") + " " + st.color.slice(6)
    return st.mode + (st.color_name ? " · " + st.color_name : "")
  }

  // Change one or more schedule settings, e.g. setSchedule({ off: "23:00" }).
  function setSchedule(patch) { run(["schedule", JSON.stringify(patch)]) }

  // Fetch the state once at startup, so right-click works before the panel has
  // ever been opened, and again every time the panel opens.
  Component.onCompleted: run(["state"])
  onOpenedChanged: if (opened) run(["state"])

  // Runs a single `led` command. When it finishes, its output becomes the new
  // state. If the output isn't valid JSON, the last line of the error output is
  // shown in the header instead.
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

  // ---------------------------------------------------------------------------
  // The bar button
  // ---------------------------------------------------------------------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌵"  // light bulb icon
    dimmed: !root.lit
    tooltipText: root.opened ? "" : "LEDs"
    // Left-click opens the panel, right-click toggles everything off or on.
    onPressed: function(b) {
      if (b === Qt.RightButton) root.run([root.lit ? "off" : "on"])
      else root.toggle()
    }
  }

  // ---------------------------------------------------------------------------
  // The popup panel
  // ---------------------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // Grows when Advanced is expanded, but never beyond the screen height.
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    // Handles Escape (close) and Tab (move to the next bar panel).
    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        // --- 1. Header: bulb in the current colour, plus a status line -------
        PanelHero {
          width: parent.width
          title: "LEDs"
          meta: root.error !== "" ? root.error
              : !root.st.power ? "Off"
              : root.st.held ? "Night off until " + root.st.on
              : root.st.devices.length + " devices · " + root.lookText()
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "󰌵"
              // `shown` is the colour really on the LEDs (it differs from
              // `color` for "theme" and Flux); grey when everything is off.
              color: root.lit ? "#" + (root.st.shown || root.st.color) : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        // --- 2. Colour: fixed presets, then the current theme's colours --------
        PanelSectionHeader { text: "Colour"; foreground: root.foreground; fontFamily: root.fontFamily }

        Flow {
          width: parent.width
          spacing: Style.space(8)
          Repeater {
            model: root.swatches
            Swatch { required property string modelData; value: modelData; hex: modelData }
          }
        }

        // First "theme" itself (what `led` picks for this theme, marked with the
        // Omarchy logo), then each palette slot whose colour isn't already shown.
        // A slot follows itself through theme changes: "magenta" is rose-pine's
        // purple now and tokyo-night's magenta after a switch.
        PanelSectionHeader {
          text: "Theme colours" + (root.st.theme ? " · " + root.st.theme : "")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Flow {
          width: parent.width
          spacing: Style.space(8)
          Repeater {
            model: {
              var palette = root.st.palette || {}
              var seen = {}, values = ["theme"]
              seen[root.st.theme_color] = true
              for (var slot in palette)
                if (!seen[palette[slot]]) { seen[palette[slot]] = true; values.push("theme:" + slot) }
              return values
            }
            Swatch {
              required property string modelData
              value: modelData
              hex: modelData === "theme" ? (root.st.theme_color || "FFFFFF")
                                         : (root.st.palette || {})[modelData.slice(6)] || "FFFFFF"
              logo: modelData === "theme"
            }
          }
        }

        // --- 3. Effect ----------------------------------------------------------
        PanelSectionHeader { text: "Effect"; foreground: root.foreground; fontFamily: root.fontFamily }

        // The Flux button also shows the current step, e.g. "Flux · 3400K".
        // Nothing is highlighted while the lights are switched off.
        ButtonGroup {
          options: [{ value: "static", label: "Static" },
                    { value: "breathing", label: "Breathe" },
                    { value: "rainbow", label: "Rainbow" },
                    { value: "flux", label: "Flux" + (root.st.flux ? " · " + root.st.flux : ""),
                      tooltip: "Follows the sun: white by day, warm at sunset, red after dusk" }]
          value: root.st.power ? root.st.mode : ""
          focusable: false
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.setMode(v) }
        }

        // --- 4. Brightness ------------------------------------------------------
        PanelSectionHeader { text: "Brightness " + root.liveBrightness + "%"; foreground: root.foreground; fontFamily: root.fontFamily }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: 5; maximum: 100; step: 5; integer: true
          value: root.st.brightness
          onMoved: function(v) { root.liveBrightness = Math.round(v) }
          onReleased: function(v) { root.setBrightness(Math.round(v)) }
        }

        // --- 5. One switch per device ----------------------------------------
        Repeater {
          model: root.st.devices
          RowLayout {
            required property var modelData
            // Every switch shows "off" while all the lights are dark (turned off
            // by hand or by the night schedule), so flipping one always means
            // "turn this device on".
            readonly property bool isOn: root.lit && root.st.disabled.indexOf(modelData.name) === -1
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

        // --- 6. Advanced (collapsed by default) --------------------------------
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

          // Colour depth (gamma). Screen colours look washed out on LEDs, so
          // `led` darkens them by this curve. 1.0 turns the correction off.
          Text { text: "Colour depth " + Number(root.liveGamma).toFixed(1) + "  (higher = deeper, less washed out)"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: 1.0; maximum: 4.0; step: 0.1
            value: root.st.gamma || 2.8
            onMoved: function(v) { root.liveGamma = v }
            onReleased: function(v) { root.run(["set", "-g", Number(v).toFixed(1)]) }
          }

          // Any colour as six hex digits. A leading "#" is fine; anything else
          // that isn't a valid colour is ignored.
          Text { text: "Custom colour (hex)"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          TextField {
            width: parent.width
            placeholderText: "Hex, e.g. 8000FF"
            text: /^[0-9A-F]{6}$/.test(root.st.color) ? root.st.color : ""  // not "theme" / "theme:..."
            foreground: root.foreground
            onAccepted: {
              var m = String(text).match(/^#?([0-9a-fA-F]{6})$/)
              if (m) root.setColor(m[1].toUpperCase())
            }
          }

          // Darken everything while all monitors are asleep. It is on unless
          // the user has turned it off, so a missing value counts as "on".
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

          // Night schedule: lights go dark at the first time and come back at
          // the second. A time is only saved once it is a valid HH:MM.
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
            Item { Layout.fillWidth: true }  // pushes the two fields to the left
          }

          // Where Flux looks up sunrise and sunset. Accepts "lat, lon" or
          // "lat lon" in decimal degrees; `led` rejects out-of-range values.
          Text { text: "Flux location (lat, lon)"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          TextField {
            width: parent.width
            placeholderText: "37.77, -122.42"
            text: root.st.location ? root.st.location.join(", ") : ""
            foreground: root.foreground
            onEditingFinished: {
              var m = String(text).match(/^\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*$/)
              if (!m) return
              var loc = [Number(m[1]), Number(m[2])]
              var cur = root.st.location
              if (cur && loc[0] === cur[0] && loc[1] === cur[1]) return  // unchanged
              root.setSchedule({ location: loc })
            }
          }

          // "Turn all off/on" does the same as right-clicking the bar button.
          // "Restart OpenRGB" re-detects devices (e.g. after plugging one in)
          // and re-applies the current settings.
          RowLayout {
            width: parent.width
            Button {
              Layout.fillWidth: true
              text: root.lit ? "Turn all off" : "Turn all on"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.run([root.lit ? "off" : "on"])
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
        }
      }
    }
  }
}
