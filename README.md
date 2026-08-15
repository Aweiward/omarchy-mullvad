# Mullvad for Omarchy

Bar widget for [Omarchy](https://omarchy.org) Quattro. Wraps the official `mullvad` CLI.

![Mullvad panel on the Omarchy bar](preview.png)

## Install

```bash
omarchy plugin add https://github.com/Aweiward/omarchy-mullvad.git --enable
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
