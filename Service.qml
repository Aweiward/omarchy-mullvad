import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool daemonRunning: false
  property bool loggedIn: false
  property string accountExpiry: ""
  property string deviceName: ""
  property bool active: false
  property string state: "disconnected"
  property string locationCountry: ""
  property string locationCity: ""
  property string relayCountry: ""
  property string relayCity: ""
  property bool lockdown: false
  property var cities: []
  property string lastError: ""
  property string actionStatus: ""

  readonly property int refreshIntervalSec: {
    var n = parseInt(String(settings && settings.refreshIntervalSec != null ? settings.refreshIntervalSec : 30), 10)
    if (!isFinite(n)) n = 30
    if (n < 5) n = 5
    if (n > 3600) n = 3600
    return n
  }
  readonly property bool busy: whichProcess.running || snapshotProcess.running || accountProcess.running
                               || lockdownGetProcess.running || relayGetProcess.running || relayListProcess.running
                               || actionProcess.running || installProcess.running || daemonStartProcess.running

  property var _pendingCity: null
  property int _listenBackoffMs: 1000
  property bool _listenWanted: false
  property string _actionKind: ""
  property string _snapshotKind: "all"

  function clearError() { lastError = "" }

  function markDaemonDown(message) {
    daemonRunning = false
    active = false
    state = "error"
    locationCountry = ""
    locationCity = ""
    lastError = message || "Mullvad daemon is not running"
  }

  function applyStatus(status) {
    if (!status || status.ignored) return
    if (status.state === "error") {
      daemonRunning = false
      active = false
      state = "error"
      locationCountry = ""
      locationCity = ""
      return
    }
    daemonRunning = true
    state = status.state
    active = status.active
    locationCountry = status.locationCountry
    locationCity = status.locationCity
  }

  function applyAccount(account) {
    if (!account.loggedIn && daemonRunning === false) return
    loggedIn = account.loggedIn === true
    accountExpiry = account.accountExpiry || ""
    deviceName = account.deviceName || ""
    if (!account.loggedIn && account.error) lastError = account.error
  }

  function probe() {
    whichProcess.command = ["which", "mullvad"]
    whichProcess.running = true
  }

  function refresh() {
    if (!installed) {
      probe()
      return
    }
    _snapshotKind = "all"
    snapshotProcess.command = ["mullvad", "status", "--json"]
    snapshotProcess.running = true
  }

  function loadCities() {
    if (!installed || relayListProcess.running) return
    relayListProcess.command = ["mullvad", "relay", "list"]
    relayListProcess.running = true
  }

  function startListen() {
    _listenWanted = installed
    if (!installed) {
      listenProcess.running = false
      return
    }
    if (listenProcess.running) return
    listenProcess.command = ["mullvad", "status", "--json", "listen"]
    listenProcess.running = true
  }

  function installDaemon() {
    clearError()
    actionStatus = "Installing Mullvad…"
    installProcess.command = ["omarchy", "pkg", "add", "mullvad-vpn-daemon"]
    installProcess.running = true
  }

  function startDaemon() {
    clearError()
    actionStatus = "Starting Mullvad daemon…"
    daemonStartProcess.command = ["systemctl", "enable", "--now", "mullvad-daemon.service"]
    daemonStartProcess.running = true
  }

  function login(accountNumber) {
    var parsed = Model.normalizeAccountNumber(accountNumber)
    if (!parsed.ok) {
      lastError = parsed.error
      return
    }
    if (actionProcess.running) return
    clearError()
    actionStatus = "Logging in…"
    _actionKind = "login"
    actionProcess.command = ["mullvad", "account", "login", parsed.digits]
    actionProcess.running = true
  }

  function logout() {
    if (actionProcess.running) return
    clearError()
    if (active) {
      actionStatus = "Disconnecting…"
      _actionKind = "logout-after-disconnect"
      actionProcess.command = ["mullvad", "disconnect"]
      actionProcess.running = true
      return
    }
    actionStatus = "Logging out…"
    _actionKind = "logout"
    actionProcess.command = ["mullvad", "account", "logout"]
    actionProcess.running = true
  }

  function connectTunnel() {
    if (actionProcess.running) return
    clearError()
    actionStatus = "Connecting…"
    _actionKind = "connect"
    actionProcess.command = ["mullvad", "connect", "--wait"]
    actionProcess.running = true
  }

  function disconnectTunnel() {
    if (actionProcess.running) return
    clearError()
    actionStatus = "Disconnecting…"
    _actionKind = "disconnect"
    actionProcess.command = ["mullvad", "disconnect"]
    actionProcess.running = true
  }

  function toggleTunnel() {
    if (!installed || !loggedIn) return
    if (active || state === "connecting") disconnectTunnel()
    else connectTunnel()
  }

  function setCity(countryCode, cityCode) {
    if (!installed || !loggedIn) return
    var next = { country: String(countryCode || ""), city: String(cityCode || "") }
    if (next.country === "" || next.city === "") return
    if (actionProcess.running) {
      _pendingCity = next
      return
    }
    clearError()
    actionStatus = "Setting location…"
    _actionKind = "set-city"
    actionProcess.command = ["mullvad", "relay", "set", "location", next.country, next.city]
    actionProcess.running = true
  }

  function setLockdown(on) {
    if (actionProcess.running) return
    clearError()
    actionStatus = on ? "Enabling lockdown…" : "Disabling lockdown…"
    _actionKind = "lockdown"
    actionProcess.command = ["mullvad", "lockdown-mode", "set", on ? "on" : "off"]
    actionProcess.running = true
  }

  function finishAction(exitCode, stdout, stderr) {
    var err = String(stderr || stdout || "").trim()
    var kind = _actionKind
    _actionKind = ""
    actionStatus = ""
    if (exitCode !== 0) {
      lastError = err || "Mullvad command failed"
      if (kind === "logout-after-disconnect") return
      if (_pendingCity) {
        var failedPending = _pendingCity
        _pendingCity = null
        setCity(failedPending.country, failedPending.city)
      }
      return
    }
    if (kind === "login" || kind === "logout") {
      accountProcess.command = ["mullvad", "account", "get"]
      accountProcess.running = true
    }
    if (kind === "lockdown") {
      lockdownGetProcess.command = ["mullvad", "lockdown-mode", "get"]
      lockdownGetProcess.running = true
    }
    if (kind === "set-city") {
      relayGetProcess.command = ["mullvad", "relay", "get"]
      relayGetProcess.running = true
      if (active || state === "connecting") {
        _actionKind = "reconnect"
        actionProcess.command = ["mullvad", "reconnect"]
        actionProcess.running = true
        return
      }
    }
    if (kind === "logout-after-disconnect") {
      _actionKind = "logout"
      actionProcess.command = ["mullvad", "account", "logout"]
      actionProcess.running = true
      return
    }
    if (_pendingCity) {
      var pending = _pendingCity
      _pendingCity = null
      setCity(pending.country, pending.city)
    }
  }

  Component.onCompleted: probe()

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) {
        root.refresh()
        root.startListen()
      } else {
        root.daemonRunning = false
        root.loggedIn = false
      }
    }
  }

  Process {
    id: listenProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line || "").trim()
        if (text === "") return
        root.applyStatus(Model.parseStatusJson(text))
        root._listenBackoffMs = 1000
        fallbackPoll.stop()
      }
    }
    onExited: function() {
      if (!root._listenWanted) return
      root.refresh()
      fallbackPoll.interval = root.refreshIntervalSec * 1000
      fallbackPoll.running = true
      listenRestart.interval = root._listenBackoffMs
      listenRestart.restart()
      root._listenBackoffMs = Math.min(30000, root._listenBackoffMs * 2)
    }
  }

  Timer {
    id: listenRestart
    interval: 1000
    repeat: false
    onTriggered: root.startListen()
  }

  Timer {
    id: fallbackPoll
    interval: 30000
    repeat: true
    running: false
    onTriggered: root.refresh()
  }

  Process {
    id: snapshotProcess
    running: false
    command: []
    stdout: StdioCollector { id: snapshotOut; waitForEnd: true }
    stderr: StdioCollector { id: snapshotErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyStatus(Model.parseStatusJson(snapshotOut.text))
      else root.markDaemonDown(String(snapshotErr.text || "").trim() || "Mullvad daemon is not running")
      if (root.installed && root.daemonRunning) {
        accountProcess.command = ["mullvad", "account", "get"]
        accountProcess.running = true
      }
    }
  }

  Process {
    id: accountProcess
    running: false
    command: []
    stdout: StdioCollector { id: accountOut; waitForEnd: true }
    stderr: StdioCollector { id: accountErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.applyAccount(Model.parseAccountGet(accountOut.text || accountErr.text, exitCode))
      lockdownGetProcess.command = ["mullvad", "lockdown-mode", "get"]
      lockdownGetProcess.running = true
    }
  }

  Process {
    id: lockdownGetProcess
    running: false
    command: []
    stdout: StdioCollector { id: lockdownOut; waitForEnd: true }
    onExited: function() {
      root.lockdown = Model.parseLockdownGet(lockdownOut.text)
      relayGetProcess.command = ["mullvad", "relay", "get"]
      relayGetProcess.running = true
    }
  }

  Process {
    id: relayGetProcess
    running: false
    command: []
    stdout: StdioCollector { id: relayOut; waitForEnd: true }
    onExited: function() {
      var relay = Model.parseRelayGet(relayOut.text)
      root.relayCountry = relay.country
      root.relayCity = relay.city
    }
  }

  Process {
    id: relayListProcess
    running: false
    command: []
    stdout: StdioCollector { id: relayListOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.cities = Model.parseRelayList(relayListOut.text)
      else root.cities = []
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishAction(exitCode, actionOut.text, actionErr.text)
    }
  }

  Process {
    id: installProcess
    running: false
    command: []
    stdout: StdioCollector { id: installOut; waitForEnd: true }
    stderr: StdioCollector { id: installErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.actionStatus = ""
      if (exitCode !== 0) {
        root.lastError = String(installErr.text || installOut.text || "Install failed").trim()
        return
      }
      root.startDaemon()
    }
  }

  Process {
    id: daemonStartProcess
    running: false
    command: []
    stdout: StdioCollector { id: daemonOut; waitForEnd: true }
    stderr: StdioCollector { id: daemonErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.actionStatus = ""
      if (exitCode !== 0)
        root.lastError = String(daemonErr.text || "Mullvad daemon is not running").trim()
      root.probe()
    }
  }
}
