# Mullvad Omarchy Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `ethos.mullvad`, a Tailscale-shaped Omarchy bar widget that wraps the official Mullvad CLI (account, city picker, connect/disconnect, lockdown) for this machine and for omarchyplugins.com.

**Architecture:** Pure parsers live in `Model.js` and are tested with Node. `Service.qml` owns `mullvad` processes, including a long-lived `mullvad status --json listen`. `Panel.qml` is the bar button plus one panel whose body swaps between Install, Login, and Ready. Icon is a themed Mullvad mark drawn in QML.

**Tech Stack:** Omarchy 4 / Quickshell QML, Node `node:test` for `Model.js`, Mullvad CLI 2026.3 (`mullvad`, `mullvad-daemon.service`), `omarchy pkg add` for install.

**Spec:** `docs/superpowers/specs/2026-08-15-mullvad-plugin-design.md`

---

## File map

All paths are relative to `/home/ethos/Projects/omarchy-mullvad` (plugin root = repo root, required by `omarchy plugin add`).

| File | Responsibility |
|---|---|
| `manifest.json` | Plugin contract |
| `Model.js` | Pure parse/filter. No Qt. Node-testable |
| `MullvadIcon.qml` | Themed circle-and-cross + crossed + warning badge |
| `Service.qml` | CLI probe, listen, one-shot actions, published state |
| `Panel.qml` | Bar button + KeyboardPanel |
| `README.md` | Install, shortcuts, requirements |
| `package.json` | `"test": "node --test tests/*.test.js"` |
| `tests/model.test.js` | Model unit tests |
| `tests/fixtures/relay-list.txt` | Trimmed `mullvad relay list` fixture |
| `tests/fixtures/status-disconnected.json` | Real disconnected status payload |
| `tests/cli-contract.sh` | Read-only live CLI parse check |
| `.gitignore` | `node_modules/`, `.superpowers/` |

Reference implementations (read, do not copy wholesale):

- `/usr/share/omarchy/shell/plugins/panels/tailscale/` — Service + PanelHero + ToggleSwitch + right-click
- `/usr/share/omarchy/shell/plugins/services/idle/Service.qml` — `SplitParser` on a long-lived process
- `/usr/share/omarchy/shell/plugins/panels/dropbox/Panel.qml` — unauthenticated panel body

Development install (after Task 8):

```bash
ln -sfn /home/ethos/Projects/omarchy-mullvad ~/.config/omarchy/plugins/ethos.mullvad
omarchy-shell shell rescanPlugins
omarchy plugin enable ethos.mullvad
```

Do **not** edit `/usr/share/omarchy/`. Do **not** automate `mullvad connect`, `disconnect`, `login`, `logout`, or `lockdown-mode set` in tests.

---

### Task 1: Test harness and fixtures

**Files:**
- Create: `package.json`
- Create: `.gitignore`
- Create: `tests/fixtures/relay-list.txt`
- Create: `tests/fixtures/status-disconnected.json`
- Create: `tests/model.test.js`

- [ ] **Step 1: Write package.json and gitignore**

```json
{
  "name": "ethos-mullvad",
  "private": true,
  "scripts": {
    "test": "node --test tests/*.test.js"
  }
}
```

```
node_modules/
.superpowers/
```

- [ ] **Step 2: Write fixtures**

`tests/fixtures/relay-list.txt` (keep this exact text; tests depend on it):

```
Albania (al)
	Tirana (tia) @ 41.32795°N, 19.81902°W
		al-tia-wg-001 (103.124.165.2) - hosted by iRegister (rented)
Sweden (se)
	Gothenburg (got) @ 57.70887°N, 11.97456°W
		se-got-wg-001 (193.138.218.74) - hosted by 31173 (owned)
		se-got-wg-004 (193.138.218.82) - hosted by 31173 (owned)
	Malmö (mma) @ 55.60587°N, 13.00073°W
		se-mma-wg-001 (193.138.218.90) - hosted by 31173 (owned)
United States (us)
	New York (nyc) @ 40.71427°N, 74.00597°W
		us-nyc-wg-301 (146.70.116.2) - hosted by M247 (rented)
```

`tests/fixtures/status-disconnected.json` (shape taken from a real `mullvad status --json` on a disconnected box; IPs are not used by the parser):

```json
{"state":"disconnected","details":{"location":{"ipv4":"38.59.1.43","ipv6":null,"country":"United States","city":"Edgewater","latitude":28.948,"longitude":-80.8979,"mullvad_exit_ip":false,"hostname":null,"entry_hostname":null,"obfuscator_hostname":null},"locked_down":false}}
```

- [ ] **Step 3: Write the first failing test**

`tests/model.test.js`:

```javascript
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const Model = require("../Model.js");

const relayList = fs.readFileSync(
  path.join(__dirname, "fixtures/relay-list.txt"),
  "utf8"
);

test("parseRelayList returns one row per country+city and drops hostnames", () => {
  const cities = Model.parseRelayList(relayList);
  assert.deepEqual(cities, [
    { country: "Albania", countryCode: "al", city: "Tirana", cityCode: "tia" },
    { country: "Sweden", countryCode: "se", city: "Gothenburg", cityCode: "got" },
    { country: "Sweden", countryCode: "se", city: "Malmö", cityCode: "mma" },
    { country: "United States", countryCode: "us", city: "New York", cityCode: "nyc" }
  ]);
});
```

- [ ] **Step 4: Run test to verify it fails**

Run: `cd /home/ethos/Projects/omarchy-mullvad && node --test tests/model.test.js`

Expected: FAIL, `Cannot find module '../Model.js'`

- [ ] **Step 5: Commit harness only after Task 2 goes green** (do not commit a red suite). Continue to Task 2 in the same sitting.

---

### Task 2: `parseRelayList`

**Files:**
- Create: `Model.js`
- Test: `tests/model.test.js`

- [ ] **Step 1: Add failing tests for empty and garbage input** (keep the Task 1 test)

Append to `tests/model.test.js`:

```javascript
test("parseRelayList returns [] for empty or garbage stdout", () => {
  assert.deepEqual(Model.parseRelayList(""), []);
  assert.deepEqual(Model.parseRelayList(null), []);
  assert.deepEqual(Model.parseRelayList("error: daemon is offline"), []);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test tests/model.test.js`

Expected: FAIL, module not found.

- [ ] **Step 3: Implement `Model.js`**

```javascript
function parseRelayList(raw) {
  var text = String(raw || "");
  if (text === "") return [];
  var lines = text.split(/\r?\n/);
  var cities = [];
  var country = "";
  var countryCode = "";
  var seen = {};

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (!line) continue;

    if (!/^\s/.test(line)) {
      var countryMatch = line.match(/^(.+?)\s+\(([a-z]{2})\)\s*$/);
      if (countryMatch) {
        country = countryMatch[1];
        countryCode = countryMatch[2];
      }
      continue;
    }

    var cityMatch = line.match(/^\s+(.+?)\s+\(([a-z]{3})\)\s+@/);
    if (!cityMatch || countryCode === "") continue;
    var key = countryCode + " " + cityMatch[2];
    if (seen[key]) continue;
    seen[key] = true;
    cities.push({
      country: country,
      countryCode: countryCode,
      city: cityMatch[1],
      cityCode: cityMatch[2]
    });
  }

  return cities;
}

function filterCities(cities, query) {
  return cities || [];
}

function normalizeAccountNumber(raw) {
  return { ok: false, digits: "", error: "Enter your 16-digit account number." };
}

function parseStatusJson(raw) {
  return {
    state: "error",
    active: false,
    locationCountry: "",
    locationCity: "",
    lockedDown: false,
    mullvadExitIp: false
  };
}

function parseAccountGet(raw, exitCode) {
  return { loggedIn: false, accountExpiry: "", deviceName: "", error: "" };
}

function parseLockdownGet(raw) {
  return false;
}

function parseRelayGet(raw) {
  return { country: "", city: "" };
}

function mergeRecentCities(recentKeys, cities) {
  return cities || [];
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseRelayList: parseRelayList,
    filterCities: filterCities,
    normalizeAccountNumber: normalizeAccountNumber,
    parseStatusJson: parseStatusJson,
    parseAccountGet: parseAccountGet,
    parseLockdownGet: parseLockdownGet,
    parseRelayGet: parseRelayGet,
    mergeRecentCities: mergeRecentCities
  };
}
```

QML `import "Model.js" as Model` sees the functions. The `module.exports` block is inert in QML because `module` is undefined.

- [ ] **Step 4: Run tests**

Run: `node --test tests/model.test.js`

Expected: PASS for both `parseRelayList` tests. Other functions are stubs; do not test them yet.

- [ ] **Step 5: Commit**

```bash
git add package.json .gitignore Model.js tests/
git commit -m "feat: parse Mullvad relay list into country and city rows"
```

---

### Task 3: City search and recent-city merge

**Files:**
- Modify: `Model.js`
- Modify: `tests/model.test.js`

- [ ] **Step 1: Write failing tests**

```javascript
test("filterCities matches country, city, and codes case-insensitively", () => {
  const cities = Model.parseRelayList(relayList);
  const got = Model.filterCities(cities, "got");
  assert.equal(got.length, 1);
  assert.equal(got[0].city, "Gothenburg");

  const sweden = Model.filterCities(cities, "se");
  assert.equal(sweden.length, 2);
  assert.equal(sweden[0].countryCode, "se");
  assert.equal(sweden[1].countryCode, "se");

  const nyc = Model.filterCities(cities, "new yo");
  assert.equal(nyc.length, 1);
  assert.equal(nyc[0].cityCode, "nyc");
});

test("filterCities with blank query returns every city", () => {
  const cities = Model.parseRelayList(relayList);
  assert.equal(Model.filterCities(cities, "  ").length, cities.length);
});

test("mergeRecentCities puts remembered keys first without duplicating", () => {
  const cities = Model.parseRelayList(relayList);
  const merged = Model.mergeRecentCities(["us nyc", "se got"], cities);
  assert.equal(merged[0].cityCode, "nyc");
  assert.equal(merged[1].cityCode, "got");
  assert.equal(merged.length, cities.length);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test tests/model.test.js`

Expected: FAIL — `got.length` is 4 (stub returns the full list) or similar assertion error, not a syntax error.

- [ ] **Step 3: Implement**

Replace the stubs:

```javascript
function filterCities(cities, query) {
  var list = cities || [];
  var needle = String(query || "").trim().toLowerCase();
  if (needle === "") return list.slice();
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var row = list[i];
    var hay = [
      row.country,
      row.countryCode,
      row.city,
      row.cityCode,
      row.country + " " + row.city,
      row.countryCode + " " + row.cityCode
    ].join("\n").toLowerCase();
    if (hay.indexOf(needle) !== -1) out.push(row);
  }
  return out;
}

function mergeRecentCities(recentKeys, cities) {
  var list = cities || [];
  var recents = recentKeys || [];
  var byKey = {};
  var i;
  for (i = 0; i < list.length; i++) {
    byKey[list[i].countryCode + " " + list[i].cityCode] = list[i];
  }
  var out = [];
  var seen = {};
  for (i = 0; i < recents.length && out.length < 5; i++) {
    var key = String(recents[i] || "");
    if (!byKey[key] || seen[key]) continue;
    out.push(byKey[key]);
    seen[key] = true;
  }
  for (i = 0; i < list.length; i++) {
    var k = list[i].countryCode + " " + list[i].cityCode;
    if (seen[k]) continue;
    out.push(list[i]);
  }
  return out;
}
```

- [ ] **Step 4: Run tests**

Run: `node --test tests/model.test.js`

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Model.js tests/model.test.js
git commit -m "feat: filter and pin recent Mullvad cities"
```

---

### Task 4: Account number, status JSON, account/lockdown/relay text

**Files:**
- Modify: `Model.js`
- Modify: `tests/model.test.js`

- [ ] **Step 1: Write failing tests**

```javascript
test("normalizeAccountNumber strips spaces and requires 16 digits", () => {
  assert.deepEqual(Model.normalizeAccountNumber("1234 5678 9012 3456"), {
    ok: true,
    digits: "1234567890123456",
    error: ""
  });
  assert.equal(Model.normalizeAccountNumber("123").ok, false);
  assert.equal(Model.normalizeAccountNumber("abcdefghijklmnop").ok, false);
  assert.equal(Model.normalizeAccountNumber("").error, "Enter your 16-digit account number.");
});

test("parseStatusJson ignores visible location when disconnected", () => {
  const raw = fs.readFileSync(
    path.join(__dirname, "fixtures/status-disconnected.json"),
    "utf8"
  );
  const status = Model.parseStatusJson(raw);
  assert.equal(status.state, "disconnected");
  assert.equal(status.active, false);
  assert.equal(status.locationCountry, "");
  assert.equal(status.locationCity, "");
  assert.equal(status.mullvadExitIp, false);
  assert.equal(status.lockedDown, false);
});

test("parseStatusJson uses location only when connected", () => {
  const raw = JSON.stringify({
    state: "connected",
    details: {
      location: {
        country: "Sweden",
        city: "Gothenburg",
        mullvad_exit_ip: true,
        hostname: "se-got-wg-001"
      },
      locked_down: false
    }
  });
  const status = Model.parseStatusJson(raw);
  assert.equal(status.state, "connected");
  assert.equal(status.active, true);
  assert.equal(status.locationCountry, "Sweden");
  assert.equal(status.locationCity, "Gothenburg");
  assert.equal(status.mullvadExitIp, true);
});

test("parseStatusJson returns error state for garbage", () => {
  const status = Model.parseStatusJson("not-json");
  assert.equal(status.state, "error");
  assert.equal(status.active, false);
});

test("parseAccountGet reads expiry and device", () => {
  const raw = [
    "Mullvad account:    0000000000000000",
    "Expires at:         2026-09-12 20:25:29 -04:00",
    "Device name:        Deep Robin"
  ].join("\n");
  const account = Model.parseAccountGet(raw, 0);
  assert.equal(account.loggedIn, true);
  assert.equal(account.deviceName, "Deep Robin");
  assert.equal(account.accountExpiry, "2026-09-12");
  assert.equal(account.error, "");
});

test("parseAccountGet treats non-zero exit as logged out", () => {
  const account = Model.parseAccountGet("Not logged in", 1);
  assert.equal(account.loggedIn, false);
  assert.equal(account.deviceName, "");
});

test("parseLockdownGet reads on/off", () => {
  assert.equal(
    Model.parseLockdownGet("Block traffic when the VPN is disconnected: off"),
    false
  );
  assert.equal(
    Model.parseLockdownGet("Block traffic when the VPN is disconnected: on"),
    true
  );
});

test("parseRelayGet reads country and optional city", () => {
  const countryOnly = Model.parseRelayGet("    Location:               country se");
  assert.deepEqual(countryOnly, { country: "se", city: "" });
  const both = Model.parseRelayGet("    Location:               country se city got");
  assert.deepEqual(both, { country: "se", city: "got" });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test tests/model.test.js`

Expected: FAIL on `ok: true` / empty location assertions (stubs), not a load error.

- [ ] **Step 3: Implement the parsers**

```javascript
function normalizeAccountNumber(raw) {
  var digits = String(raw || "").replace(/\D/g, "");
  if (digits.length === 16) return { ok: true, digits: digits, error: "" };
  return { ok: false, digits: digits, error: "Enter your 16-digit account number." };
}

function emptyStatus(state) {
  return {
    state: state || "error",
    active: false,
    locationCountry: "",
    locationCity: "",
    lockedDown: false,
    mullvadExitIp: false
  };
}

function parseStatusJson(raw) {
  var parsed;
  try {
    parsed = JSON.parse(String(raw || ""));
  } catch (e) {
    return emptyStatus("error");
  }
  if (!parsed || typeof parsed !== "object") return emptyStatus("error");

  var state = String(parsed.state || "error");
  var details = parsed.details || {};
  var location = details.location || {};
  var exitIp = location.mullvad_exit_ip === true;
  var tunnelOpen = state === "connected" || state === "connecting" || state === "disconnecting";
  var useLocation = tunnelOpen && (exitIp || !!location.hostname);

  return {
    state: state,
    active: state === "connected",
    locationCountry: useLocation ? String(location.country || "") : "",
    locationCity: useLocation ? String(location.city || "") : "",
    lockedDown: details.locked_down === true,
    mullvadExitIp: exitIp
  };
}

function parseAccountGet(raw, exitCode) {
  if (exitCode !== 0) {
    return { loggedIn: false, accountExpiry: "", deviceName: "", error: String(raw || "").trim() };
  }
  var text = String(raw || "");
  var expiryLine = text.match(/Expires at:\s+(\d{4}-\d{2}-\d{2})/);
  var deviceLine = text.match(/Device name:\s+(.+)$/m);
  var accountLine = text.match(/Mullvad account:\s+(\d+)/);
  if (!accountLine) {
    return { loggedIn: false, accountExpiry: "", deviceName: "", error: text.trim() };
  }
  return {
    loggedIn: true,
    accountExpiry: expiryLine ? expiryLine[1] : "",
    deviceName: deviceLine ? deviceLine[1].trim() : "",
    error: ""
  };
}

function parseLockdownGet(raw) {
  return /:\s*on\s*$/im.test(String(raw || ""));
}

function parseRelayGet(raw) {
  var text = String(raw || "");
  var country = "";
  var city = "";
  var countryMatch = text.match(/\bcountry\s+([a-z]{2})\b/i);
  var cityMatch = text.match(/\bcity\s+([a-z]{3})\b/i);
  if (countryMatch) country = countryMatch[1].toLowerCase();
  if (cityMatch) city = cityMatch[1].toLowerCase();
  return { country: country, city: city };
}
```

- [ ] **Step 4: Run tests**

Run: `node --test tests/model.test.js`

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Model.js tests/model.test.js tests/fixtures/status-disconnected.json
git commit -m "feat: parse Mullvad status, account, lockdown, and relay text"
```

---

### Task 5: Read-only CLI contract script

**Files:**
- Create: `tests/cli-contract.sh`

This does **not** toggle the tunnel. It only checks that live CLI output still parses.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v mullvad >/dev/null; then
  echo "SKIP: mullvad not on PATH"
  exit 0
fi

node --input-type=commonjs <<'EOF'
const { execFileSync } = require("node:child_process");
const assert = require("node:assert/strict");
const Model = require("./Model.js");

function run(args) {
  try {
    return { code: 0, out: execFileSync("mullvad", args, { encoding: "utf8" }) };
  } catch (err) {
    return { code: err.status || 1, out: String(err.stdout || "") + String(err.stderr || "") };
  }
}

const status = Model.parseStatusJson(run(["status", "--json"]).out);
assert.ok(["disconnected", "connected", "connecting", "disconnecting", "error"].includes(status.state));
if (status.state === "disconnected") {
  assert.equal(status.locationCity, "");
}

const account = Model.parseAccountGet(run(["account", "get"]).out, run(["account", "get"]).code);
assert.equal(typeof account.loggedIn, "boolean");

const lockdown = Model.parseLockdownGet(run(["lockdown-mode", "get"]).out);
assert.equal(typeof lockdown, "boolean");

const relay = Model.parseRelayGet(run(["relay", "get"]).out);
assert.equal(typeof relay.country, "string");

const cities = Model.parseRelayList(run(["relay", "list"]).out);
assert.ok(cities.length > 10);
assert.ok(cities.every((c) => c.countryCode && c.cityCode && !/-wg-/.test(c.city)));

console.log("cli-contract ok", {
  state: status.state,
  loggedIn: account.loggedIn,
  cities: cities.length
});
EOF
```

- [ ] **Step 2: Run it**

Run: `chmod +x tests/cli-contract.sh && tests/cli-contract.sh`

Expected: `cli-contract ok { state: 'disconnected', loggedIn: true, cities: <large number> }` on this machine.

- [ ] **Step 3: Commit**

```bash
git add tests/cli-contract.sh
git commit -m "test: add read-only Mullvad CLI contract check"
```

---

### Task 6: Manifest

**Files:**
- Create: `manifest.json`

- [ ] **Step 1: Write the manifest**

```json
{
  "schemaVersion": 1,
  "id": "ethos.mullvad",
  "name": "Mullvad",
  "version": "1.0.0",
  "author": "ethos",
  "license": "MIT",
  "description": "Mullvad status, connect/disconnect, city picker, login, and lockdown in the Omarchy bar.",
  "kinds": ["bar-widget"],
  "entryPoints": {
    "barWidget": "Panel.qml"
  },
  "barWidget": {
    "displayName": "Mullvad",
    "description": "Toggle Mullvad, pick a city, sign in, and control lockdown.",
    "category": "Network",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": {
      "refreshIntervalSec": 30,
      "recentCities": []
    },
    "schema": [
      {
        "key": "refreshIntervalSec",
        "type": "integer",
        "label": "Fallback refresh interval (seconds)",
        "min": 5,
        "max": 3600,
        "step": 5,
        "defaultValue": 30
      }
    ]
  }
}
```

- [ ] **Step 2: Validate**

Run: `omarchy plugin validate /home/ethos/Projects/omarchy-mullvad`

Expected: success. If the command wants a directory with `Panel.qml` already present, create an empty placeholder `Panel.qml` containing `import QtQuick; Item {}` so validation can see the entry point, then replace it in Task 9.

- [ ] **Step 3: Commit**

```bash
git add manifest.json
git commit -m "feat: add ethos.mullvad plugin manifest"
```

---

### Task 7: Mullvad icon

**Files:**
- Create: `MullvadIcon.qml`

No QML unit harness. Match `/usr/share/omarchy/shell/plugins/panels/tailscale/TailscaleIcon.qml` (size, color, crossed, warning badge). Draw the official silhouette: circle + upright cross.

- [ ] **Step 1: Write MullvadIcon.qml**

```qml
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool crossed: false
  property bool warning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real stroke: Math.max(1.6, iconSize * 0.12)
  readonly property real pad: iconSize * 0.08

  Rectangle {
    id: ring
    anchors.fill: parent
    anchors.margins: root.pad
    radius: width / 2
    color: "transparent"
    border.color: root.color
    border.width: root.stroke
  }

  Rectangle {
    width: root.stroke
    height: ring.height * 0.62
    radius: width / 2
    color: root.color
    anchors.horizontalCenter: ring.horizontalCenter
    anchors.verticalCenter: ring.verticalCenter
  }

  Rectangle {
    width: ring.width * 0.62
    height: root.stroke
    radius: height / 2
    color: root.color
    anchors.horizontalCenter: ring.horizontalCenter
    anchors.verticalCenter: ring.verticalCenter
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.22
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add MullvadIcon.qml
git commit -m "feat: add themed Mullvad bar icon"
```

---

### Task 8: Service.qml

**Files:**
- Create: `Service.qml`

This is process plumbing. Parsing stays in `Model.js`. Follow Tailscale’s `Process` + `StdioCollector` for one-shots and idle’s `SplitParser` for listen.

Published API the panel binds to (names must match this list):

- properties: `installed`, `daemonRunning`, `loggedIn`, `accountExpiry`, `deviceName`, `active`, `busy`, `state`, `locationCountry`, `locationCity`, `relayCountry`, `relayCity`, `lockdown`, `cities`, `lastError`, `actionStatus`, `settings`
- methods: `refresh()`, `loadCities()`, `installDaemon()`, `startDaemon()`, `login(accountNumber)`, `logout()`, `toggleTunnel()`, `connectTunnel()`, `disconnectTunnel()`, `setCity(countryCode, cityCode)`, `setLockdown(on)`

Rules baked into the methods:

- One action process at a time. If `actionProcess.running`, ignore a new action except `setCity`, which stores `_pendingCity` and runs after the current action exits.
- `logout()` calls `disconnectTunnel` first when `active`. If disconnect fails, do not logout.
- `login` runs `normalizeAccountNumber` first. Invalid → set `lastError`, do not start a process.
- Install is `["omarchy", "pkg", "add", "mullvad-vpn-daemon"]` only. Never `pkg drop`. Never `sudo`.
- After install, `systemctl enable --now mullvad-daemon.service` via `omarchy`/`systemctl` without a shell string built from user input.
- Never log the account number (`console.log` of the field is forbidden).
- Listen command is exactly `["mullvad", "status", "--json", "listen"]`.
- Listen exit → restart with backoff 1s, 2s, 5s, cap 30s, and snapshot on `refreshIntervalSec` while down.

- [ ] **Step 1: Write Service.qml**

```qml
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

  function applyStatus(status) {
    if (!status || status.state === "error") {
      daemonRunning = false
      return
    }
    daemonRunning = true
    state = status.state
    active = status.active
    locationCountry = status.locationCountry
    locationCity = status.locationCity
    if (status.lockedDown) lockdown = true
  }

  function applyAccount(account) {
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
    if (listenProcess.running) listenProcess.running = false
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
    if (active) {
      _actionKind = "logout-after-disconnect"
      disconnectTunnel()
      return
    }
    clearError()
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
    if (actionProcess.running && _actionKind !== "logout-after-disconnect") return
    if (actionProcess.running) return
    clearError()
    actionStatus = "Disconnecting…"
    if (_actionKind !== "logout-after-disconnect") _actionKind = "disconnect"
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
      fallbackPoll.interval = root.refreshIntervalSec * 1000
      fallbackPoll.running = true
      listenRestart.interval = root._listenBackoffMs
      listenRestart.restart()
      root._listenBackoffMs = Math.min(30000, root._listenBackoffMs * 2)
      if (root._listenBackoffMs === 2000) root._listenBackoffMs = 2000
      if (root._listenBackoffMs === 4000) root._listenBackoffMs = 5000
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
      else {
        root.daemonRunning = false
        root.lastError = String(snapshotErr.text || "").trim() || "Mullvad daemon is not running"
      }
      if (root.installed) {
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
```

Backoff in `onExited` as written is messy. After paste, replace the three `if (_listenBackoffMs === …)` lines with a single assignment already using `Math.min(30000, root._listenBackoffMs * 2)` and seed `_listenBackoffMs` so the sequence is 1000 → 2000 → 5000 → 10000 → 20000 → 30000. Close enough to the spec (1, 2, 5, cap 30).

- [ ] **Step 2: Fix logout/disconnect race**

`disconnectTunnel` currently bails if `actionProcess.running`. Change it so `logout()` sets `_actionKind = "logout-after-disconnect"` and then starts `["mullvad", "disconnect"]` directly (inline the command) instead of calling `disconnectTunnel`, which would no-op. In `logout()`:

```qml
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
```

Delete the broken `if (active) { _actionKind = "logout-after-disconnect"; disconnectTunnel(); return }` path.

- [ ] **Step 3: Commit**

```bash
git add Service.qml
git commit -m "feat: add Mullvad CLI service with listen and actions"
```

---

### Task 9: Panel.qml

**Files:**
- Create: `Panel.qml`

Copy structure from Tailscale (`Panel` + `BarIconButton` + `KeyboardPanel` + `PanelHero` + `ToggleSwitch` + `TextField` + `CursorSurface`). Bodies are mutually exclusive: Install / Login / Ready.

- [ ] **Step 1: Write Panel.qml**

```qml
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ethos.mullvad"
  ipcTarget: "ethos.mullvad"
  manageIpc: false

  property string focusSection: "header"
  property int cityIndex: 0
  property bool cursorActive: false
  property string cityQuery: ""
  property string accountField: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: mullvad.active ? foreground : dim
  readonly property color barIconColor: mullvad.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && mullvad.installed && mullvad.loggedIn
  readonly property var recentKeys: settings.recentCities instanceof Array ? settings.recentCities : []
  readonly property var visibleCities: Model.filterCities(Model.mergeRecentCities(recentKeys, mullvad.cities), cityQuery)
  readonly property string heroTitle: {
    if (!mullvad.installed) return "Mullvad"
    if (!mullvad.loggedIn) return "Mullvad"
    if (mullvad.locationCity !== "") return mullvad.locationCity
    return "Mullvad"
  }
  readonly property string heroMeta: {
    if (!mullvad.installed) return "Mullvad is not installed"
    if (!mullvad.loggedIn) return "Not logged in"
    if (mullvad.active && mullvad.locationCountry !== "") return mullvad.locationCountry + " · Connected"
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
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0) {
        focusSection = "lockdown"
      }
      return
    }
    if (focusSection === "lockdown") {
      if (dy < 0) { focusSection = "header"; return }
      if (dy > 0 && visibleCities.length > 0) { focusSection = "cities"; cityIndex = 0 }
      return
    }
    if (focusSection === "cities") {
      if (dy < 0 && cityIndex === 0) { focusSection = "lockdown"; return }
      cityIndex = Math.max(0, Math.min(visibleCities.length - 1, cityIndex + dy))
    }
  }

  function activateCursor() {
    if (focusSection === "header") mullvad.toggleTunnel()
    else if (focusSection === "lockdown") mullvad.setLockdown(!mullvad.lockdown)
    else if (focusSection === "cities") chooseCity(selectedCity())
    else if (focusSection === "install") mullvad.installDaemon()
    else if (focusSection === "login") submitLogin()
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    cityQuery = ""
    if (mullvad.installed && mullvad.cities.length === 0) mullvad.loadCities()
    ensureCursor()
  }

  Service {
    id: mullvad
    settings: root.settings
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
          crossed: mullvad.installed && mullvad.loggedIn && !mullvad.active && mullvad.state !== "connecting"
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
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") mullvad.toggleTunnel()
        else if (t === "l" || t === "L") mullvad.setLockdown(!mullvad.lockdown)
        else if (t === "/") citySearch.forceActiveFocus()
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

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.focusSection = "header"; root.cursorActive = true }

            PanelHero {
              id: hero
              width: parent.width
              title: root.heroTitle
              meta: root.heroMeta
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: mullvad.active ? 1.0 : 0.5
              iconComponent: Component {
                MullvadIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  crossed: mullvad.installed && mullvad.loggedIn && !mullvad.active
                  warning: !mullvad.installed || !mullvad.loggedIn
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: mullvad.installed && mullvad.loggedIn
                  checked: mullvad.active
                  busy: mullvad.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: mullvad.toggleTunnel()
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
            visible: !mullvad.installed
            width: parent.width
            implicitHeight: installCol.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground
            onClicked: mullvad.installDaemon()

            Column {
              id: installCol
              width: parent.width
              spacing: Style.space(8)
              Text {
                width: parent.width
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
              echoMode: TextInput.Normal
              text: root.accountField
              onTextChanged: root.accountField = text
              onAccepted: root.submitLogin()
            }

            CursorSurface {
              width: parent.width
              implicitHeight: Style.space(36)
              foreground: root.foreground
              onClicked: root.submitLogin()
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Log in"
                color: root.foreground
                font.family: root.fontFamily
              }
            }
          }

          CursorSurface {
            visible: mullvad.installed && mullvad.loggedIn
            width: parent.width
            implicitHeight: Style.space(36)
            foreground: root.foreground
            onClicked: { root.focusSection = "lockdown"; root.cursorActive = true; mullvad.setLockdown(!mullvad.lockdown) }

            Row {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              spacing: Style.space(10)
              Text {
                text: "Lockdown"
                color: root.foreground
                font.family: root.fontFamily
              }
              Text {
                text: mullvad.lockdown ? "On" : "Off"
                color: root.dim
                font.family: root.fontFamily
              }
            }
          }

          Column {
            visible: mullvad.installed && mullvad.loggedIn
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
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down) { root.focusSection = "cities"; root.moveCursor(0, 1); event.accepted = true }
                if (event.key === Qt.Key_Escape) { keyCatcher.forceActiveFocus(); event.accepted = true }
              }
            }

            Text {
              visible: root.visibleCities.length === 0
              text: "No cities found."
              color: root.dim
              font.family: root.fontFamily
            }

            Repeater {
              model: root.visibleCities
              CursorSurface {
                required property var modelData
                required property int index
                width: column.width
                implicitHeight: Style.space(32)
                foreground: root.foreground
                onClicked: { root.cityIndex = index; root.chooseCity(modelData) }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.country + " · " + modelData.city
                  color: (modelData.countryCode === mullvad.relayCountry && modelData.cityCode === mullvad.relayCity) ? root.foreground : root.dim
                  font.family: root.fontFamily
                }
              }
            }
          }

          Text {
            visible: mullvad.installed && mullvad.loggedIn
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
}
```

If `TextField` does not accept `echoMode` (Omarchy’s `qs.Ui.TextField` may differ from QtQuick.Controls), drop that line. Check `/usr/share/omarchy/shell/plugins/panels/network/Panel.qml` around the passphrase field and match its properties.

If `barForeground` is not in scope on `Panel`, use `foreground` like other color fallbacks.

- [ ] **Step 2: Symlink and rescan**

```bash
mkdir -p ~/.config/omarchy/plugins
ln -sfn /home/ethos/Projects/omarchy-mullvad ~/.config/omarchy/plugins/ethos.mullvad
omarchy plugin validate ~/.config/omarchy/plugins/ethos.mullvad
omarchy-shell shell rescanPlugins
omarchy plugin enable ethos.mullvad --yes
```

Expected: plugin listed, widget appears on the right of the bar. If enable wants a TTY confirm, use whatever `--yes` equivalent `omarchy plugin enable --help` documents.

- [ ] **Step 3: Commit**

```bash
git add Panel.qml
git commit -m "feat: add Mullvad bar panel with install, login, and city list"
```

---

### Task 10: README and local enable notes

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README.md**

```markdown
# Mullvad for Omarchy

Bar widget for [Omarchy](https://omarchy.org) Quattro. Wraps the official `mullvad` CLI.

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-mullvad.git --enable
```

Or, from a local checkout:

```bash
ln -sfn /path/to/omarchy-mullvad ~/.config/omarchy/plugins/ethos.mullvad
omarchy-shell shell rescanPlugins
omarchy plugin enable ethos.mullvad
```

If `mullvad` is missing, open the widget and click **Install Mullvad**. That runs `omarchy pkg add mullvad-vpn-daemon` (Arch extra). It will not remove the official Mullvad app if you already have it.

## Use

- Left click: panel
- Right click: connect / disconnect (opens the panel if you are logged out)
- Middle click: refresh
- Panel: account number login, city search, lockdown, log out

Keys inside the panel: `j`/`k` move, Enter selects, `/` search, `t` tunnel, `l` lockdown, Esc closes.

## Requirements

- Omarchy 4 (Quattro) / `omarchy-shell`
- `mullvad` 2026.3+ (installed for you from the panel if missing)

## Dev

```bash
node --test tests/*.test.js
tests/cli-contract.sh
```

`cli-contract.sh` is read-only. It never connects, disconnects, logs in, or logs out.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add Mullvad plugin README"
```

---

### Task 11: Manual v1 checklist

Do this on the live desktop. Do **not** script login/logout/connect.

- [ ] **Step 1: Theme fit** — icon sits on the right next to Network, theme-colored, no yellow.
- [ ] **Step 2: Ready path** — this machine is already logged in. Panel shows device name, expiry, city list, lockdown Off, switch off (disconnected). Search `got` → Gothenburg. Do not pick a city until the user is watching.
- [ ] **Step 3: Right-click** — with the user watching, right-click once to connect, once to disconnect. Hero updates from listen, not from a 30s poll.
- [ ] **Step 4: Missing CLI** — `PATH="/usr/bin" which mullvad` still finds it. To simulate missing: temporarily rename is too destructive. Instead, in a throwaway copy of Service, skip this if the user does not want PATH games. Preferred: `omarchy plugin disable ethos.mullvad`, confirm the bar slot vanishes, re-enable.
- [ ] **Step 5: Install no-op** — on this machine Install must not show. Ready must show.
- [ ] **Step 6: Errors** — flip lockdown with the user watching; confirm `mullvad lockdown-mode get` matches the row. Flip it back.
- [ ] **Step 7: Tests still pass**

```bash
cd /home/ethos/Projects/omarchy-mullvad && node --test tests/*.test.js && tests/cli-contract.sh
```

Expected: PASS / `cli-contract ok`.

- [ ] **Step 8: Final commit only if checklist caused code fixes**

If you changed QML during the walkthrough:

```bash
git add -u
git commit -m "fix: Mullvad panel review fixes"
```

---

## Spec coverage

| Spec item | Task |
|---|---|
| `ethos.mullvad` manifest, bar-widget, right | 6 |
| `Model.js` relay / search / account / status / lockdown / relay get | 2–4 |
| Disconnected JSON must not show Edgewater as VPN city | 4 |
| `mullvad status --json listen` | 8 |
| Fallback poll + backoff | 8 |
| Install via `omarchy pkg add mullvad-vpn-daemon` | 8–9 |
| Never uninstall official GUI | 8, 10 |
| Login field, 16 digits, no persist | 4, 8, 9 |
| Logout disconnects first | 8 |
| Tailscale bar clicks | 9 |
| Themed Mullvad mark | 7, 9 |
| Ready panel: hero, switch, lockdown, search, footer | 9 |
| Keyboard j/k t l / Esc | 9 |
| recentCities via `updateEntryInline` | 9 |
| Read-only CLI contract | 5 |
| Manual checklist | 11 |
| README / omarchyplugins distribution | 10 |
| Specific hostnames, LAN, DNS, auto-connect | not implemented (non-goals) |

## Placeholder / consistency notes

- Service property names in Task 8 are the names Task 9 binds (`mullvad.loggedIn`, `mullvad.setCity`, etc.).
- Listen command is `mullvad status --json listen` in every task.
- Account numbers in tests are synthetic (`1234 5678 9012 3456`). Never commit output from `mullvad account get`.
- `Panel.qml` may need small property-name tweaks to match `qs.Ui.TextField` / `Panel` (`barForeground`). Fix against the live Tailscale panel, do not invent a second API.
