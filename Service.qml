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
  property var expiryDaysLeft: null
  readonly property bool expiryWarning: loggedIn && expiryDaysLeft !== null && expiryDaysLeft <= expiryWarnDays
  property string deviceName: ""
  property bool active: false
  property string state: "disconnected"
  property string locationCountry: ""
  property string locationCity: ""
  property string relayCountry: ""
  property string relayCity: ""
  property bool lockdown: false
  property bool autoConnect: false
  property bool lanSharing: false
  property var dns: null
  readonly property bool dnsKnown: dns !== null
  readonly property bool dnsCustom: dns !== null && dns.custom === true
  readonly property bool dnsBlockAdsTrackers: dns !== null && dns.blockAds === true && dns.blockTrackers === true
  property var cities: []
  property string lastError: ""
  property string actionStatus: ""

  readonly property int expiryWarnDays: {
    var n = parseInt(String(settings && settings.expiryWarnDays != null ? settings.expiryWarnDays : 7), 10)
    if (!isFinite(n)) n = 7
    if (n < 1) n = 1
    if (n > 90) n = 90
    return n
  }
  readonly property int refreshIntervalSec: {
    var n = parseInt(String(settings && settings.refreshIntervalSec != null ? settings.refreshIntervalSec : 30), 10)
    if (!isFinite(n)) n = 30
    if (n < 5) n = 5
    if (n > 3600) n = 3600
    return n
  }
  readonly property bool busy: whichProcess.running || snapshotProcess.running || accountProcess.running
                               || lockdownGetProcess.running || relayGetProcess.running || relayListProcess.running
                               || autoConnectGetProcess.running || lanGetProcess.running || dnsGetProcess.running
                               || actionProcess.running || installProcess.running || daemonStartProcess.running

  property var _pendingCity: null
  property int _listenBackoffMs: 1000
  property bool _listenWanted: false
  property string _actionKind: ""
  property string _pendingAccount: ""
  property string _snapshotKind: "all"
  property bool _expiryNotified: false
  property double _expectDropUntil: 0
  property double _lastDropNotifyMs: 0

  function clearError() { lastError = "" }

  function markDaemonDown(message) {
    if (daemonRunning) {
      notify("Mullvad daemon stopped", "The VPN is down and your traffic is unprotected.", "critical")
    }
    daemonRunning = false
    active = false
    state = "error"
    locationCountry = ""
    locationCity = ""
    lastError = message || "Mullvad daemon is not running"
  }

  function applyStatus(status) {
    if (!status || status.ignored) return
    var prevState = state
    if (status.state === "error") {
      daemonRunning = false
      active = false
      state = "error"
      locationCountry = ""
      locationCity = ""
    } else {
      daemonRunning = true
      state = status.state
      active = status.active
      locationCountry = status.locationCountry
      locationCity = status.locationCity
    }
    var userInitiated = actionProcess.running || Date.now() < _expectDropUntil
    var drop = Model.dropNotification(prevState, state, userInitiated, lockdown)
    if (drop && Date.now() - _lastDropNotifyMs > 60000) {
      _lastDropNotifyMs = Date.now()
      notify(drop.summary, drop.body, drop.urgency)
    }
  }

  function applyAccount(account) {
    if (!account.loggedIn && daemonRunning === false) return
    loggedIn = account.loggedIn === true
    accountExpiry = account.accountExpiry || ""
    deviceName = account.deviceName || ""
    lastError = Model.nextAccountError(account, lastError)
    expiryDaysLeft = Model.daysUntilExpiry(accountExpiry, new Date())
    if (!loggedIn) {
      _expiryNotified = false
      return
    }
    if (expiryWarning && !_expiryNotified) {
      _expiryNotified = true
      notify(Model.expiryWarningText(expiryDaysLeft), "Top up at mullvad.net/account to keep the VPN running.")
    }
  }

  function notify(summary, body, urgency) {
    if (notifyProcess.running) return
    notifyProcess.command = ["notify-send", "--app-name=Mullvad",
                             "--urgency=" + (urgency || "normal"), summary, body || ""]
    notifyProcess.running = true
  }

  function openAccountPage() {
    if (openUrlProcess.running) return
    openUrlProcess.command = ["xdg-open", "https://mullvad.net/account"]
    openUrlProcess.running = true
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
    // The account number is a credential, so it never goes on the command line
    // where any local process could read it from /proc. `mullvad account login`
    // with no argument prompts for it and reads the answer from stdin.
    _pendingAccount = parsed.digits
    actionProcess.stdinEnabled = true
    actionProcess.command = ["mullvad", "account", "login"]
    actionProcess.running = true
  }

  function logout() {
    if (actionProcess.running) return
    clearError()
    if (active) {
      actionStatus = "Disconnecting…"
      _actionKind = "logout-after-disconnect"
      _expectDropUntil = Date.now() + 5000
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
    _expectDropUntil = Date.now() + 5000
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

  function setAutoConnect(on) {
    if (actionProcess.running) return
    clearError()
    actionStatus = on ? "Enabling auto-connect…" : "Disabling auto-connect…"
    _actionKind = "auto-connect"
    actionProcess.command = ["mullvad", "auto-connect", "set", on ? "on" : "off"]
    actionProcess.running = true
  }

  function setLanSharing(on) {
    if (actionProcess.running) return
    clearError()
    actionStatus = on ? "Allowing LAN sharing…" : "Blocking LAN sharing…"
    _actionKind = "lan"
    actionProcess.command = ["mullvad", "lan", "set", on ? "allow" : "block"]
    actionProcess.running = true
  }

  function setDnsBlockAdsTrackers(on) {
    if (actionProcess.running) return
    // `mullvad dns set default` replaces the whole DNS config, so never
    // toggle blind: skip when the current config is unknown, and never
    // clobber a custom DNS server the user set outside the widget.
    if (dns === null || dns.custom === true) return
    clearError()
    actionStatus = "Updating DNS blockers…"
    _actionKind = "dns"
    actionProcess.command = ["mullvad"].concat(Model.buildDnsSetArgs(dns, on === true))
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
    if (kind === "auto-connect") {
      autoConnectGetProcess.command = ["mullvad", "auto-connect", "get"]
      autoConnectGetProcess.running = true
    }
    if (kind === "lan") {
      lanGetProcess.command = ["mullvad", "lan", "get"]
      lanGetProcess.running = true
    }
    if (kind === "dns") {
      dnsGetProcess.command = ["mullvad", "dns", "get"]
      dnsGetProcess.running = true
    }
    if (kind === "set-city") {
      relayGetProcess.command = ["mullvad", "relay", "get"]
      relayGetProcess.running = true
      if (active || state === "connecting") {
        _actionKind = "reconnect"
        _expectDropUntil = Date.now() + 5000
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
      autoConnectGetProcess.command = ["mullvad", "auto-connect", "get"]
      autoConnectGetProcess.running = true
    }
  }

  Process {
    id: autoConnectGetProcess
    running: false
    command: []
    stdout: StdioCollector { id: autoConnectOut; waitForEnd: true }
    onExited: function() {
      root.autoConnect = Model.parseAutoConnectGet(autoConnectOut.text)
      lanGetProcess.command = ["mullvad", "lan", "get"]
      lanGetProcess.running = true
    }
  }

  Process {
    id: lanGetProcess
    running: false
    command: []
    stdout: StdioCollector { id: lanOut; waitForEnd: true }
    onExited: function() {
      root.lanSharing = Model.parseLanGet(lanOut.text)
      dnsGetProcess.command = ["mullvad", "dns", "get"]
      dnsGetProcess.running = true
    }
  }

  Process {
    id: dnsGetProcess
    running: false
    command: []
    stdout: StdioCollector { id: dnsOut; waitForEnd: true }
    onExited: function() {
      root.dns = Model.parseDnsGet(dnsOut.text)
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
    onStarted: {
      if (root._pendingAccount === "") return
      actionProcess.write(root._pendingAccount + "\n")
      root._pendingAccount = ""
      actionProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      root._pendingAccount = ""
      actionProcess.stdinEnabled = false
      root.finishAction(exitCode, actionOut.text, actionErr.text)
    }
  }

  Process {
    id: notifyProcess
    running: false
    command: []
  }

  Process {
    id: openUrlProcess
    running: false
    command: []
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
