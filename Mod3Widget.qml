import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Mod3 Solitaire bar toggle. Clicking launches the game if it is not running,
// parks its window on the special:mod3 scratchpad, and shows the scratchpad;
// click again to hide it. The game is a V/gg app whose Wayland EGL path
// renders a blank window on this hardware, so launches strip WAYLAND_DISPLAY
// to force the XWayland backend. The floating window is dynamically resized
// to 70% of the focused monitor and positioned 10 px below the bar.
BarWidget {
  id: root
  moduleName: "com.darkhorse-studios.mod3-bar-widget"

  readonly property string special: "mod3"
  readonly property string gameTitle: "Mod3 Solitaire"
  readonly property string gameBinary: root.expandHome(root.setting("binary", "~/Applications/Mod3_Solitaire.AppImage"))

  // execArgv passes argv straight to exec as positional parameters, which a
  // shell never tilde-expands, so a bare "~" in the binary path must be
  // resolved here before launching.
  function expandHome(path) {
    var p = String(path || "")
    if (p === "~") return Quickshell.env("HOME")
    if (p.startsWith("~/")) return Quickshell.env("HOME") + p.substring(1)
    return p
  }

  property bool hasClient: false
  property bool shown: false
  property bool launching: false

  readonly property bool running: root.hasClient || root.launching

  function isMod3(win) {
    return win && String(win.title || "") === root.gameTitle
  }

  function hasMod3Client(clients) {
    for (var i = 0; i < clients.length; i++) {
      if (root.isMod3(clients[i])) return true
    }
    return false
  }

  function getMod3Client(clients) {
    for (var i = 0; i < clients.length; i++) {
      if (root.isMod3(clients[i])) return clients[i]
    }
    return null
  }

  // ------------- scratchpad visibility (source of truth for `shown`) -------------

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name || "") !== "activespecial") return
      var parts = String(event.data || "").split(",")
      root.shown = parts[0] === "special:" + root.special
    }
  }

  // ------------- hyprctl plumbing -------------

  property var pendingClients: null
  property var pendingMonitors: null

  Process {
    id: clientsProcess
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        var clients = []
        try { clients = JSON.parse(String(text || "")) } catch (e) {}
        var cb = root.pendingClients
        root.pendingClients = null
        if (cb) cb(clients)
        else root.applyClients(clients)
      }
    }
  }

  Process {
    id: monitorsProcess
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        var monitors = []
        try { monitors = JSON.parse(String(text || "")) } catch (e) {}
        var cb = root.pendingMonitors
        root.pendingMonitors = null
        if (cb) cb(monitors)
      }
    }
  }

  // Dispatches run one at a time: the compositor only accepts them against a
  // settled state, and two hyprctl calls racing each other is how windows end
  // up on the wrong workspace. Queue rather than stack.
  property var dispatchQueue: []

  Process {
    id: dispatchProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        Qt.callLater(root.pumpDispatch)
      }
    }
  }

  function runDispatch(command) {
    root.dispatchQueue.push(command)
    root.pumpDispatch()
  }

  function pumpDispatch() {
    if (dispatchProcess.running) return
    if (root.dispatchQueue.length === 0) {
      root.refreshState()
      return
    }
    dispatchProcess.command = root.dispatchQueue.shift()
    dispatchProcess.running = true
  }

  function workspaceName(win) {
    var ws = win ? win.workspace : null
    return ws ? String(ws.name || "") : ""
  }

  // Park the game window on the scratchpad unless it is already there. The
  // AppImage launches onto the active workspace, so this move is what actually
  // puts the dropdown on special:mod3; a map-time rule in looknfeel.lua catches
  // the first frame, but this is the source of truth.
  function moveToScratchpad(win) {
    if (!win || !win.address) return
    if (workspaceName(win) === "special:" + root.special) return
    root.runDispatch(["hyprctl", "dispatch", 'hl.dsp.window.move({ window = "address:' + win.address + '", workspace = "special:' + root.special + '" })'])
  }

  function toggleSpecial() {
    root.runDispatch(["hyprctl", "dispatch", 'hl.dsp.workspace.toggle_special("' + root.special + '")'])
  }

  function queryClients(cb) {
    root.pendingClients = cb
    if (!clientsProcess.running) clientsProcess.running = true
  }

  function queryMonitors(cb) {
    root.pendingMonitors = cb
    if (!monitorsProcess.running) monitorsProcess.running = true
  }

  function refreshState() {
    root.queryClients(null)
  }

  // ------------- runtime auto-sizing to 70% x 70% of the active monitor -------------

  function focusedMonitor(monitors) {
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i] && monitors[i].focused) return monitors[i]
    }
    return monitors.length ? monitors[0] : null
  }

  function logicalMonitorSize(monitor) {
    var scale = Math.max(1, (monitor.scale || 1))
    var rotated = ((monitor.transform || 0) % 2) === 1
    var width = rotated ? monitor.height : monitor.width
    var height = rotated ? monitor.width : monitor.height
    return { width: width / scale, height: height / scale }
  }

  function resizeToClean(win, monitors) {
    if (!win || !win.address) return
    var monitor = root.focusedMonitor(monitors)
    if (!monitor) return
    if (!win.floating) {
      root.runDispatch(["hyprctl", "dispatch", 'hl.dsp.window.float({ window = "address:' + win.address + '", action = "on" })'])
    }
    var size = root.logicalMonitorSize(monitor)
    var w = Math.max(200, Math.round(size.width * 0.7))
    var h = Math.max(150, Math.round(size.height * 0.7))
    var address = "address:" + win.address
    root.runDispatch(["hyprctl", "dispatch", 'hl.dsp.window.resize({ window = "' + address + '", x = ' + w + ', y = ' + h + ' })'])
    var position = root.bar ? String(root.bar.position || "top") : "top"
    var barThickness = (position === "left" || position === "right") ? 0 : root.barSize
    var monitorLeft = Math.round(monitor.x)
    var monitorTop = Math.round(monitor.y)
    var monitorRight = monitorLeft + size.width
    var monitorBottom = monitorTop + size.height
    var barBottom = (position === "bottom")
      ? monitorBottom
      : monitorTop + barThickness
    var x = Util.clamp(monitorLeft + Math.round((size.width - w) / 2), monitorLeft, Math.max(monitorLeft, monitorRight - w))
    var y = Util.clamp(barBottom + 10, monitorTop, Math.max(monitorTop, monitorBottom - h))
    root.runDispatch(["hyprctl", "dispatch", 'hl.dsp.window.move({ window = "' + address + '", x = ' + x + ', y = ' + y + ' })'])
  }

  function autoSizeWindow(win) {
    if (!win || !win.address) return
    root.queryMonitors(function(monitors) {
      root.resizeToClean(win, monitors)
    })
  }

  function applyClients(clients) {
    root.hasClient = root.hasMod3Client(clients)
    if (root.hasClient) root.launching = false
  }

  // ------------- click: launch if needed, then flip the scratchpad -------------

  function onToggle() {
    if (root.launching) return
    root.queryClients(function(clients) {
      var win = root.getMod3Client(clients)
      if (win) {
        root.moveToScratchpad(win)
        root.autoSizeWindow(win)
        root.toggleSpecial()
      } else {
        root.launchGame()
      }
    })
  }

  // ------------- launch -------------

  Timer {
    id: launchPoll
    interval: 350
    repeat: true
    running: false
    property int attempts: 0
    onTriggered: root.pollLaunch()
  }

  function launchGame() {
    root.launching = true
    launchPoll.attempts = 0
    launchPoll.running = true
    Util.execArgv(["env", "-u", "WAYLAND_DISPLAY", root.gameBinary])
    root.pollLaunch()
  }

  function pollLaunch() {
    root.queryClients(function(clients) {
      var win = root.getMod3Client(clients)
      if (win) {
        launchPoll.running = false
        launchPoll.attempts = 0
        root.launching = false
        // Park the fresh window on the scratchpad, then open it. If the
        // scratchpad somehow was already showing, `shown` is true and the
        // toggle is skipped.
        root.moveToScratchpad(win)
        root.autoSizeWindow(win)
        if (!root.shown) root.toggleSpecial()
      } else if (++launchPoll.attempts >= 40) {
        launchPoll.running = false
        launchPoll.attempts = 0
        root.launching = false
      }
    })
  }

  Timer {
    id: stateRefresh
    interval: 3000
    repeat: true
    running: true
    onTriggered: root.refreshState()
  }

  Component.onCompleted: Qt.callLater(root.refreshState)

  // ------------- IPC (keybinding) -------------
  // `omarchy-shell -q com.darkhorse-studios.mod3-bar-widget toggle` (see
  // ~/.config/hypr/bindings.lua).

  IpcHandler {
    target: "com.darkhorse-studios.mod3-bar-widget"

    function toggle(): void { root.onToggle() }
    function show(): void { if (!root.shown) root.onToggle() }
    function hide(): void { if (root.shown) root.onToggle() }
  }

  // ------------- bar button -------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uDB81\uDE38" // nf-md-cards
    active: root.shown
    dimmed: !root.running
    tooltipText: root.shown ? "Hide Mod3 Solitaire" : "Play Mod3 Solitaire"
    onPressed: function(buttonId) {
      if (buttonId === Qt.LeftButton) root.onToggle()
    }
  }
}
