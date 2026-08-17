import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "aweiward.mullvad"
  ipcTarget: "aweiward.mullvad"
  manageIpc: false

  property string focusSection: "header"
  readonly property var toggleSections: ["lockdown", "autoconnect", "lan", "dns"]
  property int cityIndex: 0
  property bool cursorActive: false
  property string cityQuery: ""
  property string accountField: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: (mullvad.active || mullvad.state === "connecting" || mullvad.state === "disconnecting") ? foreground : dim
  readonly property color barIconColor: (mullvad.active || mullvad.state === "connecting" || mullvad.state === "disconnecting") ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && mullvad.installed && mullvad.loggedIn
  readonly property bool fieldFocused: (accountInput && accountInput.activeFocus) || (citySearch && citySearch.activeFocus)
  readonly property var recentKeys: settings.recentCities instanceof Array ? settings.recentCities : []
  readonly property var visibleCities: Model.filterCities(Model.mergeRecentCities(recentKeys, mullvad.cities), cityQuery)
  readonly property bool ready: mullvad.installed && mullvad.loggedIn
  readonly property bool iconCrossed: mullvad.installed && mullvad.loggedIn && !mullvad.active && mullvad.state !== "connecting" && mullvad.state !== "disconnecting"
  readonly property string toggleHint: mullvad.active ? "Disconnect Mullvad" : "Connect Mullvad"
  readonly property string heroTitle: {
    if (!mullvad.installed) return "Mullvad"
    if (!mullvad.loggedIn) return "Mullvad"
    if (mullvad.locationCity !== "") return mullvad.locationCity
    return "Mullvad"
  }
  readonly property string heroMeta: {
    if (!mullvad.installed) return "Mullvad is not installed"
    if (!mullvad.loggedIn) return "Not logged in"
    if (mullvad.active) return (mullvad.locationCountry !== "" ? mullvad.locationCountry + " · Connected" : "Connected")
    if (mullvad.state === "connecting") return "Connecting…"
    if (mullvad.state === "disconnecting") return "Disconnecting…"
    return "Disconnected"
  }

  function selectedCity() {
    if (visibleCities.length === 0) return null
    return visibleCities[Math.max(0, Math.min(cityIndex, visibleCities.length - 1))]
  }

  function persistRecent(countryCode, cityCode) {
    var key = String(countryCode || "") + " " + String(cityCode || "")
    if (key === " ") return
    var next = [key]
    for (var i = 0; i < recentKeys.length && next.length < 5; i++) {
      var existing = String(recentKeys[i] || "")
      if (existing !== "" && existing !== key && next.indexOf(existing) === -1) next.push(existing)
    }
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var k in settings) if (k !== "id") entry[k] = settings[k]
    entry.recentCities = next
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function chooseCity(row) {
    if (!row) return
    persistRecent(row.countryCode, row.cityCode)
    mullvad.setCity(row.countryCode, row.cityCode)
  }

  function submitLogin() {
    mullvad.login(accountField)
  }

  function ensureCursor() {
    if (!mullvad.installed) { focusSection = "install"; return }
    if (!mullvad.loggedIn) { focusSection = "login"; return }
    if (focusSection === "install" || focusSection === "login") focusSection = "header"
    if (cityIndex >= visibleCities.length) cityIndex = Math.max(0, visibleCities.length - 1)
    if (cityIndex < 0) cityIndex = 0
  }

  function syncFocus() {
    if (mullvad.installed && !mullvad.loggedIn && accountInput)
      accountInput.forceActiveFocus()
    else
      keyCatcher.forceActiveFocus()
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0) focusSection = toggleSections[0]
      return
    }
    var ti = toggleSections.indexOf(focusSection)
    if (ti !== -1) {
      if (dy < 0) { focusSection = ti === 0 ? "header" : toggleSections[ti - 1]; return }
      if (ti < toggleSections.length - 1) { focusSection = toggleSections[ti + 1]; return }
      if (visibleCities.length > 0) { focusSection = "cities"; cityIndex = 0 }
      return
    }
    if (focusSection === "cities") {
      if (dy < 0 && cityIndex === 0) { focusSection = toggleSections[toggleSections.length - 1]; return }
      cityIndex = Math.max(0, Math.min(visibleCities.length - 1, cityIndex + dy))
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") mullvad.toggleTunnel()
    else if (focusSection === "lockdown") mullvad.setLockdown(!mullvad.lockdown)
    else if (focusSection === "autoconnect") mullvad.setAutoConnect(!mullvad.autoConnect)
    else if (focusSection === "lan") mullvad.setLanSharing(!mullvad.lanSharing)
    else if (focusSection === "dns") mullvad.setDnsBlockAdsTrackers(!mullvad.dnsBlockAdsTrackers)
    else if (focusSection === "cities") chooseCity(selectedCity())
    else if (focusSection === "install") mullvad.installDaemon()
    else if (focusSection === "login") submitLogin()
    else if (focusSection === "daemon") mullvad.startDaemon()
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function setToggleCursor(section) {
    cursorActive = true
    focusSection = section
  }

  function setCityCursor(index) {
    cursorActive = true
    focusSection = "cities"
    cityIndex = index
    scrollCursorIntoView()
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "cities" && cityColumn && cityIndex >= 0 && cityIndex < cityColumn.children.length)
      scrollItemIntoView(cityColumn.children[cityIndex])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cityQuery = ""
    if (panelFlick) panelFlick.contentY = 0
    mullvad.refresh()
    if (mullvad.installed && mullvad.cities.length === 0) mullvad.loadCities()
    ensureCursor()
    Qt.callLater(syncFocus)
  }
  onCityIndexChanged: scrollCursorIntoView()
  onVisibleCitiesChanged: ensureCursor()

  Service {
    id: mullvad
    settings: root.settings
  }

  Connections {
    target: mullvad
    function onInstalledChanged() {
      if (mullvad.installed && mullvad.cities.length === 0) mullvad.loadCities()
      root.ensureCursor()
      Qt.callLater(root.syncFocus)
    }
    function onLoggedInChanged() {
      if (mullvad.loggedIn && mullvad.cities.length === 0) mullvad.loadCities()
      if (mullvad.loggedIn) root.accountField = ""
      root.ensureCursor()
      Qt.callLater(root.syncFocus)
    }
    function onCitiesChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { mullvad.refresh(); mullvad.loadCities(); return "ok" }
    function connect(): string { mullvad.connectTunnel(); return "ok" }
    function disconnect(): string { mullvad.disconnectTunnel(); return "ok" }
    function status(): string { return mullvad.state }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        MullvadIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: root.iconCrossed
          warning: !mullvad.installed || !mullvad.loggedIn
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (mullvad.installed && mullvad.loggedIn) mullvad.toggleTunnel()
        else root.toggle()
      } else if (buttonCode === Qt.MiddleButton) {
        mullvad.refresh()
        mullvad.loadCities()
      } else {
        root.toggle()
      }
    }
  }

  // Must stay outside KeyboardPanel: that type's default property is
  // contentItem (QQuickItem list). Shortcut is not an Item, and putting it
  // there fails the whole widget load.
  Shortcut {
    sequences: ["l", "L"]
    enabled: root.opened && root.ready && !root.fieldFocused
    onActivated: mullvad.setLockdown(!mullvad.lockdown)
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.fieldFocused
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive || root.focusSection === "install" || root.focusSection === "login") root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") {
          if (root.ready) mullvad.toggleTunnel()
        } else if (t === "/") {
          if (root.ready && citySearch) citySearch.forceActiveFocus()
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: root.heroTitle
              meta: root.heroMeta
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: (mullvad.active || mullvad.state === "connecting" || mullvad.state === "disconnecting") ? 1.0 : 0.5
              iconComponent: Component {
                MullvadIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  crossed: root.iconCrossed
                  warning: !mullvad.installed || !mullvad.loggedIn
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: root.ready
                  checked: mullvad.active
                  busy: mullvad.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: mullvad.toggleTunnel()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: mullvad.actionStatus !== "" || mullvad.lastError !== ""
            width: parent.width
            text: mullvad.actionStatus !== "" ? mullvad.actionStatus : mullvad.lastError
            color: mullvad.lastError !== "" && mullvad.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            id: daemonBody
            visible: mullvad.installed && !mullvad.daemonRunning
            width: parent.width
            implicitHeight: daemonCol.implicitHeight + Style.spacing.rowPaddingX
            hasCursor: root.cursorActive && root.focusSection === "daemon"
            foreground: root.foreground
            fill: root.hoverFill

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: mullvad.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
              enabled: !mullvad.busy
              onEntered: {
                root.cursorActive = true
                root.focusSection = "daemon"
              }
              onClicked: mullvad.startDaemon()
            }

            Column {
              id: daemonCol
              width: parent.width
              spacing: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.space(10)
              rightPadding: Style.space(10)

              Text {
                width: parent.width - daemonCol.leftPadding - daemonCol.rightPadding
                text: "Mullvad daemon is not running"
                color: root.dim
                wrapMode: Text.WordWrap
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: mullvad.busy ? "Starting…" : "Start daemon"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          CursorSurface {
            id: installBody
            visible: !mullvad.installed
            width: parent.width
            implicitHeight: installCol.implicitHeight + Style.spacing.rowPaddingX
            hasCursor: root.cursorActive && root.focusSection === "install"
            foreground: root.foreground
            fill: root.hoverFill

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: mullvad.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
              enabled: !mullvad.busy
              onEntered: {
                root.cursorActive = true
                root.focusSection = "install"
              }
              onClicked: mullvad.installDaemon()
            }

            Column {
              id: installCol
              width: parent.width
              spacing: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.space(10)
              rightPadding: Style.space(10)

              Text {
                width: parent.width - installCol.leftPadding - installCol.rightPadding
                text: "Mullvad daemon is not installed. Installs mullvad-vpn-daemon from Arch extra. Leaves the official app alone if it is already there."
                color: root.dim
                wrapMode: Text.WordWrap
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: mullvad.busy ? "Installing…" : "Install Mullvad"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Column {
            visible: mullvad.installed && !mullvad.loggedIn
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Log in with your 16-digit Mullvad account number."
              color: root.dim
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            TextField {
              id: accountInput
              width: parent.width
              foreground: root.foreground
              placeholderText: "Account number"
              text: root.accountField
              onTextChanged: root.accountField = text
              onAccepted: root.submitLogin()
              Keys.onEscapePressed: root.close()
            }

            CursorSurface {
              id: loginButton
              width: parent.width
              implicitHeight: Style.space(36)
              hasCursor: root.cursorActive && root.focusSection === "login"
              foreground: root.foreground
              fill: root.hoverFill

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: mullvad.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                enabled: !mullvad.busy
                onEntered: {
                  root.cursorActive = true
                  root.focusSection = "login"
                }
                onClicked: root.submitLogin()
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                text: mullvad.busy ? "Logging in…" : "Log in"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          SettingRow {
            section: "lockdown"
            label: "Lockdown"
            checked: mullvad.lockdown
            width: parent.width
            onToggleRequested: mullvad.setLockdown(!mullvad.lockdown)
          }

          SettingRow {
            section: "autoconnect"
            label: "Auto-connect"
            checked: mullvad.autoConnect
            width: parent.width
            onToggleRequested: mullvad.setAutoConnect(!mullvad.autoConnect)
          }

          SettingRow {
            section: "lan"
            label: "LAN sharing"
            checked: mullvad.lanSharing
            width: parent.width
            onToggleRequested: mullvad.setLanSharing(!mullvad.lanSharing)
          }

          SettingRow {
            section: "dns"
            label: "Block ads & trackers"
            checked: mullvad.dnsBlockAdsTrackers
            rowEnabled: mullvad.dnsKnown && !mullvad.dnsCustom
            hint: mullvad.dnsCustom ? "Custom DNS is active; manage blocking with the CLI." : ""
            width: parent.width
            onToggleRequested: mullvad.setDnsBlockAdsTrackers(!mullvad.dnsBlockAdsTrackers)
          }

          Column {
            visible: root.ready
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: citySearch
              width: parent.width
              foreground: root.foreground
              placeholderText: "Search cities…"
              text: root.cityQuery
              onTextChanged: {
                root.cityQuery = text
                root.cityIndex = 0
              }
              onAccepted: root.chooseCity(root.selectedCity())
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down || event.text === "j") {
                  root.moveCursor(0, 1)
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Up || event.text === "k") {
                  root.moveCursor(0, -1)
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.chooseCity(root.selectedCity())
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Escape) {
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }
            }

            Text {
              visible: root.visibleCities.length === 0
              width: parent.width
              text: "No cities found."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: cityColumn
              visible: root.visibleCities.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.visibleCities
                CityRow {
                  required property var modelData
                  required property int index
                  width: cityColumn.width
                  city: modelData
                  rowIndex: index
                }
              }
            }
          }

          Text {
            visible: root.ready
            width: parent.width
            text: {
              var bits = []
              if (mullvad.deviceName !== "") bits.push(mullvad.deviceName)
              if (mullvad.accountExpiry !== "") bits.push("expires " + mullvad.accountExpiry)
              bits.push("Log out")
              return bits.join(" · ")
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: mullvad.logout()
            }
          }
        }
      }
    }
  }

  component SettingRow: CursorSurface {
    id: settingRow
    property string label: ""
    property string section: ""
    property bool checked: false
    property bool rowEnabled: true
    property string hint: ""
    signal toggleRequested()

    visible: root.ready
    implicitHeight: Math.max(Style.space(36), settingInner.implicitHeight + Style.spacing.rowPaddingX)
    hasCursor: root.cursorActive && root.focusSection === settingRow.section
    foreground: root.foreground
    fill: root.hoverFill

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: (mullvad.busy || !settingRow.rowEnabled) ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !mullvad.busy && settingRow.rowEnabled
      onEntered: root.setToggleCursor(settingRow.section)
      onClicked: settingRow.toggleRequested()
    }

    Row {
      id: settingInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)

      Column {
        width: parent.width - settingSwitch.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: settingRow.label
          color: settingRow.rowEnabled ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          visible: settingRow.hint !== ""
          width: parent.width
          text: settingRow.hint
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }

      ToggleSwitch {
        id: settingSwitch
        checked: settingRow.checked
        busy: mullvad.busy
        interactive: false
        cursorRing: false
        foreground: root.foreground
        opacity: settingRow.rowEnabled ? 1.0 : 0.4
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  component CityRow: CursorSurface {
    id: cityRow
    property var city: null
    property int rowIndex: 0
    readonly property bool selectedRelay: city && city.countryCode === mullvad.relayCountry && city.cityCode === mullvad.relayCity

    hasCursor: root.cursorActive && root.focusSection === "cities" && root.cityIndex === rowIndex
    current: selectedRelay
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: Style.space(32)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCityCursor(cityRow.rowIndex)
      onClicked: {
        root.cityIndex = cityRow.rowIndex
        root.chooseCity(cityRow.city)
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      text: cityRow.city ? (cityRow.city.country + " · " + cityRow.city.city) : ""
      color: cityRow.selectedRelay || cityRow.hasCursor ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }
}
