# Mullvad Omarchy plugin

Date: 2026-08-15
Status: Draft, pending user review
Repo: `/home/ethos/Projects/omarchy-mullvad`
Plugin id: `ethos.mullvad`

A community Omarchy Quattro shell plugin that drives the official Mullvad CLI from the bar. Destination: a public git repo listed on omarchyplugins.com.

## Problem

On Omarchy, Mullvad is a terminal app: `mullvad connect`, `mullvad status`, `mullvad disconnect`, `mullvad relay set location`. There is no first-party Mullvad widget. The Tailscale widget can pick Mullvad *exit nodes through Tailscale*. That is a different product. This plugin is native Mullvad.

## Decisions (locked)

| Topic | Choice |
|---|---|
| Audience | Personal daily driver and a community plugin |
| Account surface | Login, logout, expiry, device name |
| Relay pick | Country + city, with search. Specific hostnames are a later follow-up |
| Bar | Tailscale pattern: left click opens the panel, right click toggles the tunnel, icon shows state |
| Lockdown | In v1 (kill switch). Auto-connect, LAN, DNS, split tunnel are out |
| Missing CLI | Panel Install action runs `omarchy pkg add mullvad-vpn-daemon` |
| Official GUI | If `mullvad-vpn` is already installed, leave it. Never uninstall anything |
| Login | 16-digit account number field in the panel. Paste-friendly. Not a terminal. Not the official GUI |
| Icon | Official Mullvad circle-and-cross silhouette, painted in the theme color |
| Panel | One Tailscale-shaped panel. Hero + switch, lockdown row, city search, account footer. Install/login replace the list when those states apply |
| Implementation | Same file layout as Tailscale. Tunnel state from `mullvad status --json listen`. No private Mullvad socket |

## Non-goals (v1)

- Specific relay hostnames
- IPs, throughput, protocol, WireGuard vs OpenVPN
- Auto-connect, allow LAN, custom DNS, split tunnel, anti-censorship, multihop
- Talking to Mullvad’s management socket or D-Bus
- Editing `/usr/share/omarchy/` or shipping as `omarchy.mullvad`
- Uninstalling or replacing the official Mullvad app
- Storing the account number on disk

## Architecture

Third-party plugin. Git repo with `manifest.json` at the root. Installed with:

```bash
omarchy plugin add <git-url> --enable
```

On disk after install: `~/.config/omarchy/plugins/ethos.mullvad/`.

**Kind:** `bar-widget` only. `category: "Network"`. `allowMultiple: false`. `defaultSection: "right"`.

**Process boundary:** every action is a `mullvad` (or `omarchy pkg add`) argv. The only long-lived child is `mullvad status --json listen`. Restart it if it dies. `mullvad status listen` without `--json` is human text and is not used.

**Files (repo root):**

| File | Responsibility |
|---|---|
| `manifest.json` | Plugin contract, widget schema |
| `MullvadIcon.qml` | Themed mark + crossed + warning badge |
| `Model.js` | Pure parse/filter: status JSON, relay list text, account number digits |
| `Service.qml` | CLI ownership, listen process, action processes, published state |
| `Panel.qml` | Bar button, panel UI, keyboard |
| `README.md` | Install, requirements, shortcuts |

Copy Tailscale *patterns* (`PanelHero`, `ToggleSwitch`, `KeyboardPanel`, `BarIconButton`, `CursorSurface`). Do not fork `omarchy.tailscale`.

## Manifest

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
  "entryPoints": { "barWidget": "Panel.qml" },
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

`recentCities` is written by the plugin into the bar layout entry. It is not a user-facing schema field.

## Service state

`Service.qml` is a singleton the panel binds to. Published properties:

| Property | Meaning |
|---|---|
| `installed` | `mullvad` is on `PATH` |
| `daemonRunning` | A status snapshot or listen event succeeded |
| `loggedIn` | `mullvad account get` succeeded |
| `accountExpiry` | Parsed expiry string, or empty |
| `deviceName` | Device name from `account get`, or empty |
| `active` | Tunnel is connected |
| `busy` | An action process or listen-restart is in flight |
| `state` | `disconnected` \| `connecting` \| `connected` \| `disconnecting` \| `error` |
| `locationCountry` | Connected Mullvad country name, or empty when disconnected |
| `locationCity` | Connected Mullvad city name, or empty when disconnected |
| `relayCountry` | Selected constraint country code (`se`) |
| `relayCity` | Selected constraint city code (`got`), or empty |
| `lockdown` | Lockdown mode is on |
| `cities` | Array of `{ country, countryCode, city, cityCode }` |
| `lastError` | Last failure sentence, or empty |
| `actionStatus` | In-progress sentence, or empty |

Disconnected `mullvad status --json` reports the *visible* (non-VPN) city and `"mullvad_exit_ip": false`. That must not be shown as the tunnel location. Use country/city from `details.location` only when `state` is `connected` (or `connecting` / `disconnecting` with a Mullvad hostname). If `mullvad_exit_ip` is false, `locationCountry` and `locationCity` stay empty.

## CLI contract

Verified against Mullvad CLI 2026.3 on this machine.

| Action | Command |
|---|---|
| Status snapshot | `mullvad status --json` |
| Live status | `mullvad status --json listen` |
| Account | `mullvad account get` |
| Login | `mullvad account login <16-digit>` |
| Logout | `mullvad account logout` |
| Connect | `mullvad connect --wait` |
| Disconnect | `mullvad disconnect` |
| Reconnect | `mullvad reconnect` |
| Relay constraint | `mullvad relay get` |
| Relay list | `mullvad relay list` |
| Set city | `mullvad relay set location <country> <city>` |
| Lockdown read | `mullvad lockdown-mode get` |
| Lockdown write | `mullvad lockdown-mode set on` / `off` |
| Install | `omarchy pkg add mullvad-vpn-daemon` |
| Daemon unit | `mullvad-daemon.service` |

Login argv is the digits only. No `bash -c`. No stdin that contains the account number in a shell string.

`mullvad relay list` is indented text, not JSON:

```
Sweden (se)
        Gothenburg (got) @ …
            se-got-wg-001 …
        Malmö (mma) @ …
```

`Model.parseRelayList` keeps one row per country+city. Hostnames are discarded in v1.

`mullvad relay set location se got` is the v1 setter.

After a city pick: if `active` or `state === "connecting"`, run `mullvad reconnect`; if the user turned the switch on against a disconnected tunnel, run `mullvad connect --wait`.

## Data flow

1. On load, probe `which mullvad`. If missing, `installed = false` and stop.
2. Snapshot `status --json`, `account get`, `lockdown-mode get`, `relay get`.
3. Start `mullvad status --json listen`. Each JSON event updates `state`, `active`, and tunnel location.
4. If listen exits, restart with backoff 1s, 2s, 5s, cap 30s. While down, snapshot on `refreshIntervalSec`.
5. `relay list` is lazy: first panel open, then cached. Refresh on middle-click or if `cities` is empty after a successful connect.
6. After login, logout, or lockdown commands, re-read account and/or lockdown. Those are not in the listen stream.
7. `recentCities` stores up to five `"se got"` keys. The city list shows those first (still in the same list, not a second section required).

The plugin does not persist the account number. The daemon holds the session.

## UI

### Bar icon

Native QML, not an SVG asset (same reason as Tailscale: tiny slot rendering). Circle + cross in `Color.foreground`.

| Condition | Drawing |
|---|---|
| `state` is `connected` | Full opacity |
| Logged in, disconnected | Dim + diagonal strike (`crossed`) |
| `connecting` / `disconnecting` | Full opacity; switch `busy` |
| `!installed` or `!loggedIn` | Warning badge `!` |
| Lockdown on, disconnected | Same as disconnected. No second badge |

Clicks on `BarIconButton`:

- Left: toggle panel
- Right: if `installed && loggedIn`, toggle tunnel; otherwise open the panel
- Middle: refresh snapshot + relay list

### Panel

One `KeyboardPanel`. Width/height follow Tailscale (`~380×560` via `fittedContentWidth/Height`).

**Missing CLI.** Hero title “Mullvad”. Body: Mullvad daemon is not installed. Primary action **Install Mullvad** → `omarchy pkg add mullvad-vpn-daemon`, then enable/start `mullvad-daemon.service` if needed, then re-probe. Polkit cancel or pacman failure sets `lastError`. No retry loop.

**Logged out.** Account number field (digits, spaces stripped on submit). Submit **Log in**. Validation before CLI: must be exactly 16 digits. Mullvad error text is shown under the field. Field is cleared after a successful login.

**Ready.**

- `PanelHero`: title = connected city or “Mullvad”; meta = `Sweden · Connected` or `Disconnected`
- Trailing `ToggleSwitch` bound to `active`
- `actionStatus` / `lastError` line
- Lockdown row with a switch (`l` key)
- Search field (`/` focuses) + city rows `Country · City`
- Footer: `deviceName · expires <date> · Log out`

Keyboard: `j`/`k` or arrows move cities, Enter selects, `t` toggles tunnel, `l` toggles lockdown, Esc closes.

### States that replace, not stack

Install, login, and ready are mutually exclusive bodies under the hero. Ready never shows a login field. Login never shows the city list.

## Error handling

- `lastError` is a user-facing sentence. `actionStatus` is the in-progress sentence.
- CLI present, daemon dead: try to start `mullvad-daemon.service` once. On failure, show “Mullvad daemon is not running” and a **Start daemon** action.
- Empty or non-16-digit login: do not call the CLI.
- Expired account: Ready panel still works; connect failure includes the expiry date. Footer already shows it.
- Logout while connected: disconnect first. If disconnect fails, do not logout.
- Connect failure: switch returns off; stderr becomes `lastError`.
- Failed city change: selection snaps back to the previous constraint; show the error.
- Only one action process at a time. A city pick during connect replaces the queued relay set; it does not stack.
- Never log the account number. Never `pkg drop`. Never raw `sudo`.

## Testing

**`Model.js` (automated, no tunnel changes)**

- Fixture `mullvad relay list` → unique country/city rows, zero hostnames.
- Search: `got` → Gothenburg; `se` → Swedish cities; `new yo` → New York. Case-insensitive.
- Empty or garbage stdout → `[]`, no throw.
- Account normalize: spaces stripped; reject unless 16 digits.
- Disconnected status JSON must not yield a tunnel city.

**CLI contract (read-only on a real machine)**

- Parse `mullvad status --json`, `relay get`, `account get`, `lockdown-mode get` in the disconnected state.
- Do not automate login, logout, connect, or lockdown in CI.

**Manual before publish**

1. Hide `mullvad` from PATH → warning badge, Install, cancel polkit → error, no loop.
2. Machine that already has the CLI → Ready, not Install. Official GUI left in place if present.
3. Logout (operator-watched) → bad number, then good number.
4. Right-click toggle, panel switch, city search + pick, lockdown on/off.
5. Drop network mid-connect → error line, switch off.
6. Theme switch → icon and panel follow the theme. No leftover Mullvad yellow.

## Distribution

- Repo root is the plugin (manifest at root).
- README: require Omarchy 4 / Quattro, `omarchy plugin add <url> --enable`, and that Install needs network + polkit.
- List on omarchyplugins.com after a public repo exists.
- License: MIT.

## Success

A user who has never used the Mullvad CLI can install the plugin, install the daemon from the panel, paste an account number, pick a city, connect, see status on the bar, right-click to disconnect, and enable lockdown. The widget looks like it belongs next to Network and Tailscale.

## Follow-ups (not v1)

- Specific hostname picker
- Auto-connect, LAN, DNS
- Live IPs / throughput
- Upstream `omarchy install service mullvad` if Omarchy wants a first-party installer later
